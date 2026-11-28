import Foundation

/// report.sh's Security section, Time Machine included.
extension Checks {
    static let protections: [(argv: [String], on: String, okText: String, warnText: String)] = [
        (["fdesetup", "status"], "is On", "FileVault: on", "FileVault: off — your disk is not encrypted (System Settings → Privacy & Security)"),
        (["/usr/libexec/ApplicationFirewall/socketfilterfw", "--getglobalstate"], "enabled", "Firewall: on", "Firewall: off (System Settings → Network → Firewall)"),
        (["csrutil", "status"], "status: enabled", "System Integrity Protection: on", "System Integrity Protection: off"),
        (["spctl", "--status"], "enabled", "Gatekeeper: on", "Gatekeeper: off — apps from anywhere can run"),
    ]

    static func security(_ run: Run) {
        guard run.task("check.security") else { return }
        let out = run.out
        out.beginSection("Security")
        for protection in protections {
            switch isOn(output(run, protection.argv), protection.on) {
            case true?: out.ok(protection.okText)
            case false?: out.warn(protection.warnText)
            case nil: break
            }
        }
        let preferences = "/Library/Preferences/com.apple.SoftwareUpdate"
        if output(run, ["defaults", "read", preferences, "AutomaticCheckEnabled"]) == "0" {
            out.warn("Automatic update checks: off")
        } else if output(run, ["defaults", "read", preferences, "CriticalUpdateInstall"]) == "0" {
            out.warn("Security responses & system files: not installed automatically")
        } else {
            out.ok("Automatic security updates: on")
        }
        sharing(run)
        if !run.settings.skip.contains(",check.time_machine,") { timeMachine(run) }
    }

    /// `case "$state" in *on*) on ;; "") nothing ;; *) off`.
    static func isOn(_ state: String, _ on: String) -> Bool? {
        state.contains(on) ? true : state.isEmpty ? nil : false
    }

    /// Sharing services that let other computers in: said, not judged (a build machine needs them).
    static func sharing(_ run: Run) {
        let disabled = output(run, ["launchctl", "print-disabled", "system"])
        func listed(_ pattern: String) -> Bool {
            let expression = try! NSRegularExpression(pattern: pattern)
            return Bash.lines(disabled).contains { expression.hasMatch(in: $0) }
        }
        func shared(_ service: String) -> Bool { listed("\"\(service)\" => (enabled|false)") }
        if shared("com.openssh.sshd") { run.out.info("Remote Login (SSH) is on: other computers can log in to this Mac (System Settings → General → Sharing)") }
        if shared("com.apple.screensharing") { run.out.info("Screen Sharing is on: other computers can see and control this Mac (System Settings → General → Sharing)") }
        if shared("com.apple.RemoteDesktop.agent")
            || (!listed("com.apple.RemoteDesktop.agent") && run.shell.tl(0, ["pgrep", "-x", "ARDAgent"], stdout: .null, stderr: .null) == 0) {
            run.out.info("Remote Management is on: other computers can see and control this Mac with Apple Remote Desktop (System Settings → General → Sharing)")
        }
    }

    static func timeMachine(_ run: Run) {
        let out = run.out
        let destination = run.shell.capture(["tmutil", "destinationinfo"], stdin: .inherit)
        guard destination.status == 0, destination.output.contains("Name") else {
            out.warn("Time Machine: no backup destination configured — not using backups? hide this: skip = check.time_machine in %s", run.env.paths.tildify(run.env.conf))
            return
        }
        guard let latest = latestBackup(run.shell.capture(["tmutil", "latestbackup"], stdin: .inherit).output) else {
            out.info("Time Machine: configured (last backup date needs Full Disk Access for Terminal)")
            return
        }
        let age = backupAge(latest, now: time(nil))
        if age > 7 { out.warn("Time Machine: last backup %s (%s days ago)", latest, String(age)) } else { out.ok("Time Machine: last backup %s", latest) }
    }

    /// Whole days since that day's local midnight; 0 for a date strptime rejects. bash's `date -j -f %Y-%m-%d` gave the day the
    /// time of day of its own call, so a second that ticked after `date +%s` made the age a day short.
    static func backupAge(_ day: String, now: time_t) -> Int {
        var midnight = tm()
        guard strptime(day, "%Y-%m-%d", &midnight) != nil else { return 0 }
        midnight.tm_isdst = -1
        return Int((now - mktime(&midnight)) / 86400)
    }

    /// `grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -1`.
    static func latestBackup(_ output: String) -> String? {
        let expression = try! NSRegularExpression(pattern: "[0-9]{4}-[0-9]{2}-[0-9]{2}")
        return Bash.lines(output).flatMap { line in
            expression.matches(in: line, range: NSRange(location: 0, length: (line as NSString).length)).map { (line as NSString).substring(with: $0.range) }
        }.last
    }
}
