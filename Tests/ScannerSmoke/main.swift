import Foundation

let items = PlugInScanner.scan()
let byFormat = Dictionary(grouping: items, by: \.format).mapValues(\.count)
let byStatus = Dictionary(grouping: items, by: \.status).mapValues(\.count)

precondition(!SafetyPolicy.isAllowedToMove(path: "/System/Library/Components/CoreAudio.component"))
precondition(!SafetyPolicy.isAllowedToMove(path: KnownLocations.userPath("Music/LUNA Sessions/Important Session")))
precondition(!SafetyPolicy.isAllowedToMove(path: KnownLocations.userPath("Documents/random.txt")))
precondition(SafetyPolicy.isAllowedToMove(path: KnownLocations.userPath("Library/Audio/Plug-Ins/Components/Test.component")))
precondition(SafetyPolicy.isAllowedToMove(path: "/Library/Audio/Plug-Ins/VST3/Test.vst3"))

print("items=\(items.count)")
for format in PlugInFormat.allCases {
    print("format.\(format.rawValue)=\(byFormat[format, default: 0])")
}
for status in FindingStatus.allCases {
    print("status.\(status.rawValue)=\(byStatus[status, default: 0])")
}
print("safety-policy=PASS")
