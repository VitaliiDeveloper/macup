import Darwin
import Foundation
import MacupCore

// The macup binary: it runs what is ported itself and hands every other invocation, whole, to the bash build it carries.
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
switch Router.route(argv, env: env) {
case .bash:
    BashExec.run()
case .rejected(let failure):
    exit(OneOff.rejected(failure, env: env, translations: Translations.json))
case .swift(let arguments) where arguments.command == nil && arguments.action == nil && !arguments.deep:
    switch Menu.run(arguments, env: env, translations: Translations.json) {
    case .done(let status):
        exit(status)
    case .run(let word):
        // first, not last: a trailing --only with no value would take it
        if case .swift(let picked) = Router.route([word] + argv, env: env) { MainPass.run(picked, env: env, translations: Translations.json) }
        BashExec.run(prepending: [word])
    }
case .swift(let arguments) where arguments.command == nil:
    MainPass.run(arguments, env: env, translations: Translations.json)
case .swift(let arguments):
    exit(OneOff.run(arguments, env: env, translations: Translations.json))
}
