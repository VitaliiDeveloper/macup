import Darwin

/// The one-off commands the Swift build runs itself (arguments.sh, after the options are read).
public enum OneOff {
    /// Runs a routed command; returns the exit status. `translations` is src/i18n/translations.json.
    public static func run(_ arguments: Arguments, env: Env, translations: String) -> Int32 {
        env.apply()
        let shell = Shell(env: env)
        let config = Config(env: env)
        lazy var lang: Lang = arguments.lang ?? Lang.initial(env: env, config: config, shell: shell)
        var colors = Colors.initial(env: env)
        if arguments.noColor { colors = .off }
        let out = Output(i18n: I18n(lang: .en, translations: [:]), colors: colors)

        if env.underSudo, !arguments.runsUnderSudo {
            // under sudo the config, the reports and the history would become root's, and the next plain run could not write them
            out.write(I18n(lang: lang, translationsJSON: translations).translate("macup does not need sudo: run it as yourself.") + "\n")
            return 1
        }
        switch arguments.command {
        case .version?:
            out.write("macup \(Env.version)\n")
        case .help?:
            out.write(Help.text(lang: lang, colors: colors, conf: env.paths.tildify(env.conf)))
        case .tasks?:
            let i18n = I18n(lang: lang, translationsJSON: translations)
            let settings = Settings(config: config, env: env, cliSkip: arguments.cliSkip, cliOnly: arguments.cliOnly, cliEnable: arguments.cliEnable, cliLevel: arguments.level)
            let sel = Selection(settings)
            out.write(arguments.json ? TasksCommand.json(selection: sel, i18n: i18n, confPath: env.conf)
                             : TasksCommand.list(selection: sel, i18n: i18n, colors: colors, conf: env.paths.tildify(env.conf)))
        case let command? where Router.unavailable.contains(command):
            out.write("macup \(command == .selfUpdate ? "self-update" : command.rawValue): not available in this build\n")
            return 1
        default:
            out.write("macup: \(arguments.command?.rawValue ?? "run") is not ported\n")
            return 70
        }
        return 0
    }
}
