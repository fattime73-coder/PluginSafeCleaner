import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [ScanItem] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var focusedID: UUID?
    @Published var isScanning = false
    @Published var isWorking = false
    @Published var lastScanDate: Date?
    @Published var runningDAWs: [String] = []
    @Published var history: [(url: URL, manifest: QuarantineManifest)] = []
    @Published var notice: Notice?

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var focusedItem: ScanItem? {
        guard let focusedID else { return nil }
        return items.first { $0.id == focusedID }
    }

    var selectedItems: [ScanItem] {
        items.filter { selectedIDs.contains($0.id) && $0.isMovable }
    }

    func scan() {
        guard !isScanning && !isWorking else { return }
        isScanning = true
        selectedIDs.removeAll()
        focusedID = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let results = PlugInScanner.scan()
            DispatchQueue.main.async {
                self.items = results
                self.lastScanDate = Date()
                self.isScanning = false
                self.refreshRunningDAWs()
                self.refreshHistory()
            }
        }
    }

    func toggleSelection(_ item: ScanItem) {
        guard item.isMovable else { return }
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectItems(_ candidates: [ScanItem]) {
        selectedIDs.formUnion(candidates.filter(\.isMovable).map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func refreshRunningDAWs() {
        let appNames = NSWorkspace.shared.runningApplications.compactMap(\.localizedName)
        let targets = ["Logic Pro", "LUNA", "MainStage", "Pro Tools"]
        runningDAWs = targets.filter { target in
            appNames.contains { $0.caseInsensitiveCompare(target) == .orderedSame }
        }
    }

    func quarantineSelected() {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        refreshRunningDAWs()
        guard runningDAWs.isEmpty else {
            notice = Notice(title: "DAWを終了してください", message: runningDAWs.joined(separator: "、") + " が起動中です。終了してから再確認してください。")
            return
        }

        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = QuarantineManager.quarantine(items: targets)
            DispatchQueue.main.async {
                self.isWorking = false
                self.selectedIDs.removeAll()
                self.refreshHistory()

                var message = "\(outcome.moved.count)項目を隔離しました。完全削除はしていません。"
                if !outcome.errors.isEmpty {
                    message += "\n\n未完了:\n" + outcome.errors.joined(separator: "\n")
                }
                self.notice = Notice(title: outcome.moved.isEmpty ? "隔離できませんでした" : "隔離が完了しました", message: message)
                self.scan()
            }
        }
    }

    func refreshHistory() {
        history = QuarantineManager.loadManifests()
    }

    func restore(manifestURL: URL) {
        refreshRunningDAWs()
        guard runningDAWs.isEmpty else {
            notice = Notice(title: "DAWを終了してください", message: runningDAWs.joined(separator: "、") + " が起動中です。復元前に終了してください。")
            return
        }

        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = QuarantineManager.restore(manifestURL: manifestURL)
            DispatchQueue.main.async {
                self.isWorking = false
                var parts = ["\(outcome.restoredCount)項目を元の場所へ戻しました。"]
                if !outcome.skipped.isEmpty { parts.append("スキップ:\n" + outcome.skipped.joined(separator: "\n")) }
                if !outcome.errors.isEmpty { parts.append("エラー:\n" + outcome.errors.joined(separator: "\n")) }
                self.notice = Notice(title: "復元結果", message: parts.joined(separator: "\n\n"))
                self.refreshHistory()
                self.scan()
            }
        }
    }

    func reveal(_ item: ScanItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    func copyPath(_ item: ScanItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path, forType: .string)
    }
}
