import AppKit
import Foundation

enum QuarantineManager {
    static let baseDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/PlugIn Safe Cleaner/Quarantine", isDirectory: true)

    static func quarantine(items: [ScanItem]) -> QuarantineOutcome {
        let manager = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let sessionDirectory = baseDirectory.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        var records: [QuarantineRecord] = []
        var errors: [String] = []
        var administratorMoves: [(item: ScanItem, destination: URL, request: AdministratorMover.MoveRequest)] = []

        do {
            try manager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        } catch {
            return QuarantineOutcome(manifestURL: nil, moved: [], errors: ["隔離フォルダを作成できません: \(error.localizedDescription)"])
        }

        for item in items {
            guard item.isMovable else {
                errors.append("\(item.name): 安全ポリシーにより移動対象外です。")
                continue
            }
            guard manager.fileExists(atPath: item.path) else {
                errors.append("\(item.name): 元のファイルが見つかりません。")
                continue
            }

            let destination = uniqueDestination(for: item, in: sessionDirectory)
            do {
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

                if item.scope.needsAdministrator {
                    administratorMoves.append((
                        item: item,
                        destination: destination,
                        request: AdministratorMover.MoveRequest(source: item.path, destination: destination.path)
                    ))
                } else {
                    try manager.moveItem(at: URL(fileURLWithPath: item.path), to: destination)
                    records.append(QuarantineRecord(item: item, quarantinedPath: destination.path))
                }
            } catch {
                errors.append("\(item.name): \(error.localizedDescription)")
            }
        }

        if !administratorMoves.isEmpty {
            do {
                try AdministratorMover.moveBatch(administratorMoves.map(\.request))
                for move in administratorMoves {
                    if manager.fileExists(atPath: move.destination.path),
                       !manager.fileExists(atPath: move.item.path) {
                        records.append(QuarantineRecord(item: move.item, quarantinedPath: move.destination.path))
                    } else {
                        errors.append("\(move.item.name): 管理者処理後も移動を確認できませんでした。")
                    }
                }
            } catch {
                for move in administratorMoves {
                    if manager.fileExists(atPath: move.destination.path),
                       !manager.fileExists(atPath: move.item.path) {
                        records.append(QuarantineRecord(item: move.item, quarantinedPath: move.destination.path))
                    } else {
                        errors.append("\(move.item.name): \(error.localizedDescription)")
                    }
                }
            }
        }

        guard !records.isEmpty else {
            try? manager.removeItem(at: sessionDirectory)
            return QuarantineOutcome(manifestURL: nil, moved: [], errors: errors)
        }

        let manifest = QuarantineManifest(
            id: UUID(),
            createdAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            records: records
        )
        let manifestURL = sessionDirectory.appendingPathComponent("manifest.json")

        do {
            try writeManifest(manifest, to: manifestURL)
        } catch {
            errors.append("復元用台帳の保存に失敗しました: \(error.localizedDescription)")
        }

        return QuarantineOutcome(manifestURL: manifestURL, moved: records, errors: errors)
    }

