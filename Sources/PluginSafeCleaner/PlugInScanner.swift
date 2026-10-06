import Foundation

enum PlugInScanner {
    private static let residueSuffixes: Set<String> = ["disabled", "old", "bak", "backup", "previous"]

    static func scan() -> [ScanItem] {
        var items: [ScanItem] = []

        for root in KnownLocations.plugInRoots {
            items.append(contentsOf: scanPlugIns(in: root))
        }

        for target in KnownLocations.cacheTargets {
            items.append(contentsOf: scanCache(target))
        }

        markDuplicates(in: &items)
        return items.sorted {
            if $0.status.priority != $1.status.priority {
                return $0.status.priority < $1.status.priority
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func scanPlugIns(in root: ScanRoot) -> [ScanItem] {
        let manager = FileManager.default
        let rootURL = URL(fileURLWithPath: root.path, isDirectory: true)
        guard manager.fileExists(atPath: rootURL.path) else { return [] }

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]
        guard let enumerator = manager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var results: [ScanItem] = []
        while let url = enumerator.nextObject() as? URL {
            let depth = url.pathComponents.count - rootURL.pathComponents.count
            if depth > root.maximumDepth {
                enumerator.skipDescendants()
                continue
            }

            let lowerExtension = url.pathExtension.lowercased()
            let baseExtension = url.deletingPathExtension().pathExtension.lowercased()
            let isExpectedBundle = root.extensions.contains(lowerExtension)
            let isResidue = residueSuffixes.contains(lowerExtension) && root.extensions.contains(baseExtension)

            guard isExpectedBundle || isResidue else { continue }
            enumerator.skipDescendants()
            results.append(inspectPlugIn(url: url, root: root, isResidue: isResidue))
        }
        return results
    }

    private static func inspectPlugIn(url: URL, root: ScanRoot, isResidue: Bool) -> ScanItem {
        let manager = FileManager.default
        let values = try? url.resourceValues(forKeys: [
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ])

        if values?.isSymbolicLink == true {
            let destination = url.resolvingSymlinksInPath().path
            if !manager.fileExists(atPath: destination) {
                return ScanItem(
                    name: url.lastPathComponent,
                    path: url.path,
                    format: root.format,
                    scope: root.scope,
                    status: .broken,
                    detail: "リンク先が見つからない壊れたシンボリックリンクです。",
                    modifiedAt: values?.contentModificationDate,
                    byteSize: byteSize(values)
                )
            }
        }

        if isResidue {
            return ScanItem(
                name: url.lastPathComponent,
                path: url.path,
                format: root.format,
                scope: root.scope,
                status: .disabledResidue,
                detail: "拡張子から、無効化済みまたはバックアップとして残された候補と判断しました。",
                modifiedAt: values?.contentModificationDate,
                byteSize: byteSize(values)
            )
        }

        guard let bundle = Bundle(url: url) else {
            return ScanItem(
                name: url.lastPathComponent,
                path: url.path,
                format: root.format,
                scope: root.scope,
                status: .broken,
                detail: "プラグインのInfo.plistを読み取れません。",
                modifiedAt: values?.contentModificationDate,
                byteSize: byteSize(values)
            )
        }

        let executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        let executableExists: Bool = {
            guard let executableName, !executableName.isEmpty else { return false }
            let executableURL = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
            return manager.fileExists(atPath: executableURL.path)
        }()

        if !executableExists {
            return ScanItem(
                name: displayName(for: bundle, fallback: url.lastPathComponent),
                path: url.path,
                format: root.format,
                scope: root.scope,
                status: .broken,
                detail: "プラグイン本体の実行ファイルが見つかりません。アンインストール残りの可能性があります。",
                bundleIdentifier: bundle.bundleIdentifier,
                modifiedAt: values?.contentModificationDate,
                byteSize: byteSize(values)
            )
        }

        return ScanItem(
            name: displayName(for: bundle, fallback: url.lastPathComponent),
            path: url.path,
            format: root.format,
            scope: root.scope,
            status: .healthy,
            detail: "構造上の破損は見つかりません。不要と確認できた場合だけ隔離してください。",
            bundleIdentifier: bundle.bundleIdentifier,
            modifiedAt: values?.contentModificationDate,
            byteSize: byteSize(values)
        )
    }

    private static func scanCache(_ target: CacheTarget) -> [ScanItem] {
        let manager = FileManager.default
        let targetURL = URL(fileURLWithPath: target.path)
        guard manager.fileExists(atPath: targetURL.path) else { return [] }

        switch target.mode {
        case .exact:
            return [cacheItem(url: targetURL, target: target)]
        case .children:
            let children = (try? manager.contentsOfDirectory(
                at: targetURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            return children.map { cacheItem(url: $0, target: target) }
        }
    }

    private static func cacheItem(url: URL, target: CacheTarget) -> ScanItem {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey])
        let label = target.mode == .exact ? target.label : url.lastPathComponent
        return ScanItem(
            name: label,
            path: url.path,
            format: .cache,
            scope: target.scope,
            status: .cache,
            detail: target.detail,
            modifiedAt: values?.contentModificationDate,
            byteSize: byteSize(values)
        )
    }

    private static func markDuplicates(in items: inout [ScanItem]) {
        var groups: [String: [Int]] = [:]

        for (index, item) in items.enumerated() where item.format != .cache {
            let identity = item.bundleIdentifier?.lowercased()
                ?? item.name.lowercased().replacingOccurrences(of: ".\(item.format.rawValue.lowercased())", with: "")
            let key = "\(item.format.rawValue)|\(identity)"
            groups[key, default: []].append(index)
        }

        for indices in groups.values where indices.count > 1 {
            let paths = indices.map { items[$0].scope.rawValue }.joined(separator: " / ")
            for index in indices where items[index].status == .healthy {
                items[index].status = .duplicate
                items[index].detail = "同じ識別子または名前の\(items[index].format.rawValue)が複数あります（\(paths)）。バージョンを確認してください。"
            }
        }
    }

    private static func displayName(for bundle: Bundle, fallback: String) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? fallback
    }

    private static func byteSize(_ values: URLResourceValues?) -> Int64? {
        if let size = values?.totalFileAllocatedSize { return Int64(size) }
        if let size = values?.fileSize { return Int64(size) }
        return nil
    }
}
