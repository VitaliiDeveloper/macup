/// `macup tasks` and `macup tasks --json` (2.9's commands.sh `list_tasks`, `tasks_json`).
public enum TasksCommand {
    /// The list after `load_conf`: the config with the command line's --skip, --only and --enable on top.
    static func text(_ context: OneOff.Context, json: Bool) -> String {
        let arguments = context.arguments, env = context.env
        let selection = Selection(Settings(config: context.config, env: env, cliSkip: arguments.cliSkip, cliOnly: arguments.cliOnly,
                                           cliEnable: arguments.cliEnable, cliLevel: arguments.level))
        return json ? self.json(selection: selection, i18n: context.i18n, confPath: env.conf)
            : list(selection: selection, i18n: context.i18n, colors: context.colors, conf: env.paths.tildify(env.conf))
    }

    public static func list(selection: Selection, i18n: I18n, colors: Colors, conf: String) -> String {
        var out = "\(colors.bold)\(Text.pad(i18n.translate("TASK"), 26)) \(Text.pad(i18n.translate("STATE"), 6)) \(i18n.translate("WHAT IT DOES"))\(colors.reset)\n"
        for task in Tasks.all {
            let st = selection.runs(task.id) ? "\(colors.green)\(Text.pad(i18n.translate("on"), 6))\(colors.reset)" : "\(colors.dim)\(Text.pad(i18n.translate("off"), 6))\(colors.reset)"
            out += "\(Text.pad(task.id, 26)) \(st) \(i18n.translate(task.text))\n"
        }
        out += "\n" + i18n.format("Turn tasks off or on in %s (skip = … / enable = …)", conf) + "\n"
        return out
    }

    /// For a program (a GUI); see "For scripts and other programs" in the README.
    public static func json(selection: Selection, i18n: I18n, confPath: String) -> String {
        let tasks = Tasks.all.map { task in
            "{\"id\":\"\(task.id)\",\"group\":\"\(task.group)\",\"default\":\"\(task.on ? "on" : "off")\",\"on\":\(selection.runs(task.id)),\"text\":\"\(JSON.str(i18n.translate(task.text)))\"}"
        }
        return "{\"schema\":1,\"config\":\"\(JSON.str(confPath))\",\"tasks\":[" + tasks.joined(separator: ",") + "]}\n"
    }
}
