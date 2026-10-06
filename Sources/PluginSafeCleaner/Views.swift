import AppKit
import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case findings = "検出結果"
    case guidance = "再スキャン案内"
    case history = "隔離履歴"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .findings: return "magnifyingglass"
        case .guidance: return "arrow.triangle.2.circlepath"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

enum QuickFormatFilter: String, CaseIterable, Identifiable {
    case all = "すべて"
    case aax = "AAX"
    case vst = "VST / VST3"
    case audioUnit = "AU"
    case universalAudio = "UA / LUNA"
    case cache = "キャッシュ"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .aax: return "slider.horizontal.3"
        case .vst: return "dial.medium"
        case .audioUnit: return "waveform"
        case .universalAudio: return "moon.stars"
        case .cache: return "arrow.triangle.2.circlepath"
        }
    }

    func matches(_ item: ScanItem) -> Bool {
        switch self {
        case .all:
            return true
        case .aax:
            return item.format == .aax
        case .vst:
            return item.format == .vst || item.format == .vst3
        case .audioUnit:
            return item.format == .audioUnit
        case .universalAudio:
            let identity = item.bundleIdentifier?.lowercased() ?? ""
            return item.format == .luna
                || item.path.localizedCaseInsensitiveContains("Universal Audio")
                || identity.contains("uaudio")
                || item.name.localizedCaseInsensitiveContains("UAD")
        case .cache:
            return item.format == .cache
        }
    }
}

