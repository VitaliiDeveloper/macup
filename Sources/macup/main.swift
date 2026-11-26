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
switch Router.route(argv, env: env) {
case .bash:
    BashExec.run()
case .swift(let a):
    exit(OneOff.run(a, env: env, translations: Translations.json))
}
