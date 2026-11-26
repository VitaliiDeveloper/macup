#!/usr/bin/env python3
"""Unit tests for src/py/macup_helpers.py. Plain unittest: runs with the stock /usr/bin/python3, no installs.
   python3 tests/test_helpers.py"""
import io
import os
import sys
import tempfile
import unicodedata
import unittest
import urllib.parse
from contextlib import redirect_stdout
from unittest import mock

sys.dont_write_bytecode = True   # no __pycache__ in src/py
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "py"))
import macup_helpers as h  # noqa: E402


def uri(path):
    return "file://" + urllib.parse.quote(path)


def mkdirs(*paths):
    for p in paths:
        os.makedirs(p, exist_ok=True)


def touch(*paths):
    for p in paths:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").close()


class Tmp(unittest.TestCase):
    def setUp(self):
        t = tempfile.TemporaryDirectory()
        self.addCleanup(t.cleanup)
        self.tmp = os.path.realpath(t.name)   # /var → /private/var, as $HOME would be


class WorkspaceGone(Tmp):
    def setUp(self):
        super().setUp()
        self.home = os.path.join(self.tmp, "home")
        mkdirs(os.path.join(self.home, "work"))

    def gone(self, u):
        return h.workspace_gone(u, self.home)

    def test_missing_folder_in_home_is_gone(self):
        self.assertTrue(self.gone(uri(self.home + "/work/deleted")))
        self.assertTrue(self.gone(uri(self.home + "/deleted/deeper/still")))

    def test_existing_folder_is_not(self):
        self.assertFalse(self.gone(uri(self.home + "/work")))

    def test_percent_encoded_name(self):
        mkdirs(self.home + "/work/my app")
        self.assertFalse(self.gone("file://" + self.home + "/work/my%20app"))
        self.assertTrue(self.gone("file://" + self.home + "/work/other%20app"))

    def test_localhost_counts_as_local(self):
        self.assertTrue(self.gone("file://localhost" + urllib.parse.quote(self.home + "/work/deleted")))

    def test_not_a_local_folder(self):
        for u in ("vscode-remote://ssh-remote+box" + self.home + "/work/deleted",
                  "file://server" + urllib.parse.quote(self.home + "/work/deleted"),
                  "", None, 42, {"path": self.home}):
            self.assertFalse(self.gone(u), u)

    def test_outside_home_or_dotdot(self):
        self.assertFalse(self.gone(uri(self.tmp + "/elsewhere/deleted")))
        self.assertFalse(self.gone(uri(self.home + "x/deleted")))
        self.assertFalse(self.gone(uri(self.home + "/work/../deleted")))

    def test_library_is_never_a_project(self):
        self.assertFalse(self.gone(uri(self.home + "/Library/Mobile Documents/com~apple~CloudDocs/proj")))

    def test_symlinked_ancestor_may_be_an_unmounted_disk(self):
        mkdirs(self.tmp + "/volume")
        os.symlink(self.tmp + "/volume", self.home + "/ext")
        self.assertFalse(self.gone(uri(self.home + "/ext/deleted")))
        os.symlink(self.tmp + "/nowhere", self.home + "/work/dead")
        self.assertFalse(self.gone(uri(self.home + "/work/dead/deleted")))

    def test_deepest_folder_on_another_disk(self):
        real = os.stat
        work = self.home + "/work"
        def stat(p, *a, **k):
            r = real(p, *a, **k)
            if p == work:
                return os.stat_result((r.st_mode, r.st_ino, r.st_dev + 1) + tuple(r)[3:])
            return r
        with mock.patch.object(h.os, "stat", stat):
            self.assertFalse(self.gone(uri(work + "/deleted")))
            self.assertTrue(self.gone(uri(self.home + "/deleted")))

    @unittest.skipUnless(sys.platform == "darwin", "APFS matches names in either Unicode form")
    def test_nfd_name_on_disk_nfc_in_uri(self):
        mkdirs(self.home + "/work/" + unicodedata.normalize("NFD", "café"))
        self.assertFalse(self.gone(uri(self.home + "/work/" + unicodedata.normalize("NFC", "café"))))
        mkdirs(self.home + "/work/" + unicodedata.normalize("NFC", "naïve"))
        self.assertFalse(self.gone(uri(self.home + "/work/" + unicodedata.normalize("NFD", "naïve"))))


class EditorWorkspaces(Tmp):
    def test_lists_only_workspaces_of_gone_folders(self):
        home, ws = self.tmp + "/home", self.tmp + "/ws"
        mkdirs(home + "/live")
        def w(name, body):
            mkdirs(ws + "/" + name)
            with open(ws + "/" + name + "/workspace.json", "w") as f:
                f.write(body)
        w("a-gone", '{"folder": "%s"}' % uri(home + "/deleted"))
        w("b-live", '{"folder": "%s"}' % uri(home + "/live"))
        w("c-file", '{"workspace": "%s"}' % uri(home + "/deleted/x.code-workspace"))
        w("d-broken", "{not json")
        w("e-remote", '{"folder": "vscode-remote://wsl+Ubuntu/home/me/x"}')
        mkdirs(ws + "/f-empty")
        os.symlink(ws + "/a-gone", ws + "/g-link")
        out = io.StringIO()
        with redirect_stdout(out):
            h.editor_workspaces([ws, home])
        self.assertEqual(out.getvalue().split(), [ws + "/a-gone", ws + "/c-file"])


