import Foundation

let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("PluginSafeCleaner-BatchTest-\(UUID().uuidString)")
let sourceDirectory = root.appendingPathComponent("source")
let destinationDirectory = root.appendingPathComponent("destination")
let sourceOne = sourceDirectory.appendingPathComponent("Plug In One.aaxplugin")
let sourceTwo = sourceDirectory.appendingPathComponent("Maker's Plug In.vst3")
let destinationOne = destinationDirectory.appendingPathComponent("AAX/Plug In One.aaxplugin")
let destinationTwo = destinationDirectory.appendingPathComponent("VST3/Maker's Plug In.vst3")
let scriptURL = root.appendingPathComponent("batch.zsh")

defer { try? manager.removeItem(at: root) }
try manager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
try Data("one".utf8).write(to: sourceOne)
try Data("two".utf8).write(to: sourceTwo)

let requests = [
    AdministratorMover.MoveRequest(source: sourceOne.path, destination: destinationOne.path),
    AdministratorMover.MoveRequest(source: sourceTwo.path, destination: destinationTwo.path)
]
let script = AdministratorMover.makeBatchShellScript(requests)
try script.write(to: scriptURL, atomically: true, encoding: .utf8)

let syntaxCheck = Process()
syntaxCheck.executableURL = URL(fileURLWithPath: "/bin/zsh")
syntaxCheck.arguments = ["-n", scriptURL.path]
try syntaxCheck.run()
syntaxCheck.waitUntilExit()
precondition(syntaxCheck.terminationStatus == 0, "Generated batch script has invalid syntax")

let execution = Process()
execution.executableURL = URL(fileURLWithPath: "/bin/zsh")
execution.arguments = [scriptURL.path]
try execution.run()
execution.waitUntilExit()
precondition(execution.terminationStatus == 0, "Generated batch script failed")
precondition(!manager.fileExists(atPath: sourceOne.path))
precondition(!manager.fileExists(atPath: sourceTwo.path))
precondition(manager.fileExists(atPath: destinationOne.path))
precondition(manager.fileExists(atPath: destinationTwo.path))
print("batch-move-smoke=PASS")
