import Foundation

/// `macup config` and `macup lang` (commands.sh `open_conf`, `choose_lang`).
enum ConfigLang {
    /// Creates the config when there is none; opens it in the editor on a terminal, else prints its path.
    static func open(_ context: OneOff.Context) -> Int32 {
        let env = context.env
        var info = stat()
        if !(stat(env.conf, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG) {
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

    /// Sets `language` in the config, from the argument or from a question on the terminal.
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

/// core.sh's `ask`: the question goes to /dev/tty and the answer comes from there, so it works under `curl | bash`.
enum Terminal {
    static var available: Bool {
        let descriptor = Darwin.open("/dev/tty", O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    /// The line typed, as `read -r` and `echo` hand it on: blanks at both ends gone. "" without a terminal.
    static func ask(_ prompt: String) -> String {
        let writer = Darwin.open("/dev/tty", O_WRONLY)
        if writer >= 0 { Shell.writeText(prompt, to: writer); close(writer) }
        let reader = Darwin.open("/dev/tty", O_RDONLY)
        guard reader >= 0 else { return "" }
        defer { close(reader) }
        var bytes: [UInt8] = [], byte: UInt8 = 0
        while true {
            let count = read(reader, &byte, 1)
            if count < 0, errno == EINTR { continue }
            if count != 1 || byte == 0x0A { break }
            if byte != 0 { bytes.append(byte) }
        }
        let blanks: Set<UInt8> = [0x20, 0x09, 0x0A]
        let trimmed = bytes.drop(while: blanks.contains).reversed().drop(while: blanks.contains).reversed()
        return Bash.substitution(Bash.echo(String(decoding: Array(trimmed), as: UTF8.self)))
    }

    static func isYes(_ answer: String) -> Bool { ["y", "Y", "т", "Т", "д", "Д"].contains(answer) }
}
