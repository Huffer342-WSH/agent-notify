#!/bin/sh

set -eu

PROGRAM_NAME="agent-notify"
DEFAULT_SOURCE_URL="https://raw.githubusercontent.com/Huffer342-WSH/agent-notify/refs/heads/main/agent-notify.py"
INSTALL_DIR="${AGENT_NOTIFY_INSTALL_DIR:-${CODEX_NOTIFY_INSTALL_DIR:-${HOME}/.local/bin}}"
CODEX_DIR="${CODEX_HOME:-${HOME}/.codex}"
CONFIG_PATH="${CODEX_DIR}/config.toml"
CLAUDE_CONFIG_PATH="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/settings.json"
SOURCE_URL="${AGENT_NOTIFY_SOURCE_URL:-${CODEX_NOTIFY_SOURCE_URL:-}}"
UNINSTALL=0
SKIP_CONFIG=0
TARGET=codex

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Options:
  --source-url URL  Download agent-notify.py from a custom URL
  --install-dir DIR Install the executable in DIR (default: ~/.local/bin)
  --target TOOL     Configure codex (default), claude, or all
  --no-config       Install files without changing tool configuration
  --uninstall       Remove selected configuration and unused program files
  -h, --help        Show this help

The codex-notify command is installed as a compatibility alias.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --source-url)
            [ "$#" -ge 2 ] || { echo "error: --source-url requires a URL" >&2; exit 2; }
            SOURCE_URL=$2
            shift 2
            ;;
        --install-dir)
            [ "$#" -ge 2 ] || { echo "error: --install-dir requires a directory" >&2; exit 2; }
            INSTALL_DIR=$2
            shift 2
            ;;
        --target)
            [ "$#" -ge 2 ] || { echo "error: --target requires codex, claude, or all" >&2; exit 2; }
            TARGET=$2
            case "$TARGET" in codex|claude|all) ;; *) echo "error: invalid target: $TARGET" >&2; exit 2 ;; esac
            shift 2
            ;;
        --no-config) SKIP_CONFIG=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done
INSTALL_PATH="${INSTALL_DIR}/${PROGRAM_NAME}"
LEGACY_PATH="${INSTALL_DIR}/codex-notify"

command -v python3 >/dev/null 2>&1 || { echo "error: Python 3 is required" >&2; exit 1; }

update_codex_config() {
    python3 - "$CONFIG_PATH" "$INSTALL_PATH" "$LEGACY_PATH" "$1" <<'PY'
import json
import re
import shutil
import sys
from pathlib import Path

path = Path(sys.argv[1])
installed, legacy, mode = sys.argv[2:]
if not path.exists() and mode == "uninstall":
    sys.exit(0)
text = path.read_text(encoding="utf-8") if path.exists() else ""
lines = text.splitlines(keepends=True)
first_table = next((i for i, line in enumerate(lines) if line.lstrip().startswith("[")), len(lines))
matches = [i for i, line in enumerate(lines[:first_table]) if re.match(r"^notify\s*=", line)]
if mode == "install":
    replacement = f"notify = [{json.dumps(installed)}]\n"
    if matches:
        if any(not re.search(r"\]\s*(?:#.*)?$", lines[i].rstrip()) for i in matches):
            raise ValueError("Multi-line notify configuration is not supported")
        lines[matches[0]] = replacement
        for i in reversed(matches[1:]):
            del lines[i]
    else:
        if first_table and not lines[first_table - 1].endswith("\n"):
            lines[first_table - 1] += "\n"
        lines.insert(first_table, replacement)
else:
    expected = re.compile(r"^notify\s*=\s*\[\s*(?:" + "|".join(re.escape(json.dumps(p)) for p in (installed, legacy)) + r")\s*\]\s*(?:#.*)?$")
    lines = [line for i, line in enumerate(lines) if not (i < first_table and expected.match(line.rstrip()))]
path.parent.mkdir(parents=True, exist_ok=True)
if path.exists():
    shutil.copy2(path, str(path) + ".agent-notify.bak")
path.write_text("".join(lines), encoding="utf-8")
PY
}

