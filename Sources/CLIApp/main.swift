import Foundation

let router = CLICommandRouter.live()
let consoleIO = ConsoleIO()
let exitCode = router.execute(arguments: Array(CommandLine.arguments.dropFirst()), io: consoleIO)
exit(Int32(exitCode))
