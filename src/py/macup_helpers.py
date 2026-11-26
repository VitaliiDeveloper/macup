"""Data parsing for macup. build.sh embeds this file into macup as $MACUP_PY; bash runs it as
`python3 -c "$MACUP_PY" <command> args…` and only where python3 exists. Runs on the stock
/usr/bin/python3 (3.9): no newer syntax. An uncaught exception exits non-zero, which bash reads as
"could not check"."""
import collections
import datetime
import glob
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
import urllib.parse


def sim_list(args):
    """stdin: `simctl list devices -j`, "@@", `simctl runtime list -j` → D and R lines, tab-separated."""
    dev_raw, rt_raw = sys.stdin.read().split("@@", 1)
    try: devs = json.loads(dev_raw).get("devices", {})
    except Exception: devs = {}
    try: rts = json.loads(rt_raw)
    except Exception: rts = {}
    for rid, ds in devs.items():
        for d in ds:
            print("D", d.get("udid", ""), d.get("state", ""), rid, d.get("name", "").replace("\t", " "), sep="\t")
    for uid, r in rts.items():
        if not r.get("deletable", True): continue
        ds = devs.get(r.get("runtimeIdentifier", ""), [])
        booted = any(d.get("state") == "Booted" for d in ds)
        plat = r.get("runtimeIdentifier", "").split(".")[-1].split("-")[0]
        print("R", uid, int(r.get("sizeBytes", 0)) // 1024, (r.get("lastUsedAt") or "-")[:10], len(ds), int(booted), plat, r.get("version", "?"), sep="\t")


def profiles_expired(args):
    """profile folders → the provisioning profiles past their ExpirationDate."""
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    for d in args:
        if not os.path.isdir(d) or os.path.islink(d): continue
        for n in sorted(os.listdir(d)):
            p = os.path.join(d, n)
            if not n.endswith((".mobileprovision", ".provisionprofile")) or os.path.islink(p) or not os.path.isfile(p): continue
            try:
                raw = open(p, "rb").read(); a = raw.index(b"<?xml"); b = raw.index(b"</plist>", a) + 8
                exp = plistlib.loads(raw[a:b]).get("ExpirationDate")
            except Exception: continue   # unreadable: not ours to judge
            if isinstance(exp, datetime.datetime) and exp.replace(tzinfo=None) < now: print(p)


def workspace_gone(u, home):
    """A workspace.json folder/workspace URI → True when it names a folder in home that is gone."""
    if not isinstance(u, str) or not u.startswith("file://"):
        return False
    u = urllib.parse.urlparse(u)
    if u.netloc not in ("", "localhost"):
        return False
    w = urllib.parse.unquote(u.path)
    if not w.startswith(home + "/") or "/../" in w or os.path.lexists(w):
        return False
    # iCloud Drive and cloud providers hide folders while signed out; under Library nothing is a project
    if w.startswith(home + "/Library/"):
        return False
    # gone only if the deepest folder still there is a real one on the home folder's disk: a symlink on the way may lead to an unmounted disk
    cur, ok = home, True
    for part in w[len(home) + 1:].split("/"):
        nxt = os.path.join(cur, part)
        if os.path.islink(nxt):
            ok = False; break
        if not os.path.isdir(nxt):
            break
        cur = nxt
    return ok and os.stat(cur).st_dev == os.stat(home).st_dev


def editor_workspaces(args):
    """workspaceStorage folder, home → the workspace folders whose project folder is gone."""
    ws, home = args[0], args[1]
    for d in sorted(os.listdir(ws)):
        p = os.path.join(ws, d)
        if os.path.islink(p) or not os.path.isdir(p):
            continue
        try:
            with open(os.path.join(p, "workspace.json"), encoding="utf-8") as f:
                j = json.load(f)
        except Exception:
            continue
        if workspace_gone(j.get("folder") or j.get("workspace") or "", home):
            print(p)


def electron_cache_groups(A, K, names_s, apps_s, brs_s, covered_s):
    """Application Support, ~/Library/Caches and the tables as macup keeps them → output lines:
    level, kind, name, folders to watch (\\x1f), cache folders (\\x1f), tab-separated."""
    names = set(names_s.split("|"))
    covered = [c for c in covered_s.split("\n") if c]
    apps = dict(l.split("|", 1) for l in apps_s.split("\n") if "|" in l)
    browsers = {d: f[0] for f in (l.split("|") for l in brs_s.split("\n")) if len(f) > 2 for d in f[2].split(";")}
    has = lambda p, n: os.path.exists(os.path.join(p, n))
    def chromium(p):
        return has(p, "Local State") or (has(p, "Preferences") and any(has(p, n) for n in ("Cookies", "TransportSecurity", "Network Persistent State", "DIPS")))
    groups = {}
    def record(root, path):
        if any(path == c or path.startswith(c + "/") for c in covered): return
        top = os.path.relpath(path, root).split(os.sep)[0]
        prof = os.path.dirname(path)
        aprof = prof if root == A else os.path.join(A, os.path.relpath(prof, K))
        udr = aprof
        while udr.startswith(A + os.sep) and not has(udr, "Local State"): udr = os.path.dirname(udr)
        key = os.path.relpath(udr, A) if udr.startswith(A + os.sep) else top
        if key.endswith("/User Data"): key = key[: -len("/User Data")]
        if top in apps: kind, name = "app", apps[top]
        else:
            name = browsers.get(key) or browsers.get(top) or (key.replace("/", " ") if key.count("/") < 2 else top)
            browser = path.endswith("/cache2") or has(aprof, "History") or has(aprof, "Default/History") or has(udr, "Default/History")
            kind = "browser" if browser else "app"
        g = groups.setdefault((kind, name), (set(), {os.path.join(A, top), os.path.join(K, top)}))
        g[0].add(path)
    for root in (A, K):
        for dp, dns, _ in os.walk(root):
            depth = 0 if dp == root else os.path.relpath(dp, root).count(os.sep) + 1
            keep = []
            for d in dns:
                p = os.path.join(dp, d)
                if os.path.islink(p) or d.endswith((".app", ".ShipIt")) or d == "org.sparkle-project.Sparkle": continue
                if depth == 0 and (d.startswith("com.apple.") or d == "macup"): continue
                if d in names or (d == "cache2" and root == K):
                    if depth > 0 and (root == K or (d != "cache2" and chromium(dp))): record(root, p)
                    continue
                if depth < 5: keep.append(d)
            dns[:] = keep
    return ["\t".join(("3" if kind == "browser" else "1", kind, name, "\x1f".join(sorted(opened)), "\x1f".join(sorted(paths))))
            for (kind, name), (paths, opened) in sorted(groups.items())]


def electron_caches(args):
    """Application Support, ~/Library/Caches; env NAMES, APPS, BRS, COVERED → electron_cache_groups lines."""
    for line in electron_cache_groups(args[0], args[1], os.environ["NAMES"], os.environ["APPS"], os.environ["BRS"], os.environ["COVERED"]):
        print(line)


def sim_runtimes(args):
    """stdin: `simctl runtime list -j` → "count KB", then one line per runtime."""
    try: d = json.load(sys.stdin)
    except Exception: sys.exit()
    rs = sorted(d.values(), key=lambda r: (r.get("platformIdentifier", ""), r.get("version", "")))
    print(len(rs), sum(r.get("sizeBytes", 0) for r in rs) // 1024)
    for r in rs: print("%s %s · %.1f GB" % (r.get("platformIdentifier", "").split(".")[-1].replace("platform", ""), r.get("version", "?"), r.get("sizeBytes", 0) / 1e9))


def python_version(args):
    import platform
    print(platform.python_version())


def commands(args):
    """bin folders → the number of scripts, then a line per interpreter that is gone or folder of dead links."""
    n, groups, gone = 0, {}, {}
    dirs = {}
    home = os.path.normpath(os.path.expanduser("~"))
    for x in args:
        if os.path.isdir(x): dirs.setdefault(os.path.realpath(x), x)
    for d in dirs.values():
        try: entries = list(os.scandir(d))
        except OSError: continue
        for e in entries:
            p = e.path
            # files Homebrew installed are brew doctor's job (libevent ships an `env python` script nobody runs)
            if "/Cellar/" in os.path.realpath(p): continue
            if not os.path.exists(p):
                if os.path.islink(p):
                    groups.setdefault(("-", d), set()).add(e.name)
                    # what was removed, so people know whose leftovers these are: Python.framework, Foo.app, node_modules/quicktype
                    t = os.path.normpath(os.path.join(d, os.readlink(p)))
                    m = re.search(r"[^/]+\.(?:framework|app)|node_modules/(?:@[^/]+/)?[^/]+", t)
                    t = m.group(0) if m else os.path.dirname(t)
                    gone.setdefault(d, set()).add("~" + t[len(home):] if t.startswith(home + "/") else t)
                continue
            if not os.path.isfile(p) or not os.access(p, os.X_OK): continue
            try:
                with open(p, "rb") as f: head = f.readline(256)
            except OSError: continue
            if not head.startswith(b"#!"): continue
            n += 1
            args = head[2:].decode("utf-8", "replace").split()
            if not args: continue
            if os.path.basename(args[0]) == "env":
                rest = [a for a in args[1:] if not a.startswith("-") and "=" not in a]
                if not rest or shutil.which(rest[0]): continue
                name = rest[0]
            elif os.access(args[0], os.X_OK): continue
            else: name = os.path.basename(args[0])
            uv = re.search(r"/uv/tools/([^/]+)/", os.path.realpath(p) + " " + args[0])
            hint = "pipx reinstall-all" if "/pipx/venvs/" in os.path.realpath(p) else f"uv tool install --reinstall {uv.group(1)}" if uv else "-"
            groups.setdefault((name, hint), set()).add(e.name)
    print(n)
    for (name, hint), names in sorted(groups.items()):
        names = sorted(names)
        print(name, hint, ", ".join(names[:10]) + (f" +{len(names) - 10}" if len(names) > 10 else ""), ", ".join(sorted(gone.get(hint, ()))), sep="\t")


def certs_expiring(args):
    """stdin: `security find-identity -v -p codesigning` → the signing certificates that expire within 30 days."""
    names = set(re.findall(r"\x22([^\x22]+)\x22", sys.stdin.read()))
    if not names: sys.exit()
    pems = re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", subprocess.run(["security", "find-certificate", "-a", "-p"], capture_output=True, text=True).stdout, re.S)
    soon, newest = 30 * 86400, {}
    def x(pem, *a): return subprocess.run(["openssl", "x509", "-noout", *a], input=pem, capture_output=True, text=True)
    for pem in pems:
        m = re.search(r"^\s*commonName\s*=\s*(.+)$", x(pem, "-subject", "-nameopt", "multiline").stdout, re.M)   # one field per line: a comma in the name stays
        name = m.group(1).strip() if m else ""
        if name not in names or x(pem, "-checkend", "0").returncode != 0: continue   # already expired: it signs nothing, Keychain Access shows it
        end = datetime.datetime.strptime(x(pem, "-enddate").stdout.strip().split("=")[1], "%b %d %H:%M:%S %Y %Z")
        if name not in newest or end > newest[name][0]: newest[name] = (end, pem)   # renewed in Xcode: same name, the newer one counts
    for name in sorted(newest):
        if x(newest[name][1], "-checkend", str(soon)).returncode != 0: print(name)


def crashes(args):
    """→ "S <system crashes>", then "A <count> <app>" for apps of yours that crashed 3+ times in 7 days."""
    home = os.path.expanduser("~")
    d = home + "/Library/Logs/DiagnosticReports"
    now = time.time()
    apps, system, seen = collections.Counter(), 0, set()
    def mine(path): return path.startswith("/Applications/") or path.startswith(home + "/Applications/")
    for f in sorted(glob.glob(d + "/*.ips") + glob.glob(d + "/Retired/*.ips") + glob.glob(d + "/*.crash") + glob.glob(d + "/Retired/*.crash")):
        base = os.path.basename(f)
        if base in seen or base.startswith("ExcUserFault_"): continue
        seen.add(base)
        try:
            text = open(f, errors="replace").read()
            when, name, path = os.path.getmtime(f), re.sub(r"[-_][0-9]{4}-[0-9][0-9]-[0-9][0-9].*", "", base), ""
            if f.endswith(".ips"):
                head, _, body = text.partition("\n")
                h = json.loads(head)
                if str(h.get("bug_type")) != "309": continue
                name = h.get("app_name") or h.get("name") or name
                try: when = datetime.datetime.strptime(h["timestamp"], "%Y-%m-%d %H:%M:%S.%f %z").timestamp()
                except Exception: pass
                m = re.search(r"\x22procPath\x22\s*:\s*(\x22(?:[^\x22\\]|\\.)*\x22)", body)
                path = json.loads(m.group(1)) if m else ""
            else:
                m = re.search(r"^Path:\s+(.+)$", text, re.M)
                path = m.group(1).strip() if m else ""
        except Exception: continue
        if now - when > 7 * 86400: continue
        if mine(path): apps[name] += 1
        else: system += 1
    print("S", system)
    for n, c in apps.most_common():
        if c >= 3: print("A", c, n)


def plugins(args):
    """installed_plugins.json → "name version" of each user-scope Claude Code plugin."""
    d = json.load(open(args[0])); pl = d.get("plugins", d)
    for k, v in sorted(pl.items()):
        es = v if isinstance(v, list) else [v]
        e = next((x for x in es if isinstance(x, dict) and x.get("scope", "user") == "user"), None)
        if e is None: continue   # project/local plugins belong to their project
        print(k, e.get("version") or (e.get("gitCommitSha") or "")[:7] or "?")


REGISTRY_VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+")


def npm_outdated_rows(d, root):
    """`npm outdated -g --json` as a dict, npm's global root → (package, current, latest) to update."""
    for k, v in d.items():
        c, l = str(v.get("current", "")), str(v.get("latest", ""))
        if os.path.islink(os.path.join(root, k)) or not REGISTRY_VERSION.match(c) or not REGISTRY_VERSION.match(l) or c == l: continue
        yield k, c, l


def npm_outdated(args):
    """stdin: `npm outdated -g --json`; npm's global root → "package current latest" lines."""
    try: d = json.load(sys.stdin)
    except Exception: d = {}
    for row in npm_outdated_rows(d, args[0]):
        print(*row)


def skills(args):
    """~/.agents/.skill-lock.json → "name hash" lines."""
    d = json.load(open(args[0]))
    for k, v in sorted(d.get("skills", {}).items()): print(k, v.get("skillFolderHash", "")[:7])


def version_key(v):
    return [int(x) for x in re.findall(r"\d+", v)]


def apps_behind(args):
    """Homebrew's cask.json, ~/Applications → the number of apps checked, then "App have → new" lines."""
    try: brewed = set(subprocess.run(["brew", "list", "--cask"], capture_output=True, text=True).stdout.split())
    except OSError: brewed = set()
    casks = {}
    for c in json.load(open(args[0])):
        if "@" in c["token"]: continue   # beta and other channels of the same app
        for art in c.get("artifacts", []):
            for a in (art.get("app") or [])[:1]:
                if isinstance(a, str): casks.setdefault(a, []).append((c["token"], str(c.get("version", "")).split(",")[0]))
    # brew upgrade covers casks brew installed; two casks with one app name and different versions are different apps (Telegram)
    latest = {a: v[0][1] for a, v in casks.items() if not brewed & {t for t, _ in v} and len({n for _, n in v}) == 1}
    checked, behind = 0, []
    for d in ("/Applications", args[1]):
        if not os.path.isdir(d): continue
        for a in sorted(os.listdir(d)):
            p = os.path.join(d, a)
            if a not in latest or os.path.isdir(p + "/Contents/_MASReceipt"): continue
            try: i = plistlib.load(open(p + "/Contents/Info.plist", "rb"))
            except Exception: continue
            have = str(i.get("CFBundleShortVersionString") or i.get("CFBundleVersion") or "").split(" ")[0]
            new = latest[a]
            if not have or new == "latest": continue
            checked += 1
            if version_key(new) > version_key(have): behind.append("%s %s → %s" % (a[:-4], have, new))
    print(checked); print("\n".join(behind))


COMMANDS = {
    "sim-list": sim_list,
    "profiles-expired": profiles_expired,
    "editor-workspaces": editor_workspaces,
    "electron-caches": electron_caches,
    "sim-runtimes": sim_runtimes,
    "python-version": python_version,
    "commands": commands,
    "certs-expiring": certs_expiring,
    "crashes": crashes,
    "plugins": plugins,
    "npm-outdated": npm_outdated,
    "skills": skills,
    "apps-behind": apps_behind,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print("macup helpers: unknown command %r" % (sys.argv[1:2] or [""])[0], file=sys.stderr)
        sys.exit(2)
    COMMANDS[sys.argv[1]](sys.argv[2:])
