import SwiftUI

@main
struct PluginSafeCleanerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .help) {
                Link("Logic Proの公式再スキャン手順", destination: URL(string: "https://support.apple.com/ja-jp/122179")!)
                Link("LUNAの公式プラグイン管理手順", destination: URL(string: "https://help.uaudio.com/hc/en-us/articles/34498519722132-Using-Insert-Plug-Ins")!)
            }
        }
    }
}
