import importlib.util
import io
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("notify", ROOT / "agent-notify.py")
assert spec is not None and spec.loader is not None
notify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notify)


class NotificationTests(unittest.TestCase):
    def test_environment_names_remain_backward_compatible(self):
        with patch.dict(os.environ, {"CODEX_NOTIFY_SOURCE_KIND": "terminal"}, clear=True):
            self.assertEqual(notify.notify_environment("SOURCE_KIND"), "terminal")
            with patch.dict(os.environ, {"AGENT_NOTIFY_SOURCE_KIND": "editor"}):
                self.assertEqual(notify.notify_environment("SOURCE_KIND"), "editor")
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(notify.notify_environment("SOURCE_KIND", "unknown"), "unknown")

    def test_old_source_launcher(self):
        result = subprocess.run([sys.executable, str(ROOT / "codex-notify.py"), "--claude"],
                                input='{"hook_event_name":"SubagentStop"}', capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_claude_content_without_codex_database(self):
        payload = {"hook_event_name": "Stop", "session_id": "claude-1",
                   "cwd": "/projects/project", "last_assistant_message": "完成 <测试> & 检查"}
        with patch.object(notify, "session_name", side_effect=AssertionError):
            title, body, session, cwd = notify.notification_content(payload)
        self.assertIn("Claude Code", title)
        self.assertIn("project", title)
        self.assertEqual(body, "完成 &lt;测试&gt; &amp; 检查")
        self.assertEqual((session, cwd), ("claude-1", "/projects/project"))

    def test_stop_hook_active_does_not_suppress_notification(self):
        # This flag means a previous Stop hook continued the turn, not a duplicate.
        self.assertTrue(notify.notification_content({
            "hook_event_name": "Stop", "stop_hook_active": True})[0])

    def test_missing_answer_has_fallback(self):
        self.assertEqual(notify.notification_content({"hook_event_name": "Stop"})[1], "任务已完成")

    def test_other_events_ignored(self):
        for event in ("Notification", "SubagentStop", "StopFailure", "PreToolUse"):
            self.assertEqual(notify.notification_content({"hook_event_name": event}), ("", "", "", ""))

    def test_codex_unchanged(self):
        with patch.object(notify, "session_name", return_value="会话"):
            title, body, session, _ = notify.notification_content({
                "type": "agent-turn-complete", "thread-id": "codex-1", "cwd": "/projects/repo",
                "input-messages": ["first", "last"], "last-assistant-message": "answer"})
        self.assertIn("会话", title)
        self.assertEqual(body, "last —— answer")
        self.assertEqual(session, "codex-1")

    def test_stdin_entry(self):
        payload = {"hook_event_name": "Stop", "last_assistant_message": "你好"}
        with patch.object(sys, "argv", ["notify", "--claude"]), \
                patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), \
                patch.object(notify, "notify", return_value=0) as send:
            self.assertEqual(notify.main(), 0)
            send.assert_called_once_with(payload)

    def test_bad_stdin(self):
        for text in ("not json", "[]", "null"):
            with patch.object(sys, "argv", ["notify", "--claude"]), \
                    patch.object(sys, "stdin", io.StringIO(text)), \
                    patch.object(sys, "stderr", io.StringIO()):
                self.assertEqual(notify.main(), 2)

    def test_claude_mode_rejects_codex_event(self):
        with patch.object(sys, "argv", ["notify", "--claude"]), \
                patch.object(sys, "stdin", io.StringIO('{"type":"agent-turn-complete"}')), \
                patch.object(notify, "notify") as send:
            self.assertEqual(notify.main(), 0)
            send.assert_not_called()


