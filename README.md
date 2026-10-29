# Agent Notify

面向编程 Agent 的桌面通知工具，支持 Linux 和 Windows。当 Agent 完成一轮回复后，
Agent Notify 会发送桌面通知，点击通知可尝试返回原来的编辑器或终端窗口。

支持 Codex CLI、Codex VS Code 插件，以及通过 `Stop` Hook 接入的 Claude Code VS Code
插件。Claude Code CLI 共用同一份 Hook 配置，也会触发通知。

## 安装

### 从仓库安装

先克隆仓库并进入项目目录；已有克隆可直接进入目录：

```bash
git clone https://github.com/Huffer342-WSH/agent-notify.git
cd agent-notify
```

Linux 需要 Python 3：

```bash
./install.sh --target all
```

Windows 10/11 使用系统自带的 Windows PowerShell 5.1，不需要 Python 或第三方模块：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Target all
```

目标可选 `codex`、`claude`、`all`。不指定时仍然只配置 Codex，以保持旧版安装行为。
安装后重启对应客户端，并在 Claude Code 中发起新会话测试。

### 在线安装

Linux：

```bash
curl -LsSf https://raw.githubusercontent.com/Huffer342-WSH/agent-notify/refs/heads/main/install.sh | sh -s -- --target all
```

Windows：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Huffer342-WSH/agent-notify/refs/heads/main/install.ps1))) -Target all
```

安装器优先使用同目录的 `agent-notify.py` 或 `agent-notify.ps1`，文件不存在时自动从上述
仓库下载主程序。在线安装使用 `main` 分支中的最新版本。

### 安装位置与配置

Linux 主程序为 `~/.local/bin/agent-notify`，同目录保留 `codex-notify` 兼容命令。
Windows 主程序为 `%LOCALAPPDATA%\AgentNotify\agent-notify.ps1`，同目录保留
`codex-notify.ps1` 兼容入口，并注册当前用户级 `agent-notify://` 点击激活协议。

安装器按所选目标修改配置：

- Codex：`${CODEX_HOME:-~/.codex}/config.toml` 的顶层 `notify` 设置。
- Claude Code：`${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json` 中的 `Stop` Hook。
  这不是 VS Code 的 `settings.json`，插件与 CLI 共用此配置。

安装器在修改前备份配置，后缀为 `.agent-notify.bak`；每次修改前的备份会覆盖上次备份。
Claude 配置必须是有效的 JSON，解析失败时安装器报错，不覆盖原配置。安装器保留其他
Claude 设置和 Hook，重复安装不会追加相同通知命令。

Windows 安装器支持在 `--previous-notify` 包装的命令中替换内层回调。Linux 安装器只管理
单行顶层 `notify` 配置；两种安装器均不支持多行 `notify` 数组。

### 从 Codex Notify 迁移

