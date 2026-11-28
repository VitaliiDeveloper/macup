import Foundation

/// `macup` with no command and no run (2.9's commands.sh `menu`, `mline`; the end of arguments.sh): a terminal gets the menu,
/// anything else the help.
public enum Menu {
    public enum Choice: Equatable {
        case done(Int32)
        /// The word that starts the run picked (check, all, update, clean, --deep): bash's menu sets what that word sets.
        case run(String)
    }

    /// It leaves the environment as it was, for the run it starts.
    public static func run(_ arguments: Arguments, env: Env, translations: String) -> Choice {
        let context = OneOff.Context(arguments, env: env, translations: translations)
        if OneOff.refusesSudo(context) { return .done(1) }
        let i18n = context.i18n, colors = context.colors, out = context.out
        let help = Help.text(lang: context.lang, colors: colors, conf: env.paths.tildify(env.conf))
        guard isatty(0) == 1, isatty(1) == 1 else { out.write(help); return .done(2) }

        out.write("\n\(colors.bold)macup\(colors.reset) — \(i18n.translate("keep your Mac healthy")) \(colors.dim)(v\(Env.version) · \(context.lang.name))\(colors.reset)\n\n")
        let lines = [("1", "Check", "health, security, updates, then pick what to clean"), ("2", "Update & clean", "everything + report"),
                     ("3", "Update only", ""), ("4", "Clean only", ""), ("5", "Deep check", "also largest folders, Downloads, project artifacts"),
                     ("6", "History & trends", ""), ("7", "Latest report", ""), ("8", "Tasks & settings", "what runs, how to turn things off"),
                     ("9", "Language", "English · Українська · Русский"), ("h", "Help", ""), ("q", "Quit", "")]
        for (key, label, hint) in lines {
            let note = hint.isEmpty ? "" : i18n.translate(hint)
            out.write("  \(colors.bold)\(key)\(colors.reset)  \(Text.pad(i18n.translate(label), 24))\(colors.dim)\(note)\(colors.reset)\n")
        }
        out.write("\n")
        let choice = Terminal.ask(i18n.translate("Choose [1]: "))
        switch choice.isEmpty ? "1" : choice {
        case "1": return .run("check")
        case "2": return .run("all")
        case "3": return .run("update")
        case "4": return .run("clean")
        case "5": return .run("--deep")
        case "6": out.write(History.text(context))
        case "7": FileHandle.standardOutput.write(Reports.last(context))
        case "8":
            out.write(TasksCommand.text(context, json: false))
            if Terminal.isYes(Terminal.ask(i18n.translate("Open the config now? [y/N] "))) { _ = ConfigLang.open(context) }
        case "9": _ = ConfigLang.choose(context)
        case "h", "H": out.write(help)
        default: break
        }
        return .done(0)
    }
}
