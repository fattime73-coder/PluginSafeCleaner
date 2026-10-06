import Foundation

enum PlugInFormat: String, CaseIterable, Codable, Identifiable {
    case audioUnit = "Audio Unit"
    case vst = "VST"
    case vst3 = "VST3"
    case aax = "AAX"
    case luna = "LUNA"
    case cache = "キャッシュ / スキャン情報"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .audioUnit: return "AU"
        case .cache: return "CACHE"
        default: return rawValue.uppercased()
        }
    }

    var icon: String {
        switch self {
        case .audioUnit: return "waveform"
        case .vst, .vst3: return "dial.medium"
        case .aax: return "slider.horizontal.3"
        case .luna: return "moon.stars"
        case .cache: return "arrow.triangle.2.circlepath"
        }
    }
}

enum InstallScope: String, Codable, CaseIterable, Identifiable {
    case user = "ユーザー"
    case system = "システム"
    case protectedSystem = "保護領域"

    var id: String { rawValue }
    var needsAdministrator: Bool { self == .system }
}

enum FindingStatus: String, Codable, CaseIterable {
    case healthy = "通常のプラグイン"
    case broken = "壊れている可能性"
    case disabledResidue = "無効化・バックアップ候補"
    case duplicate = "重複候補"
    case cache = "再スキャン用データ"
    case protected = "移動不可"

    var symbol: String {
        switch self {
        case .healthy: return "checkmark.circle"
        case .broken: return "exclamationmark.triangle.fill"
        case .disabledResidue: return "archivebox"
        case .duplicate: return "square.on.square"
        case .cache: return "arrow.triangle.2.circlepath"
        case .protected: return "lock.fill"
        }
    }

    var priority: Int {
        switch self {
        case .broken: return 0
        case .disabledResidue: return 1
        case .duplicate: return 2
        case .cache: return 3
        case .healthy: return 4
        case .protected: return 5
        }
    }
}

struct ScanItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let format: PlugInFormat
    let scope: InstallScope
    var status: FindingStatus
    var detail: String
    let bundleIdentifier: String?
    let modifiedAt: Date?
    let byteSize: Int64?

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        format: PlugInFormat,
        scope: InstallScope,
        status: FindingStatus,
        detail: String,
        bundleIdentifier: String? = nil,
        modifiedAt: Date? = nil,
        byteSize: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.format = format
        self.scope = scope
        self.status = status
        self.detail = detail
        self.bundleIdentifier = bundleIdentifier
        self.modifiedAt = modifiedAt
        self.byteSize = byteSize
    }

    var isMovable: Bool {
        scope != .protectedSystem && status != .protected && SafetyPolicy.isAllowedToMove(path: path)
    }

    var isSuggestedCandidate: Bool {
        status == .broken || status == .disabledResidue
    }
}

struct ScanRoot {
    let path: String
    let format: PlugInFormat
    let scope: InstallScope
    let extensions: Set<String>
    let maximumDepth: Int
}

struct CacheTarget {
    enum Mode {
        case children
        case exact
    }

    let path: String
    let scope: InstallScope
    let label: String
    let detail: String
    let mode: Mode
}

enum KnownLocations {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static func userPath(_ suffix: String) -> String {
        URL(fileURLWithPath: home).appendingPathComponent(suffix).path
    }

    static let plugInRoots: [ScanRoot] = [
        ScanRoot(path: userPath("Library/Audio/Plug-Ins/Components"), format: .audioUnit, scope: .user, extensions: ["component"], maximumDepth: 2),
        ScanRoot(path: "/Library/Audio/Plug-Ins/Components", format: .audioUnit, scope: .system, extensions: ["component"], maximumDepth: 2),
        ScanRoot(path: userPath("Library/Audio/Plug-Ins/VST"), format: .vst, scope: .user, extensions: ["vst"], maximumDepth: 2),
        ScanRoot(path: "/Library/Audio/Plug-Ins/VST", format: .vst, scope: .system, extensions: ["vst"], maximumDepth: 2),
        ScanRoot(path: userPath("Library/Audio/Plug-Ins/VST3"), format: .vst3, scope: .user, extensions: ["vst3"], maximumDepth: 3),
        ScanRoot(path: "/Library/Audio/Plug-Ins/VST3", format: .vst3, scope: .system, extensions: ["vst3"], maximumDepth: 3),
        ScanRoot(path: userPath("Library/Application Support/Avid/Audio/Plug-Ins"), format: .aax, scope: .user, extensions: ["aaxplugin"], maximumDepth: 3),
        ScanRoot(path: "/Library/Application Support/Avid/Audio/Plug-Ins", format: .aax, scope: .system, extensions: ["aaxplugin"], maximumDepth: 3),
        ScanRoot(path: "/Library/Application Support/Universal Audio/Plug-ins", format: .luna, scope: .system, extensions: ["lunacomponent"], maximumDepth: 2)
    ]

    static let cacheTargets: [CacheTarget] = [
        CacheTarget(
            path: userPath("Library/Caches/AudioUnitCache"),
            scope: .user,
            label: "Audio Unitキャッシュ",
            detail: "Logic Proなどが使うAU検証キャッシュです。問題があるときだけ隔離し、Macを再起動してください。",
            mode: .children
        ),
        CacheTarget(
            path: userPath("Library/Application Support/Universal Audio/workspace"),
            scope: .user,
            label: "LUNAワークスペースキャッシュ",
            detail: "LUNAのワークスペース情報です。まずLUNAのManage Plug-InsでRescan Allを試してください。",
            mode: .exact
        ),
        CacheTarget(
            path: "/Library/Application Support/Universal Audio/skippedplugins.txt",
            scope: .system,
            label: "LUNAスキップ情報",
            detail: "Universal Audioが管理するスキップ情報です。内容確認用で、通常はLUNA内の再スキャンを優先します。",
            mode: .exact
        ),
        CacheTarget(
            path: "/Library/Application Support/Universal Audio/Plug-Ins.json",
            scope: .system,
            label: "LUNAプラグイン一覧情報",
            detail: "Universal Audioのプラグイン一覧情報です。UAD/LUNA固有プラグインの本体ではありません。",
            mode: .exact
        )
    ]

    static let allowedRoots: [String] = {
        let plugIns = plugInRoots.map(\.path)
        let caches = cacheTargets.map(\.path)
        return plugIns + caches
    }()
}

enum SafetyPolicy {
    static func isAllowedToMove(path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !standardized.hasPrefix("/System/") else { return false }
        guard !standardized.contains("/Music/LUNA Sessions") else { return false }

        return KnownLocations.allowedRoots.contains { root in
            let cleanRoot = URL(fileURLWithPath: root).standardizedFileURL.path
            return standardized == cleanRoot || standardized.hasPrefix(cleanRoot + "/")
        }
    }
}

struct QuarantineRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let originalPath: String
    let quarantinedPath: String
    let displayName: String
    let format: PlugInFormat
    let movedAt: Date
    var restoredAt: Date?

    init(item: ScanItem, quarantinedPath: String) {
        id = UUID()
        originalPath = item.path
        self.quarantinedPath = quarantinedPath
        displayName = item.name
        format = item.format
        movedAt = Date()
        restoredAt = nil
    }
}

struct QuarantineManifest: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let appVersion: String
    var records: [QuarantineRecord]

    var activeRecords: [QuarantineRecord] { records.filter { $0.restoredAt == nil } }
}

struct QuarantineOutcome {
    let manifestURL: URL?
    let moved: [QuarantineRecord]
    let errors: [String]
}

struct RestoreOutcome {
    let restoredCount: Int
    let skipped: [String]
    let errors: [String]
}