项目原名 **Codex Notify**，现仓库地址为
[Huffer342-WSH/agent-notify](https://github.com/Huffer342-WSH/agent-notify)。
已有用户建议从新版仓库执行一次 `--target all` / `-Target all` 安装：

- 新配置改用 `agent-notify` 名称，旧命令仍可使用。
- Linux 安装器迁移当前安装目录下的旧 `codex-notify --claude` Hook，避免重复通知。
- Windows 安装器也识别旧默认路径 `%LOCALAPPDATA%\CodexNotify\codex-notify.ps1`，
  迁移所选工具的旧配置。旧目录和旧协议不会自动删除，以保留旧通知及未迁移配置的可用性。
- `AGENT_NOTIFY_INSTALL_DIR`、`AGENT_NOTIFY_SOURCE_URL` 替代原来的 `CODEX_NOTIFY_*`
  安装变量；旧变量仍可作为回退使用。
- 仓库中的 `codex-notify.py`、`codex-notify.ps1` 是兼容启动器，需要与新主程序放在一起。
  手工下载单文件时应使用新的 `agent-notify.py` 或 `agent-notify.ps1`。

迁移只处理当前安装目录，以及 Windows 的旧默认路径。其他自定义路径、手工包装命令
或项目级配置需要自行检查。原来的 `.codex-notify.bak` 备份不删除。

已有克隆可更新远端地址，以下以常见的 `origin` 为例：

```bash
git remote set-url origin https://github.com/Huffer342-WSH/agent-notify.git
```

先用 `git remote -v` 确认远端名；如果使用的是 `github`，将命令中的 `origin` 改为 `github`。

### 安装选项与卸载

自定义目录：

```bash
./install.sh --install-dir ~/bin --target all
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallDir D:\Tools\AgentNotify -Target all
```

更新本地仓库后，可只更新已安装的程序，不修改现有 Hook 配置：

```bash
./install.sh --no-config
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -NoConfig
```

Hook 运行的是安装目录中的程序副本，仅执行 `git pull` 不会更新该副本。如果新通知仍显示
旧图标，请重新运行安装器，再触发一轮回复；已经发出的通知不会自动更换图标。
需要同时迁移旧名称的 Hook 配置时，应使用 `--target all` / `-Target all`，不要加 `NoConfig`。

卸载：

```bash
./install.sh --target all --uninstall
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Target all -Uninstall
```

改用 `claude` 或 `codex` 可只移除对应配置。另一个工具的用户级配置仍引用本次安装时，
安装器保留共享程序和兼容入口。卸载与 `--no-config` / `-NoConfig` 组合时直接删除文件，
不检查引用。手动配置及项目级配置需要自行移除。

## 通知内容与图标

Codex 通知显示会话名称、工作目录、最近的问题和回复摘要。会话名称通过载荷以及 VS Code
系编辑器的 `state.vscdb`、Codex 的 `state_*.sqlite` 查询，失败时显示未命名会话。

Claude 通知标题显示 `Claude Code` 和工作目录，正文显示 `last_assistant_message` 中的
最终回复摘要；旧版 Hook 未提供摘要时显示完成提示。不读取 Claude 会话标题、问题或历史。
只处理主会话的 `Stop`，不处理权限请求、`Notification`、`SubagentStop` 或失败事件。
其他 Stop Hook 如果要求 Claude 继续工作，后续再次触发 Stop 时仍会提醒，因此通知不表示
所有 Hook 均已允许会话结束。

图标按通知来源选择，SVG 数据内嵌在主程序中，不需要联网：

- Codex：深色主题使用浅色图标，浅色主题使用深色图标。
- Claude：使用星芒图标，浅色主题为陶土橙，深色主题为浅橙；路径取自
  [Simple Icons](https://simpleicons.org/?q=claude)（CC0）。

Linux 图标缓存到 `/tmp/agent-notify-<uid>/`，Windows 缓存到 `%LOCALAPPDATA%\AgentNotify`。
通知正文会显示部分问题或回复，可能在共享屏幕或锁屏时暴露内容。可以降低脚本顶部的
`QUESTION_PREVIEW_LIMIT`、`ANSWER_PREVIEW_LIMIT`，或关闭系统锁屏通知预览。

## 桌面支持

### Linux

需要实现 `org.freedesktop.Notifications` 的桌面通知服务。Ubuntu/Debian 推荐安装：

```bash
sudo apt install python3-gi libnotify-bin x11-utils
```

主程序优先使用 PyGObject 的持久 D-Bus 连接接收点击动作，缺失时回退到 `notify-send`。
`xprop` 和 `libX11` 用于 X11 窗口定位与激活，`xdotool`、`wmctrl` 提供额外回退。
支持 VS Code、VSCodium、Cursor、Windsurf、GNOME Terminal、Ghostty、Konsole、Kitty、
Alacritty、WezTerm 等常见应用。

重点验证环境为 Ubuntu 22.04、GNOME、X11。Wayland 通常限制后台激活其他应用，基础通知
仍可使用，但精确返回某个窗口取决于合成器和应用实现。

### Windows

优先使用 WinRT Toast，点击通知经 `agent-notify://` 协议和隐藏的 Windows Script Host
启动器恢复来源窗口，不闪现命令行窗口。协议未安装或 WinRT 失败时回退到
`System.Windows.Forms.NotifyIcon`。

Toast 正文左侧显示来源对应的 SVG 图标。Windows 11 顶部归属区域由 PowerShell AppID
决定，仍可能显示 PowerShell 图标。`NotifyIcon` 不支持 SVG，使用来源应用或系统图标。

Toast 请求 `duration="long"`，横幅消失后可在通知中心查看。实际停留时间由 Windows 决定；
如需延长，请在“设置 → 辅助功能 → 视觉效果 → 在此时间后关闭通知”中调整。
安装器只显示提醒，不修改系统全局设置。

### 远程环境

VS Code Remote SSH、WSL 和容器中的 Hook 在远端环境执行，不会自动把通知转发到本地
桌面。通知外观、动作支持和窗口激活最终取决于操作系统及桌面通知服务。

## 开发与测试

### 手动发送通知

Linux Codex 载荷：

```bash
~/.local/bin/agent-notify '{"type":"agent-turn-complete","thread-id":"test-thread","cwd":"/tmp/example-project","input-messages":["测试通知"],"last-assistant-message":"通知测试完成。"}'
```

Linux Claude 载荷通过标准输入传入：

```bash
printf '%s' '{"hook_event_name":"Stop","session_id":"test-claude","cwd":"/tmp/example-project","last_assistant_message":"Claude 通知测试完成。"}' | ~/.local/bin/agent-notify --claude
```

Windows Codex 载荷：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AgentNotify\agent-notify.ps1" '{"type":"agent-turn-complete","thread-id":"test-thread","cwd":"C:\\Projects\\example","input-messages":["测试通知"],"last-assistant-message":"通知测试完成。"}'
```

以上命令会发送真实桌面通知。

### Hook 配置示例

Codex 顶层配置接收单个 JSON 参数：

```toml
notify = ["/home/用户名/.local/bin/agent-notify"]
```

Claude 在 `settings.json` 中注册命令，并通过标准输入传递 JSON：

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/用户名/.local/bin/agent-notify --claude",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Windows 使用 `-Claude` 读取标准输入；安装器生成 PowerShell `-EncodedCommand` 命令，
避免路径被 Hook Shell 再次解释。脚本不输出决策 JSON，不要求 Claude 继续工作。

参考：[Claude Hook 接口](https://code.claude.com/docs/en/hooks#stop)、
[VS Code 配置](https://code.claude.com/docs/en/vs-code#configure-settings)。

### 自动测试

```bash
python3 -m unittest discover -s tests -v
sh -n install.sh
```

有 PowerShell 运行时时，还可以验证安装器的配置逻辑（不写注册表、不发送通知）：

```powershell
pwsh -NoProfile -File tests/test_install.ps1
```

Windows PowerShell 5.1 可将上述命令中的 `pwsh` 替换为 `powershell.exe`。

测试覆盖通知内容、图标、标准输入、安装配置保留、重复安装、旧名迁移及选择性卸载，
不发送真实通知。Windows Toast 和 VS Code 点击返回仍需在对应桌面环境中验证。

主要文件：`agent-notify.py`、`agent-notify.ps1` 为主程序；`install.sh`、`install.ps1`
负责安装和配置；`tests/test_notify.py` 包含单元测试与 Linux 安装集成测试，
`tests/test_install.ps1` 验证 PowerShell 安装器的配置迁移。
