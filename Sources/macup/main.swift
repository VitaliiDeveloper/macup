import Darwin
import Foundation
import MacupCore

// The macup binary.
let argv = Array(CommandLine.arguments.dropFirst())
let env: Env
do {
    env = try Env(ProcessInfo.processInfo.environment)
} catch {
    FileHandle.standardError.write(Data((Env.Failure.noHome.message + "\n").utf8))
    exit(1)
}
Names.setLocale(env)
Schedule.repair(env, translations: Translations.json)

/// The command line as arguments.sh reads it; one it rejects ends macup with its message.
func parsed(_ argv: [String]) -> Arguments {
    do { return try Arguments.parse(argv) } catch let failure as Arguments.Failure {
        exit(OneOff.rejected(failure, env: env, translations: Translations.json))
    } catch { preconditionFailure("Arguments.parse throws only Arguments.Failure") }
}

let arguments = parsed(argv)
if arguments.command != nil { exit(OneOff.run(arguments, env: env, translations: Translations.json)) }
// no command word and no run: the menu on a terminal, the help anywhere else
if arguments.action == nil, !arguments.deep {
    switch Menu.run(arguments, env: env, translations: Translations.json) {
    case .done(let status): exit(status)
    // first, not last: a trailing --only with no value would take it
    case .run(let word): MainPass.run(parsed([word] + argv), env: env, translations: Translations.json)
    }
}
MainPass.run(arguments, env: env, translations: Translations.json)