struct RootView: View {
    @StateObject private var model = AppModel()
    @State private var section: MainSection = .findings
    @State private var searchText = ""
    @State private var formatFilter: QuickFormatFilter = .all
    @State private var showingPreflight = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)
            Divider()

            HStack(spacing: 0) {
                SidebarView(section: $section, model: model)
                    .frame(width: 205)
                Divider()

                Group {
                    switch section {
                    case .findings:
                        FindingsView(
                            model: model,
                            searchText: $searchText,
                            formatFilter: $formatFilter,
                            showingPreflight: $showingPreflight
                        )
                    case .guidance:
                        GuidanceView()
                    case .history:
                        HistoryView(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1040, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.refreshHistory()
            model.scan()
        }
        .sheet(isPresented: $showingPreflight) {
            PreflightView(model: model, isPresented: $showingPreflight)
        }
        .alert(item: $model.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
    }
}

private struct HeaderView: View {
    @ObservedObject var model: AppModel

    private var bundledAppIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(nsImage: bundledAppIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Plug-in Safe Cleaner")
                    .font(.title2.weight(.semibold))
                Text("不要なプラグインを完全削除せず、安全な隔離フォルダへ移動します")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isScanning || model.isWorking {
                ProgressView()
                    .controlSize(.small)
                Text(model.isScanning ? "確認中…" : "処理中…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.scan()
            } label: {
                Label("もう一度確認", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isScanning || model.isWorking)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }
}

private struct SidebarView: View {
    @Binding var section: MainSection
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("安全な手順")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 18)

            ForEach(MainSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack {
                        Image(systemName: item.icon)
                            .frame(width: 22)
                        Text(item.rawValue)
                        Spacer()
                        if item == .findings && !model.items.isEmpty {
                            Text("\(model.items.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(section == item ? Color.accentColor.opacity(0.14) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 8)
            }

            Divider().padding(.vertical, 10)

            SafetyNote(icon: "trash.slash", text: "完全削除しません")
            SafetyNote(icon: "doc.badge.clock", text: "復元用台帳を保存")
            SafetyNote(icon: "lock", text: "複数選択でも認証1回")

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("隔離先")
                    .font(.caption.weight(.semibold))
                Text("書類 › PlugIn Safe Cleaner › Quarantine")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Finderで開く") {
                    QuarantineManager.openBaseDirectory()
                }
                .font(.caption)
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }
}

private struct SafetyNote: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
    }
}

private struct FindingsView: View {
    @ObservedObject var model: AppModel
    @Binding var searchText: String
    @Binding var formatFilter: QuickFormatFilter
    @Binding var showingPreflight: Bool
    @State private var brokenOnly = false

    private var filteredItems: [ScanItem] {
        model.items.filter { item in
            let matchesFormat = formatFilter.matches(item)
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
                || item.path.localizedCaseInsensitiveContains(query)
            let matchesStatus = !brokenOnly || item.status == .broken
            return matchesFormat && matchesSearch && matchesStatus
        }
    }

    private var brokenCandidatesInCurrentSearch: [ScanItem] {
        model.items.filter { item in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
                || item.path.localizedCaseInsensitiveContains(query)
            return formatFilter.matches(item) && matchesSearch && item.status == .broken
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StepStrip()
            Divider()

            SearchAndFormatBar(
                model: model,
                searchText: $searchText,
                formatFilter: $formatFilter,
                brokenOnly: $brokenOnly
            )

            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    SummaryBar(model: model, visibleCount: filteredItems.count)
                    Divider()

                    if model.isScanning && model.items.isEmpty {
                        VStack(spacing: 14) {
                            ProgressView()
                            Text("一般的なプラグイン配置とキャッシュを確認しています…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredItems.isEmpty {
                        EmptyStateView(
                            title: "該当項目はありません",
                            icon: "checkmark.shield",
                            message: "フィルターを変更するか、もう一度確認してください。"
                        )
                    } else {
                        List(filteredItems) { item in
                            FindingRow(
                                item: item,
                                isSelected: model.selectedIDs.contains(item.id),
                                isFocused: model.focusedID == item.id,
                                toggle: { model.toggleSelection(item) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { model.focusedID = item.id }
                            .listRowBackground(model.focusedID == item.id ? Color.accentColor.opacity(0.10) : Color.clear)
                        }
                        .listStyle(.inset)
                    }

                    Divider()
                    HStack {
                        Button {
                            brokenOnly = true
                            model.selectItems(brokenCandidatesInCurrentSearch)
                        } label: {
                            Label("壊れている可能性を一括選択", systemImage: "exclamationmark.triangle.fill")
                        }
                        .tint(.orange)
                        .disabled(brokenCandidatesInCurrentSearch.isEmpty)
                        Button("選択解除") {
                            model.clearSelection()
                        }
                        .disabled(model.selectedIDs.isEmpty)

                        Spacer()
                        Text("\(model.selectedItems.count)項目を選択中")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button {
                            model.refreshRunningDAWs()
                            showingPreflight = true
                        } label: {
                            Label("隔離へ進む", systemImage: "archivebox")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selectedItems.isEmpty || model.isWorking)
                    }
                    .padding(14)
                }
                .frame(minWidth: 610)

                DetailView(model: model)
                    .frame(minWidth: 290, idealWidth: 330)
            }
        }
    }
}

private struct SearchAndFormatBar: View {
    @ObservedObject var model: AppModel
    @Binding var searchText: String
    @Binding var formatFilter: QuickFormatFilter
    @Binding var brokenOnly: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                TextField("プラグイン名または保存場所を検索", text: $searchText)
                    .textFieldStyle(.plain)

                Button {
                    brokenOnly.toggle()
                } label: {
                    Label(
                        "壊れている可能性 \(model.items.filter { $0.status == .broken }.count)",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(brokenOnly ? Color.white : Color.orange)
                    .background(brokenOnly ? Color.orange : Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help(brokenOnly ? "すべての状態を表示" : "壊れている可能性だけ表示")
            }

            HStack(spacing: 8) {
                Text("形式")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(QuickFormatFilter.allCases) { filter in
                    FormatFilterButton(
                        filter: filter,
                        count: model.items.filter(filter.matches).count,
                        isSelected: formatFilter == filter,
                        action: { formatFilter = filter }
                    )
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.24))
    }
}

private struct FormatFilterButton: View {
    let filter: QuickFormatFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                Text(filter.rawValue)
                    .fontWeight(.semibold)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color(nsColor: .quaternaryLabelColor).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.rawValue) \(count)件")
    }
}

private struct StepStrip: View {
    private let steps = [
        ("1", "検出"), ("2", "内容を確認"), ("3", "隔離"), ("4", "DAWで再スキャン")
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 6) {
                    Text(step.0)
                        .font(.caption.bold())
                        .frame(width: 22, height: 22)
                        .background(index == 0 ? Color.accentColor : Color.secondary.opacity(0.22))
                        .foregroundStyle(index == 0 ? .white : .secondary)
                        .clipShape(Circle())
                    Text(step.1)
                        .font(.caption.weight(.medium))
                }
                if index < steps.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }
}

private struct SummaryBar: View {
    @ObservedObject var model: AppModel
    let visibleCount: Int

    var body: some View {
        HStack(spacing: 16) {
            Label("表示 \(visibleCount)", systemImage: "square.stack.3d.up")
            Label("要確認 \(model.items.filter { $0.status == .broken || $0.status == .disabledResidue }.count)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Label("キャッシュ \(model.items.filter { $0.format == .cache }.count)", systemImage: "arrow.triangle.2.circlepath")
            Spacer()
            if let date = model.lastScanDate {
                Text("最終確認 \(date.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct FindingRow: View {
    let item: ScanItem
    let isSelected: Bool
    let isFocused: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button(action: toggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(item.isMovable ? (isSelected ? Color.accentColor : Color.secondary) : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!item.isMovable)
            .help(item.isMovable ? "隔離対象として選択" : "この項目は移動できません")

            Image(systemName: item.format.icon)
                .font(.system(size: 19))
                .foregroundStyle(formatColor)
                .frame(width: 25)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .lineLimit(1)
                    .font(.body.weight(.medium))
                Text(item.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.format.shortName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(formatColor.opacity(0.14))
                    .clipShape(Capsule())
                Label(item.status.rawValue, systemImage: item.status.symbol)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }

            if item.scope.needsAdministrator {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("システム項目は一括処理につき1回、macOSの管理者認証が必要です")
            }
        }
        .padding(.vertical, 6)
    }

    private var formatColor: Color {
        switch item.format {
        case .audioUnit: return .blue
        case .vst: return .purple
        case .vst3: return .indigo
        case .aax: return .pink
        case .luna: return .teal
        case .cache: return .orange
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .broken: return .red
        case .disabledResidue, .duplicate, .cache: return .orange
        case .healthy: return .secondary
        case .protected: return .secondary
        }
    }
}

private struct DetailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if let item = model.focusedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top) {
                            Image(systemName: item.format.icon)
                                .font(.system(size: 30))
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.title3.weight(.semibold))
                                Text(item.format.rawValue)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        DetailSection(title: "判定") {
                            Label(item.status.rawValue, systemImage: item.status.symbol)
                                .font(.body.weight(.medium))
                            Text(item.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        DetailSection(title: "配置") {
                            LabeledContent("範囲", value: item.scope.rawValue)
                            if item.scope.needsAdministrator {
                                Label("一括処理につき1回、管理者パスワードが必要です", systemImage: "lock")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }

                        DetailSection(title: "ファイル") {
                            Text(item.path)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            if let size = item.byteSize {
                                LabeledContent("概算サイズ", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            }
                            if let date = item.modifiedAt {
                                LabeledContent("更新", value: date.formatted(date: .abbreviated, time: .shortened))
                            }
                        }

                        HStack {
                            Button("Finderで表示") { model.reveal(item) }
                            Button("パスをコピー") { model.copyPath(item) }
                        }
                    }
                    .padding(18)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("項目を選ぶと詳細を表示します")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PreflightView: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool
    @State private var confirmedDAWsClosed = false
    @State private var confirmedNoDeletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("隔離前の確認")
                        .font(.title2.weight(.semibold))
                    Text("選択した\(model.selectedItems.count)項目を安全なフォルダへ移動します")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if model.runningDAWs.isEmpty {
                        Label("Logic Pro / LUNAなどの対象DAWは起動していません", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label(model.runningDAWs.joined(separator: "、") + " が起動中です", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    Button("起動状態を再確認") { model.refreshRunningDAWs() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Toggle("対象のDAWを終了したことを確認しました", isOn: $confirmedDAWsClosed)
            Toggle("完全削除ではなく、復元可能な隔離であることを確認しました", isOn: $confirmedNoDeletion)

            Text("システムLibrary内の項目が含まれる場合、macOSの管理者認証画面が1回表示されます。複数選択した項目は、その1回の認証でまとめて隔離します。認証をキャンセルした項目は移動されません。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("キャンセル", role: .cancel) { isPresented = false }
                Spacer()
                Button("隔離を実行") {
                    isPresented = false
                    model.quarantineSelected()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!confirmedDAWsClosed || !confirmedNoDeletion || !model.runningDAWs.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}

private struct GuidanceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("隔離後の再スキャン")
                    .font(.largeTitle.weight(.bold))
                Text("まずDAW自身のプラグイン管理機能を使います。キャッシュ隔離は、それでも表示が残る場合の最終手段です。")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                GuidanceCard(
                    number: "1",
                    title: "Logic Pro",
                    icon: "waveform",
                    color: .blue,
                    steps: [
                        "Logic Proを終了した状態でプラグインを隔離します。",
                        "Logic Proを開き、Logic Pro ＞ 設定 ＞ プラグインマネージャを開きます。",
                        "「Audio Unitsを完全にリセット」を実行し、Logic Proを終了して再度開きます。",
                        "まだ残る場合だけAudioUnitCacheの項目を隔離し、Macを再起動します。"
                    ],
                    linkTitle: "Apple公式手順を開く",
                    linkURL: URL(string: "https://support.apple.com/ja-jp/122179")!
                )

                GuidanceCard(
                    number: "2",
                    title: "UAD LUNA",
                    icon: "moon.stars.fill",
                    color: .teal,
                    steps: [
                        "LUNAを開き、左上のサイドバーからManage Plug-Ins（または設定 ＞ Plug-Ins）を開きます。",
                        "Rescan AllでAU/VST3を再確認します。新規・更新分だけならNew Plug-Insを使います。",
                        "表示だけ消したい場合は、削除より先にIgnoreを使えます。",
                        "LUNAワークスペースキャッシュの隔離は、通常の再スキャンで直らない場合だけ行います。"
                    ],
                    linkTitle: "Universal Audio公式手順を開く",
                    linkURL: URL(string: "https://help.uaudio.com/hc/en-us/articles/34498519722132-Using-Insert-Plug-Ins")!
                )

                GroupBox {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(.orange)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("削除対象にしないもの")
                                .font(.headline)
                            Text("LUNA Sessions、プリセット、ライセンス、iLok/UA Connect関連データ、/System/Library内のApple標準コンポーネントは、このアプリの隔離対象に含めません。")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                }
            }
            .padding(28)
            .frame(maxWidth: 850, alignment: .leading)
        }
    }
}

private struct GuidanceCard: View {
    let number: String
    let title: String
    let icon: String
    let color: Color
    let steps: [String]
    let linkTitle: String
    let linkURL: URL

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        Circle().fill(color.opacity(0.15)).frame(width: 42, height: 42)
                        Image(systemName: icon).foregroundStyle(color)
                    }
                    Text(title).font(.title2.weight(.semibold))
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .frame(width: 22, height: 22)
                            .background(color.opacity(0.14))
                            .clipShape(Circle())
                        Text(step)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Link(destination: linkURL) {
                    Label(linkTitle, systemImage: "arrow.up.right.square")
                }
            }
            .padding(8)
        }
    }
}

private struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var pendingRestore: URL?
    @State private var showingRestoreConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("隔離履歴")
                        .font(.largeTitle.weight(.bold))
                    Text("元の場所が空いている項目だけ復元できます。同名ファイルは上書きしません。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Finderで隔離先を開く") { QuarantineManager.openBaseDirectory() }
            }
            .padding(24)

            Divider()

            historyContent
        }
        .confirmationDialog(
            "未復元の項目を元の場所へ戻しますか？",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("復元する") {
                if let pendingRestore { model.restore(manifestURL: pendingRestore) }
                pendingRestore = nil
            }
            Button("キャンセル", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Logic ProとLUNAを終了してから実行してください。同名ファイルは上書きしません。")
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if model.history.isEmpty {
            EmptyStateView(
                title: "隔離履歴はありません",
                icon: "archivebox",
                message: "隔離を実行すると、復元用の記録がここに表示されます。"
            )
        } else {
            List {
                ForEach(model.history.indices, id: \.self) { index in
                    HistoryEntryRow(
                        manifestURL: model.history[index].url,
                        manifest: model.history[index].manifest,
                        isWorking: model.isWorking,
                        requestRestore: {
                            pendingRestore = model.history[index].url
                            showingRestoreConfirmation = true
                        }
                    )
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct HistoryEntryRow: View {
    let manifestURL: URL
    let manifest: QuarantineManifest
    let isWorking: Bool
    let requestRestore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "archivebox.fill")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text(manifest.createdAt.formatted(date: .long, time: .shortened))
                        .font(.headline)
                    Text("隔離 \(manifest.records.count)項目・未復元 \(manifest.activeRecords.count)項目")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("フォルダを開く") {
                    NSWorkspace.shared.open(manifestURL.deletingLastPathComponent())
                }
                Button("未復元分を戻す", action: requestRestore)
                    .disabled(manifest.activeRecords.isEmpty || isWorking)
            }

            ForEach(Array(manifest.records.prefix(5))) { record in
                HStack {
                    Image(systemName: record.restoredAt == nil ? "circle.fill" : "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(record.restoredAt == nil ? Color.orange : Color.green)
                    Text(record.displayName)
                        .lineLimit(1)
                    Spacer()
                    Text(record.format.shortName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            if manifest.records.count > 5 {
                Text("ほか\(manifest.records.count - 5)項目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct EmptyStateView: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
