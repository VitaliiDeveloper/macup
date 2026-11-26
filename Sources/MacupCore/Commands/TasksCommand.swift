/// `macup tasks` and `macup tasks --json` (commands.sh `list_tasks`, `tasks_json`).
public enum TasksCommand {
    public static func list(selection: Selection, i18n: I18n, colors c: Colors, conf: String) -> String {
        var out = "\(c.b)\(Text.pad(i18n.t("TASK"), 26)) \(Text.pad(i18n.t("STATE"), 6)) \(i18n.t("WHAT IT DOES"))\(c.n)\n"
        for t in Tasks.all {
            let st = selection.runs(t.id) ? "\(c.g)\(Text.pad(i18n.t("on"), 6))\(c.n)" : "\(c.d)\(Text.pad(i18n.t("off"), 6))\(c.n)"
            out += "\(Text.pad(t.id, 26)) \(st) \(i18n.t(t.text))\n"
        }
        out += "\n" + i18n.f("Turn tasks off or on in %s (skip = … / enable = …)", conf) + "\n"
        return out
    }

    /// For a program (a GUI); see "For scripts and other programs" in the README.
    public static func json(selection: Selection, i18n: I18n, confPath: String) -> String {
        let tasks = Tasks.all.map { t in
            "{\"id\":\"\(t.id)\",\"group\":\"\(t.group)\",\"default\":\"\(t.on ? "on" : "off")\",\"on\":\(selection.runs(t.id)),\"text\":\"\(JSON.str(i18n.t(t.text)))\"}"
        }
        return "{\"schema\":1,\"config\":\"\(JSON.str(confPath))\",\"tasks\":[" + tasks.joined(separator: ",") + "]}\n"
    }
}