class ElectronCaches(Tmp):
    NAMES = "Cache|CachedData|Code Cache|GPUCache|logs"
    APPS = "Code|Visual Studio Code\nSlack|Slack"
    BRS = "Brave|Brave Browser|BraveSoftware/Brave-Browser;BraveSoftware"

    def scan(self, covered=""):
        A, K = self.tmp + "/AS", self.tmp + "/Caches"
        mkdirs(A, K)
        rows = h.electron_cache_groups(A, K, self.NAMES, self.APPS, self.BRS, covered)
        return {(r.split("\t")[1], r.split("\t")[2]): r.split("\t") for r in rows}, A, K

    def test_layout(self):
        A, K = self.tmp + "/AS", self.tmp + "/Caches"
        touch(A + "/Code/Local State", A + "/Code/Cache/x", A + "/Code/GPUCache/x")      # table app: its own name
        touch(A + "/Notion/Preferences", A + "/Notion/Cookies", A + "/Notion/Cache/x")   # Chromium by Preferences + Cookies
        touch(A + "/NotChromium/Cache/x")                                                # Cache with nothing of Chromium's
        touch(A + "/Cache/x")                                                            # depth 0: not an app's
        touch(A + "/BraveSoftware/Brave-Browser/Local State", A + "/BraveSoftware/Brave-Browser/Default/History",
              A + "/BraveSoftware/Brave-Browser/Default/Preferences", A + "/BraveSoftware/Brave-Browser/Default/Cookies",
              A + "/BraveSoftware/Brave-Browser/Default/Cache/x")
        touch(K + "/BraveSoftware/Brave-Browser/Default/Cache/x")                       # its ~/Library/Caches half
        touch(K + "/Firefox/Profiles/p.default/cache2/x")                                # cache2 is Firefox's
        touch(K + "/SomeTool/Cache/x")                                                   # in Caches the name is enough
        touch(A + "/Bundled.app/Contents/Cache/x", A + "/x.ShipIt/Cache/x",
              A + "/org.sparkle-project.Sparkle/Cache/x", A + "/com.apple.foo/Cache/x")
        touch(A + "/Deep/1/2/3/4/5/Local State", A + "/Deep/1/2/3/4/5/Cache/x")       # deeper than the walk goes
        g, A, K = self.scan()
        self.assertEqual(sorted(g), [("app", "Notion"), ("app", "SomeTool"), ("app", "Visual Studio Code"),
                                     ("browser", "Brave"), ("browser", "Firefox")])
        lv, kind, name, opened, paths = g[("app", "Visual Studio Code")]
        self.assertEqual(lv, "1")
        self.assertEqual(opened.split("\x1f"), [A + "/Code", K + "/Code"])
        self.assertEqual(paths.split("\x1f"), [A + "/Code/Cache", A + "/Code/GPUCache"])
        lv, _, _, _, paths = g[("browser", "Brave")]
        self.assertEqual(lv, "3")
        self.assertEqual(paths.split("\x1f"), [A + "/BraveSoftware/Brave-Browser/Default/Cache",
                                               K + "/BraveSoftware/Brave-Browser/Default/Cache"])
        self.assertEqual(g[("browser", "Firefox")][4], K + "/Firefox/Profiles/p.default/cache2")

    def test_covered_paths_are_left_to_the_tables(self):
        A = self.tmp + "/AS"
        touch(A + "/Code/Local State", A + "/Code/Cache/x", A + "/Code/GPUCache/x")
        g, A, K = self.scan(covered=A + "/Code/Cache\n" + A + "/Code/GPUCache\n")
        self.assertEqual(g, {})

    def test_symlinked_cache_is_skipped(self):
        A = self.tmp + "/AS"
        touch(A + "/Notion/Local State", self.tmp + "/elsewhere/x")
        os.symlink(self.tmp + "/elsewhere", A + "/Notion/Cache")
        g, A, K = self.scan()
        self.assertEqual(g, {})


class Versions(unittest.TestCase):
    def test_version_key(self):
        self.assertGreater(h.version_key("1.10.0"), h.version_key("1.9.9"))
        self.assertEqual(h.version_key("2.0"), [2, 0])
        self.assertGreater(h.version_key("2.0.1"), h.version_key("2.0"))
        self.assertEqual(h.version_key("1.2.3 (456)"), [1, 2, 3, 456])
        self.assertEqual(h.version_key("latest"), [])

    def test_npm_outdated_rows(self):
        with tempfile.TemporaryDirectory() as root:
            os.symlink(root, os.path.join(root, "linked"))
            d = {"up": {"current": "1.0.0", "latest": "1.2.0"},
                 "same": {"current": "1.0.0", "latest": "1.0.0"},
                 "git": {"current": "git+https://x", "latest": "2.0.0"},
                 "linked": {"current": "1.0.0", "latest": "2.0.0"},
                 "pre": {"current": "1.0.0-beta.1", "latest": "1.0.0"},
                 "empty": {}}
            self.assertEqual(list(h.npm_outdated_rows(d, root)), [("up", "1.0.0", "1.2.0"), ("pre", "1.0.0-beta.1", "1.0.0")])


if __name__ == "__main__":
    unittest.main()
