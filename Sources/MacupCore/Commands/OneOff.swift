import Darwin
import Foundation

/// The one-off commands the Swift build runs itself (arguments.sh, after the options are read).
public enum OneOff {
    /// What every one-off command reads: the environment, the config, the language and colours the run settled on.
    struct Context {
        let arguments: Arguments
        let env: Env
        let shell: Shell
        let config: Config
        /// The run's language (--lang, else MACUP_LANG, the config, the system); a default config is written in it.
        let lang: Lang
        let i18n: I18n
        let colors: Colors
        let out: Output
        /// src/i18n/translations.json, for `lang`, which prints in the language it sets.
        let translations: String

        init(_ arguments: Arguments, env: Env, translations: String) {
            self.arguments = arguments
            self.env = env
            self.translations = translations
            shell = Shell(env: env)
            config = Config(env: env)
            // core.sh reads the language when it loads, before --lang is looked at: a config sed cannot read says so here
            let initial = Lang.initial(env: env, config: config, shell: shell)
            lang = arguments.lang ?? initial
            i18n = I18n(lang: lang, translationsJSON: translations)
            colors = arguments.noColor ? .off : Colors.initial(env: env)
            out = Output(i18n: I18n(lang: .en, translations: [:]), colors: colors)
        }
    }

    /// Under sudo the config, the reports and the history would become root's, and the next plain run could not write them.
    static func refusesSudo(_ context: Context) -> Bool {
        guard context.env.underSudo, !context.arguments.runsUnderSudo else { return false }
        context.out.write(context.i18n.translate("macup does not need sudo: run it as yourself.") + "\n")
        return true
    }

    /// Runs a routed command; returns the exit status. `translations` is src/i18n/translations.json.
    public static func run(_ arguments: Arguments, env: Env, translations: String) -> Int32 {
        env.apply()
        let context = Context(arguments, env: env, translations: translations)
        let out = context.out
        if refusesSudo(context) { return 1 }
        switch arguments.command {
        case .version?:
            out.write("macup \(Env.version)\n")
        case .help?:
            out.write(Help.text(lang: context.lang, colors: context.colors, conf: env.paths.tildify(env.conf)))
        case .tasks?:
            out.write(TasksCommand.text(context, json: arguments.json))
        case .history?:
            out.write(arguments.json ? History.json(context) : History.text(context))
        case .last?:
            FileHandle.standardOutput.write(Reports.last(context))
        case .reports?:
            return Reports.run(context)
        case .config?:
            return ConfigLang.open(context)
        case .lang?:
            return ConfigLang.choose(context)
        case .uninstall?:
            Uninstall.run(context, selfPath: SelfPath.current())
        case let command? where Router.unavailable.contains(command):
            out.write("macup \(command == .selfUpdate ? "self-update" : command.rawValue): not available in this build\n")
            return 1
        default:
            out.write("macup: \(arguments.command?.rawValue ?? "run") is not ported\n")
            return 70
        }
        return 0
    }

    /// A tool in the foreground, with macup's terminal; its exit status, 127 when it is not there.
    static func runTool(_ argv: [String], _ shell: Shell) -> Int32 {
        guard let pid = shell.spawn(argv) else {
            Shell.writeText("macup: \(argv.first ?? ""): command not found\n", to: 2)
            return 127
        }
        return Shell.wait(pid)
    }
}
