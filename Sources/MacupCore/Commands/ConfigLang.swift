import Foundation

/// `macup config` and `macup lang` (commands.sh `open_conf`, `choose_lang`).
enum ConfigLang {
    static func open(_ context: OneOff.Context) -> Int32 {
        let env = context.env
        if !Files.isRegular(env.conf) {
            try? FileManager.default.createDirectory(atPath: env.confDir, withIntermediateDirectories: true)
            try? Config.defaultText(lang: context.lang).write(toFile: env.conf, atomically: false, encoding: .utf8)
            context.out.write(context.i18n.format("Created %s", env.paths.tildify(env.conf)) + "\n")
        }
        guard isatty(0) == 1, isatty(1) == 1 else { context.out.write(env.conf + "\n"); return 0 }
        // unquoted in bash: $EDITOR may carry arguments, e.g. "code -w"
        let editor = Env.nonEmpty(env.vars, "VISUAL") ?? Env.nonEmpty(env.vars, "EDITOR") ?? "nano"
        let words = editor.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        _ = OneOff.runTool(words + [env.conf], context.shell)
        return 0
    }

    static func choose(_ context: OneOff.Context) -> Int32 {
        let out = context.out
        var code = context.arguments.langArg
        if code.isEmpty {
            guard Terminal.available else { out.write("macup lang en|uk|ru\n"); return 2 }
            out.write("\n  1  English\n  2  Українська\n  3  Русский\n\n")
            switch Terminal.ask("Language / Мова / Язык [1-3]: ") {
            case "1", "en": code = "en"
            case "2", "uk", "ua": code = "uk"
            case "3", "ru": code = "ru"
            default: out.write("—\n"); return 1
            }
        }
        guard let lang = Lang.option(code) else { out.write("en | uk | ru\n"); return 1 }
        // a config written now says the language the command started in, until the line is replaced
        try? Config.set("language", lang.rawValue, path: context.env.conf, utf8: context.env.utf8Locale) { Config.defaultText(lang: context.lang) }
        out.write(I18n(lang: lang, translationsJSON: context.translations).format("Language: %s", lang.name) + "\n")
        return 0
    }
}