update_claude_config() {
    python3 - "$CLAUDE_CONFIG_PATH" "$INSTALL_PATH" "$LEGACY_PATH" "$1" <<'PY'
import json
import shlex
import shutil
import sys
from pathlib import Path

path = Path(sys.argv[1])
installed, legacy, mode = sys.argv[2:]
commands = {shlex.quote(p) + " --claude" for p in (installed, legacy)}
command = shlex.quote(installed) + " --claude"
if not path.exists() and mode == "uninstall":
    sys.exit(0)
data = json.loads(path.read_text(encoding="utf-8-sig")) if path.exists() else {}
if not isinstance(data, dict):
    raise ValueError("Claude settings must be a JSON object")
hooks = data.setdefault("hooks", {})
entries = hooks.setdefault("Stop", [])
updated = []
for entry in entries:
    handlers = entry.get("hooks", [])
    kept = [h for h in handlers if not (h.get("type") == "command" and h.get("command") in commands)]
    if kept == handlers:
        updated.append(entry)
    elif kept:
        updated.append(dict(entry, hooks=kept))
if mode == "install":
    updated.append({"hooks": [{"type": "command", "command": command, "timeout": 10}]})
if updated:
    hooks["Stop"] = updated
else:
    hooks.pop("Stop", None)
if not hooks:
    data.pop("hooks", None)
path.parent.mkdir(parents=True, exist_ok=True)
if path.exists():
    shutil.copy2(path, str(path) + ".agent-notify.bak")
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

update_config() {
    case "$TARGET" in codex|all) update_codex_config "$1" ;; esac
    case "$TARGET" in claude|all) update_claude_config "$1" ;; esac
}

if [ "$UNINSTALL" -eq 1 ]; then
    if [ "$SKIP_CONFIG" -eq 0 ]; then
        update_config uninstall
        # Keep both names while another user-level hook still uses either one.
        if python3 - "$CONFIG_PATH" "$CLAUDE_CONFIG_PATH" "$INSTALL_PATH" "$LEGACY_PATH" <<'PY'
import json
import shlex
import sys
from pathlib import Path

codex, claude = map(Path, sys.argv[1:3])
paths = sys.argv[3:]
used = codex.exists() and any(json.dumps(p) in codex.read_text(encoding="utf-8-sig") for p in paths)
if claude.exists():
    settings = json.loads(claude.read_text(encoding="utf-8-sig"))
    commands = {shlex.quote(p) + " --claude" for p in paths}
    for entries in settings.get("hooks", {}).values():
        for entry in entries:
            for hook in entry.get("hooks", []):
                if hook.get("type") == "command" and hook.get("command") in commands:
                    used = True
sys.exit(0 if used else 1)
PY
        then
            echo "Removed selected configuration; retained shared executables used by another hook."
            exit 0
        else
            status=$?
            [ "$status" -eq 1 ] || exit "$status"
        fi
    fi
    rm -f "$INSTALL_PATH" "$LEGACY_PATH"
    echo "Removed agent-notify and its codex-notify compatibility alias from ${INSTALL_DIR}"
    echo "Restart the selected clients to apply the change."
    exit 0
fi

mkdir -p "$INSTALL_DIR"
temp_file="${INSTALL_PATH}.tmp.$$"
trap 'rm -f "$temp_file"' EXIT HUP INT TERM
script_dir=$(if CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null; then pwd; fi)
local_source="${script_dir}/agent-notify.py"

if [ -z "$SOURCE_URL" ] && [ -n "$script_dir" ] && [ -f "$local_source" ]; then
    cp "$local_source" "$temp_file"
else
    SOURCE_URL=${SOURCE_URL:-$DEFAULT_SOURCE_URL}
    case "$SOURCE_URL" in
        https://*|http://*) ;;
        *) echo "error: --source-url must use http:// or https://" >&2; exit 2 ;;
    esac
    if command -v curl >/dev/null 2>&1; then
        curl --fail --silent --show-error --location "$SOURCE_URL" -o "$temp_file"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$temp_file" "$SOURCE_URL"
    else
        echo "error: curl or wget is required for remote installation" >&2
        exit 1
    fi
fi

python3 - "$temp_file" <<'PY'
import ast
import sys
from pathlib import Path
ast.parse(Path(sys.argv[1]).read_text(encoding="utf-8"))
PY
chmod 755 "$temp_file"
mv "$temp_file" "$INSTALL_PATH"
# A self-contained copy also supports existing hooks and detached --serve runs.
cp "$INSTALL_PATH" "$LEGACY_PATH"
chmod 755 "$LEGACY_PATH"
trap - EXIT HUP INT TERM

if [ "$SKIP_CONFIG" -eq 0 ]; then
    update_config install
fi

echo "Installed agent-notify to ${INSTALL_PATH} (compatibility alias: ${LEGACY_PATH})"
if [ "$SKIP_CONFIG" -eq 0 ]; then
    echo "Configured ${TARGET} notifications (Codex: ${CONFIG_PATH}; Claude: ${CLAUDE_CONFIG_PATH})"
    echo "Existing settings are backed up with the .agent-notify.bak suffix."
fi
echo "Restart the selected clients to apply the change."