class IconTests(unittest.TestCase):
    def test_icons_for_both_providers_and_themes(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(notify.tempfile, "gettempdir", return_value=directory):
            paths = set()
            for provider, title, data in (("codex", "Codex", notify.CODEX_ICON_PATH_DATA),
                                          ("claude", "Claude", notify.CLAUDE_ICON_PATH_DATA)):
                for dark, color in ((False, "#D97757"), (True, "#E8A48A")):
                    with patch.object(notify, "prefers_dark_theme", return_value=dark):
                        path = Path(notify.notification_icon(provider))
                        paths.add(path)
                        svg = ET.fromstring(path.read_text())  # noqa: S314 - trusted SVG generated by this test
                        svg_title, svg_path = svg.find("{*}title"), svg.find("{*}path")
                        assert svg_title is not None and svg_path is not None
                        self.assertEqual(svg_title.text, title)
                        self.assertEqual(svg_path.attrib["d"], data)
                        expected = color if provider == "claude" else ("#F7F7F8" if dark else "#202123")
                        self.assertEqual(svg.attrib["fill"], expected)
                        # Cached content must not be rewritten on a second request.
                        before = path.stat().st_mtime_ns
                        self.assertEqual(notify.notification_icon(provider), str(path))
                        self.assertEqual(path.stat().st_mtime_ns, before)
            self.assertEqual(len(paths), 4)

    def test_icon_cache_failure_falls_back(self):
        with patch.object(Path, "mkdir", side_effect=OSError):
            self.assertEqual(notify.notification_icon("claude"), "dialog-information")

    def test_notify_send_uses_claude_icon_and_app_name(self):
        with patch.object(notify.shutil, "which", return_value="/usr/bin/notify-send"), \
                patch.object(notify, "notification_icon", return_value="/icons/claude.svg") as icon, \
                patch.object(notify.subprocess, "run") as run:
            self.assertTrue(notify.send_fallback("title", "body", provider="claude"))
            icon.assert_called_once_with("claude")
            command = run.call_args.args[0]
            self.assertIn("--app-name=Claude Code", command)
            self.assertIn("--icon=/icons/claude.svg", command)

    def test_serve_entry_preserves_provider(self):
        for payload, provider in (({"hook_event_name": "Stop"}, "claude"),
                                  ({"type": "agent-turn-complete"}, "codex")):
            with patch.object(sys, "argv", ["notify", "--serve", json.dumps(payload)]), \
                    patch.object(notify, "session_name", return_value="session"), \
                    patch.object(notify, "serve_desktop_notification", return_value=0) as serve:
                self.assertEqual(notify.main(), 0)
                self.assertEqual(serve.call_args.args[-1], provider)

    def test_dbus_uses_claude_icon_and_app_name(self):
        gio, glib = MagicMock(), MagicMock()
        glib.Variant.side_effect = lambda signature, value: value
        connection = gio.bus_get_sync.return_value
        connection.call_sync.return_value.unpack.side_effect = [["actions"], [42]]
        with patch.object(notify, "Gio", gio), patch.object(notify, "GLib", glib), \
                patch.dict(os.environ, {"DBUS_SESSION_BUS_ADDRESS": "test"}), \
                patch.object(notify, "notification_icon", return_value="/icons/claude.svg") as icon:
            self.assertEqual(notify.serve_desktop_notification("title", "body", "id", "cwd", "claude"), 0)
        icon.assert_called_once_with("claude")
        args = connection.call_sync.call_args.args[4]
        self.assertEqual(args[0], "Claude Code")
        self.assertEqual(args[2], "/icons/claude.svg")
        self.assertEqual(args[6]["x-canonical-private-synchronous"], "claude-id")

    def test_no_gi_fallback_preserves_provider(self):
        with patch.object(notify, "Gio", None), \
                patch.object(notify, "send_fallback", return_value=True) as send:
            self.assertEqual(notify.serve_desktop_notification("title", "body", "id", "cwd", "claude"), 0)
            send.assert_called_once_with("title", "body", "cwd", "claude")

    def test_popen_failure_preserves_provider(self):
        with patch.object(notify, "source_context", return_value=("editor", [123], "code", "code", "code")), \
                patch.object(notify, "notification_python", return_value=sys.executable), \
                patch.object(notify.subprocess, "Popen", side_effect=OSError), \
                patch.object(notify, "serve_desktop_notification", return_value=0) as serve, \
                patch.dict(os.environ):
            self.assertEqual(notify.notify({"hook_event_name": "Stop"}), 0)
            self.assertEqual(serve.call_args.args[-1], "claude")

    def test_windows_svg_matches_linux(self):
        source = (ROOT / "agent-notify.ps1").read_text()
        template = re.search(r"\$script:ClaudeIconSvgTemplate = @'\n(.*?)\n'@", source, re.S)
        assert template is not None
        svg = ET.fromstring(template.group(1).replace("{color}", "#D97757"))  # noqa: S314 - trusted repository fixture
        svg_title, svg_path = svg.find("{*}title"), svg.find("{*}path")
        assert svg_title is not None and svg_path is not None
        self.assertEqual(svg_title.text, "Claude")
        self.assertEqual(svg_path.attrib["d"], notify.CLAUDE_ICON_PATH_DATA)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / "bin with ' quote 中文"
        self.claude = self.home / "custom-claude" / "settings.json"
        self.codex = self.home / "custom-codex" / "config.toml"
        self.env = dict(os.environ, HOME=str(self.home),
                        CLAUDE_CONFIG_DIR=str(self.claude.parent), CODEX_HOME=str(self.codex.parent))

    def install(self, *args, success=True):
        result = subprocess.run(["sh", str(ROOT / "install.sh"), "--install-dir", str(self.bin), *args],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def settings(self):
        return json.loads(self.claude.read_text())

    def test_claude_install_idempotent_and_preserves_settings(self):
        self.claude.parent.mkdir()
        original = {"env": {"EXAMPLE": "你好"}, "hooks": {
            "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "echo existing"}]}],
            "Notification": [{"hooks": [{"type": "command", "command": "echo other"}]}]}}
        self.claude.write_text(json.dumps(original))
        self.install("--target", "claude")
        self.assertEqual(json.loads(Path(str(self.claude) + ".agent-notify.bak").read_text()), original)
        self.install("--target", "claude")
        data = self.settings()
        self.assertEqual(data["env"], original["env"])
        self.assertEqual(data["hooks"]["Notification"], original["hooks"]["Notification"])
        self.assertEqual(len(data["hooks"]["Stop"]), 2)
        command = data["hooks"]["Stop"][-1]["hooks"][0]["command"]
        self.assertEqual(shlex.split(command), [str(self.bin / "agent-notify"), "--claude"])
        # Exercise shell quoting and stdin without producing a desktop notification.
        result = subprocess.run(["sh", "-c", command], input='{"hook_event_name":"SubagentStop"}',
                                capture_output=True, text=True, env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.codex.exists())
        self.install("--target", "claude", "--uninstall")
        self.assertEqual(self.settings(), original)
        self.assertFalse((self.bin / "agent-notify").exists())
        self.assertFalse((self.bin / "codex-notify").exists())

    def test_all_and_selective_uninstall(self):
        self.install("--target", "all")
        self.assertTrue(self.codex.exists())
        self.assertTrue(self.claude.exists())
        self.install("--target", "codex", "--uninstall")
        self.assertTrue((self.bin / "agent-notify").exists())
        self.assertTrue((self.bin / "codex-notify").exists())
        self.install("--target", "claude", "--uninstall")
        self.assertFalse((self.bin / "agent-notify").exists())
        self.assertFalse((self.bin / "codex-notify").exists())

    def test_claude_uninstall_preserves_codex(self):
        self.install("--target", "all")
        self.install("--target", "claude", "--uninstall")
        self.assertTrue((self.bin / "agent-notify").exists())
        self.assertIn("notify =", self.codex.read_text())

    def test_legacy_claude_hook_migrated_without_duplicate(self):
        self.claude.parent.mkdir()
        legacy_command = shlex.quote(str(self.bin / "codex-notify")) + " --claude"
        self.claude.write_text(json.dumps({"hooks": {"Stop": [{"hooks": [
            {"type": "command", "command": legacy_command},
            {"type": "command", "command": "echo keep"}]}]}}))
        self.install("--target", "claude")
        commands = [h["command"] for e in self.settings()["hooks"]["Stop"] for h in e["hooks"]]
        self.assertNotIn(legacy_command, commands)
        self.assertEqual(len(commands), 2)
        self.assertIn("echo keep", commands)
        self.assertIn(shlex.quote(str(self.bin / "agent-notify")) + " --claude", commands)

    def test_legacy_codex_config_migrated(self):
        self.codex.parent.mkdir()
        self.codex.write_text('notify = [' + json.dumps(str(self.bin / "codex-notify")) + ']\nmodel = "example"\n')
        self.install()
        self.assertIn(json.dumps(str(self.bin / "agent-notify")), self.codex.read_text())
        self.assertIn('model = "example"', self.codex.read_text())

    def test_old_alias_still_accepts_claude_stdin(self):
        self.install("--no-config")
        old, new = self.bin / "codex-notify", self.bin / "agent-notify"
        self.assertEqual(old.read_bytes(), new.read_bytes())
        result = subprocess.run([str(old), "--claude"], input='{"hook_event_name":"SubagentStop"}',
                                capture_output=True, text=True, env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_shared_legacy_reference_retains_both_names(self):
        self.install("--target", "all")
        self.claude.write_text(json.dumps({"hooks": {"Stop": [{"hooks": [{"type": "command",
            "command": shlex.quote(str(self.bin / "codex-notify")) + " --claude"}]}]}}))
        self.install("--target", "codex", "--uninstall")
        self.assertTrue((self.bin / "agent-notify").exists())
        self.assertTrue((self.bin / "codex-notify").exists())
        self.install("--target", "claude", "--uninstall")
        self.assertFalse((self.bin / "agent-notify").exists())
        self.assertFalse((self.bin / "codex-notify").exists())

    def test_default_only_codex(self):
        self.install()
        self.assertTrue(self.codex.exists())
        self.assertFalse(self.claude.exists())

    def test_install_environment_names(self):
        for name in ("AGENT_NOTIFY_INSTALL_DIR", "CODEX_NOTIFY_INSTALL_DIR"):
            with self.subTest(name=name):
                target = self.home / name
                env = dict(self.env, **{name: str(target)})
                env.pop("AGENT_NOTIFY_SOURCE_URL", None)
                env.pop("CODEX_NOTIFY_SOURCE_URL", None)
                result = subprocess.run(["sh", str(ROOT / "install.sh"), "--no-config"],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue((target / "agent-notify").exists())
                self.assertTrue((target / "codex-notify").exists())

    def test_no_config(self):
        self.install("--target", "all", "--no-config")
        self.assertFalse(self.codex.exists())
        self.assertFalse(self.claude.exists())

    def test_invalid_json_not_overwritten(self):
        self.claude.parent.mkdir()
        self.claude.write_text("{broken")
        self.install("--target", "claude", success=False)
        self.assertEqual(self.claude.read_text(), "{broken")

    def test_invalid_target(self):
        self.install("--target", "unknown", success=False)
        self.assertFalse((self.bin / "agent-notify").exists())


if __name__ == "__main__":
    unittest.main()