    static func loadManifests() -> [(url: URL, manifest: QuarantineManifest)] {
        let manager = FileManager.default
        let directories = (try? manager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return directories.compactMap { directory in
            let url = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let manifest = try? decoder.decode(QuarantineManifest.self, from: data) else { return nil }
            return (url, manifest)
        }.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    static func restore(manifestURL: URL) -> RestoreOutcome {
        let manager = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? decoder.decode(QuarantineManifest.self, from: data) else {
            return RestoreOutcome(restoredCount: 0, skipped: [], errors: ["復元用台帳を読み取れません。"])
        }

        var count = 0
        var skipped: [String] = []
        var errors: [String] = []
        var administratorRestores: [(index: Int, record: QuarantineRecord, request: AdministratorMover.MoveRequest)] = []

        for index in manifest.records.indices where manifest.records[index].restoredAt == nil {
            let record = manifest.records[index]
            guard manager.fileExists(atPath: record.quarantinedPath) else {
                skipped.append("\(record.displayName): 隔離ファイルが見つかりません。")
                continue
            }
            guard !manager.fileExists(atPath: record.originalPath) else {
                skipped.append("\(record.displayName): 元の場所に同名ファイルがあるため上書きしません。")
                continue
            }
            guard SafetyPolicy.isAllowedToMove(path: record.originalPath) else {
                errors.append("\(record.displayName): 復元先が安全対象外です。")
                continue
            }

            let originalURL = URL(fileURLWithPath: record.originalPath)
            do {
                if record.originalPath.hasPrefix("/Library/") {
                    administratorRestores.append((
                        index: index,
                        record: record,
                        request: AdministratorMover.MoveRequest(
                            source: record.quarantinedPath,
                            destination: record.originalPath
                        )
                    ))
                } else {
                    try manager.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try manager.moveItem(at: URL(fileURLWithPath: record.quarantinedPath), to: originalURL)
                    manifest.records[index].restoredAt = Date()
                    count += 1
                }
            } catch {
                errors.append("\(record.displayName): \(error.localizedDescription)")
            }
        }

        if !administratorRestores.isEmpty {
            do {
                try AdministratorMover.moveBatch(administratorRestores.map(\.request))
                for restore in administratorRestores {
                    if manager.fileExists(atPath: restore.record.originalPath),
                       !manager.fileExists(atPath: restore.record.quarantinedPath) {
                        manifest.records[restore.index].restoredAt = Date()
                        count += 1
                    } else {
                        errors.append("\(restore.record.displayName): 管理者処理後も復元を確認できませんでした。")
                    }
                }
            } catch {
                for restore in administratorRestores {
                    if manager.fileExists(atPath: restore.record.originalPath),
                       !manager.fileExists(atPath: restore.record.quarantinedPath) {
                        manifest.records[restore.index].restoredAt = Date()
                        count += 1
                    } else {
                        errors.append("\(restore.record.displayName): \(error.localizedDescription)")
                    }
                }
            }
        }

        do {
            try writeManifest(manifest, to: manifestURL)
        } catch {
            errors.append("復元結果を台帳へ保存できません: \(error.localizedDescription)")
        }

        return RestoreOutcome(restoredCount: count, skipped: skipped, errors: errors)
    }

    static func openBaseDirectory() {
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(baseDirectory)
    }

    private static func uniqueDestination(for item: ScanItem, in sessionDirectory: URL) -> URL {
        let manager = FileManager.default
        let group = item.scope == .system ? "System Library" : "User Library"
        let relativePath: String
        if item.scope == .system {
            relativePath = item.path.replacingOccurrences(of: "/Library/", with: "")
        } else {
            let userLibrary = KnownLocations.userPath("Library") + "/"
            relativePath = item.path.replacingOccurrences(of: userLibrary, with: "")
        }

        let proposed = sessionDirectory
            .appendingPathComponent(group, isDirectory: true)
            .appendingPathComponent(relativePath)
        if !manager.fileExists(atPath: proposed.path) { return proposed }

        let base = proposed.deletingPathExtension().lastPathComponent
        let ext = proposed.pathExtension
        let parent = proposed.deletingLastPathComponent()
        for number in 2...999 {
            let name = ext.isEmpty ? "\(base)-\(number)" : "\(base)-\(number).\(ext)"
            let candidate = parent.appendingPathComponent(name)
            if !manager.fileExists(atPath: candidate.path) { return candidate }
        }
        return parent.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)"))
    }

    private static func writeManifest(_ manifest: QuarantineManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }
}

enum AdministratorMover {
    struct MoveRequest {
        let source: String
        let destination: String

        var destinationParent: String {
            URL(fileURLWithPath: destination).deletingLastPathComponent().path
        }
    }

    struct MoveError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func moveBatch(_ requests: [MoveRequest]) throws {
        guard !requests.isEmpty else { return }

        let manager = FileManager.default
        let temporaryScript = manager.temporaryDirectory
            .appendingPathComponent("PluginSafeCleaner-\(UUID().uuidString).zsh")
        try makeBatchShellScript(requests).write(to: temporaryScript, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporaryScript.path)
        defer { try? manager.removeItem(at: temporaryScript) }

        let appleScript = """
        on run argv
            set scriptPath to item 1 of argv
            do shell script "/bin/zsh " & quoted form of scriptPath with administrator privileges
        end run
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript, "--", temporaryScript.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MoveError(message: message?.isEmpty == false ? message! : "管理者権限での移動がキャンセルされたか、失敗しました。")
        }
    }

    static func makeBatchShellScript(_ requests: [MoveRequest]) -> String {
        var lines = ["#!/bin/zsh", "batch_status=0"]
        for request in requests {
            let parent = shellQuoted(request.destinationParent)
            let source = shellQuoted(request.source)
            let destination = shellQuoted(request.destination)
            lines.append("/bin/mkdir -p -- \(parent) && /bin/mv -- \(source) \(destination) || batch_status=1")
        }
        lines.append("exit $batch_status")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
