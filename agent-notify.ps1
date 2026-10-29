[CmdletBinding(DefaultParameterSetName = "Notify")]
param(
    [Parameter(Position = 0, ParameterSetName = "Notify")]
    [string]$Payload,

    [Parameter(ParameterSetName = "Notify")]
    [switch]$Claude,

    [Parameter(Mandatory = $true, ParameterSetName = "Serve")]
    [switch]$Serve,

    [Parameter(Mandatory = $true, ParameterSetName = "Serve")]
    [string]$NotificationData,

    [Parameter(Mandatory = $true, ParameterSetName = "Activate")]
    [string]$ActivationUri
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:QuestionPreviewLimit = 300
$script:AnswerPreviewLimit = 300
$script:SessionPreviewLimit = 40
$script:DirectoryPreviewLimit = 24
$script:TitlePreviewLimit = 72
$script:WatchSeconds = 120
$script:CodexIconSvgTemplate = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="{color}" fill-rule="evenodd">
  <title>Codex</title>
  <path clip-rule="evenodd" d="M8.086.457a6.105 6.105 0 013.046-.415c1.333.153 2.521.72 3.564 1.7a.117.117 0 00.107.029c1.408-.346 2.762-.224 4.061.366l.063.03.154.076c1.357.703 2.33 1.77 2.918 3.198.278.679.418 1.388.421 2.126a5.655 5.655 0 01-.18 1.631.167.167 0 00.04.155 5.982 5.982 0 011.578 2.891c.385 1.901-.01 3.615-1.183 5.14l-.182.22a6.063 6.063 0 01-2.934 1.851.162.162 0 00-.108.102c-.255.736-.511 1.364-.987 1.992-1.199 1.582-2.962 2.462-4.948 2.451-1.583-.008-2.986-.587-4.21-1.736a.145.145 0 00-.14-.032c-.518.167-1.04.191-1.604.185a5.924 5.924 0 01-2.595-.622 6.058 6.058 0 01-2.146-1.781c-.203-.269-.404-.522-.551-.821a7.74 7.74 0 01-.495-1.283 6.11 6.11 0 01-.017-3.064.166.166 0 00.008-.074.115.115 0 00-.037-.064 5.958 5.958 0 01-1.38-2.202 5.196 5.196 0 01-.333-1.589 6.915 6.915 0 01.188-2.132c.45-1.484 1.309-2.648 2.577-3.493.282-.188.55-.334.802-.438.286-.12.573-.22.861-.304a.129.129 0 00.087-.087A6.016 6.016 0 015.635 2.31C6.315 1.464 7.132.846 8.086.457zm-.804 7.85a.848.848 0 00-1.473.842l1.694 2.965-1.688 2.848a.849.849 0 001.46.864l1.94-3.272a.849.849 0 00.007-.854l-1.94-3.393zm5.446 6.24a.849.849 0 000 1.695h4.848a.849.849 0 000-1.696h-4.848z"/>
</svg>
'@

# Claude mark from https://cdn.simpleicons.org/claude (Simple Icons, CC0).
$script:ClaudeIconSvgTemplate = @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="{color}">
  <title>Claude</title>
  <path d="m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"/>
</svg>
'@

function Test-WindowsDarkTheme {
    try {
        $settings = Get-ItemProperty -LiteralPath `
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" `
            -Name "AppsUseLightTheme" -ErrorAction Stop
        return [int]$settings.AppsUseLightTheme -eq 0
    } catch {
        return $false
    }
}

function Get-NotificationIconUri {
    param([string]$Provider = "codex")

    try {
        $isClaude = $Provider -eq "claude"
        $providerName = if ($isClaude) { "claude" } else { "codex" }
        $darkTheme = Test-WindowsDarkTheme
        $theme = if ($darkTheme) { "dark" } else { "light" }
        $color = if ($isClaude) {
            if ($darkTheme) { "#E8A48A" } else { "#D97757" }
        } else {
            if ($darkTheme) { "#F7F7F8" } else { "#202123" }
        }
        $template = if ($isClaude) { $script:ClaudeIconSvgTemplate } else { $script:CodexIconSvgTemplate }
        $iconDirectory = Join-Path $env:LOCALAPPDATA "AgentNotify"
        [void](New-Item -ItemType Directory -Path $iconDirectory -Force)
        $iconPath = Join-Path $iconDirectory "$providerName-$theme.svg"
        $content = $template.Replace("{color}", $color) +
            [Environment]::NewLine
        $current = if (Test-Path -LiteralPath $iconPath) {
            [IO.File]::ReadAllText($iconPath, [Text.Encoding]::UTF8)
        } else {
            ""
        }
        if ($current -ne $content) {
            $encoding = New-Object Text.UTF8Encoding($false)
            [IO.File]::WriteAllText($iconPath, $content, $encoding)
        }
        return ([Uri]$iconPath).AbsoluteUri
    } catch {
        return ""
    }
}

function Convert-ToCompactText {
    param(
        [object]$Value,
        [int]$Limit
    )

    if ($null -eq $Value) {
        return ""
    }

    if ($Value -is [string]) {
        $text = $Value
    } else {
        try {
            $text = $Value | ConvertTo-Json -Compress -Depth 20
        } catch {
            $text = [string]$Value
        }
    }

    $text = (($text -replace "\s+", " ").Trim())
    if ($text.Length -le $Limit) {
        return $text
    }

    return $text.Substring(0, [Math]::Max(0, $Limit - 3)).TrimEnd() + "..."
}

function Get-EventValue {
    param(
        [object]$Event,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $Event.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value) {
            $value = [string]$property.Value
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
    }

    return ""
}

function Get-LastInputMessage {
    param([object]$Event)

    $property = $Event.PSObject.Properties["input-messages"]
    if ($null -eq $property -or $null -eq $property.Value) {
        return Get-EventValue $Event @(
            "last-user-message",
            "user-message",
            "prompt",
            "input"
        )
    }

    $messages = @($property.Value)
    for ($index = $messages.Count - 1; $index -ge 0; $index--) {
        $message = Convert-ToCompactText $messages[$index] $script:QuestionPreviewLimit
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            return $message
        }
    }

    return ""
}

function Initialize-NativeSqlite {
    if ("AgentNotify.NativeSqlite" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace AgentNotify
{
    public static class NativeSqlite
    {
        private const int SQLITE_OK = 0;
        private const int SQLITE_ROW = 100;
        private const int SQLITE_OPEN_READONLY = 1;
        private static readonly IntPtr SQLITE_TRANSIENT = new IntPtr(-1);
        public static string LastError = String.Empty;

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_open_v2(
            IntPtr filename, out IntPtr database, int flags, IntPtr vfs);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_close(IntPtr database);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_prepare_v2(
            IntPtr database, IntPtr sql, int length, out IntPtr statement,
            IntPtr tail);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_bind_text(
            IntPtr statement, int index, IntPtr value, int length,
            IntPtr destructor);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_step(IntPtr statement);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr sqlite3_column_text(
            IntPtr statement, int column);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_column_bytes(
            IntPtr statement, int column);

        [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
        private static extern int sqlite3_finalize(IntPtr statement);

        private static IntPtr Utf8(string value, out int length)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(value ?? String.Empty);
            length = bytes.Length;
            IntPtr pointer = Marshal.AllocHGlobal(length + 1);
            Marshal.Copy(bytes, 0, pointer, length);
            Marshal.WriteByte(pointer, length, 0);
            return pointer;
        }

        private static string ColumnText(IntPtr statement, int column)
        {
            IntPtr pointer = sqlite3_column_text(statement, column);
            if (pointer == IntPtr.Zero)
                return String.Empty;

            int length = sqlite3_column_bytes(statement, column);
            if (length <= 0)
                return String.Empty;

            byte[] bytes = new byte[length];
            Marshal.Copy(pointer, bytes, 0, length);
            return Encoding.UTF8.GetString(bytes);
        }

        public static string[] QueryFirst(
            string databasePath, string sql, string parameter, int columns)
        {
            IntPtr database = IntPtr.Zero;
            IntPtr statement = IntPtr.Zero;
            IntPtr filename = IntPtr.Zero;
            IntPtr query = IntPtr.Zero;
            IntPtr value = IntPtr.Zero;
            try
            {
                LastError = String.Empty;
                int filenameLength;
                filename = Utf8(databasePath, out filenameLength);
                int status = sqlite3_open_v2(filename, out database,
                        SQLITE_OPEN_READONLY, IntPtr.Zero);
                if (status != SQLITE_OK)
                {
                    LastError = "sqlite3_open_v2 returned " + status;
                    return null;
                }

                int queryLength;
                query = Utf8(sql, out queryLength);
                status = sqlite3_prepare_v2(database, query, queryLength,
                        out statement, IntPtr.Zero);
                if (status != SQLITE_OK)
                {
                    LastError = "sqlite3_prepare_v2 returned " + status;
                    return null;
                }

                if (!String.IsNullOrEmpty(parameter))
                {
                    int valueLength;
                    value = Utf8(parameter, out valueLength);
                    status = sqlite3_bind_text(statement, 1, value,
                            valueLength, SQLITE_TRANSIENT);
                    if (status != SQLITE_OK)
                    {
                        LastError = "sqlite3_bind_text returned " + status;
                        return null;
                    }
                }

                status = sqlite3_step(statement);
                if (status != SQLITE_ROW)
                {
                    LastError = "sqlite3_step returned " + status;
                    return null;
                }

                var result = new List<string>();
                for (int index = 0; index < columns; index++)
                    result.Add(ColumnText(statement, index));
                return result.ToArray();
            }
            finally
            {
                if (statement != IntPtr.Zero)
                    sqlite3_finalize(statement);
                if (database != IntPtr.Zero)
                    sqlite3_close(database);
                if (value != IntPtr.Zero)
                    Marshal.FreeHGlobal(value);
                if (query != IntPtr.Zero)
                    Marshal.FreeHGlobal(query);
                if (filename != IntPtr.Zero)
                    Marshal.FreeHGlobal(filename);
            }
        }
    }
}
'@
}

function Get-VSCodeSessionName {
    param([string]$ThreadId)

    if ([string]::IsNullOrWhiteSpace($ThreadId)) {
        return ""
    }

    $storageRoots = @(
        (Join-Path $env:APPDATA "Code\User\workspaceStorage"),
        (Join-Path $env:APPDATA "Code - Insiders\User\workspaceStorage"),
        (Join-Path $env:APPDATA "VSCodium\User\workspaceStorage"),
        (Join-Path $env:APPDATA "Cursor\User\workspaceStorage"),
        (Join-Path $env:APPDATA "Windsurf\User\workspaceStorage")
    )

    $databases = foreach ($root in $storageRoots) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -Filter "state.vscdb" -File -Recurse `
                -ErrorAction SilentlyContinue
        }
    }

    foreach ($database in @($databases | Sort-Object LastWriteTimeUtc -Descending)) {
        try {
            $row = [AgentNotify.NativeSqlite]::QueryFirst(
                $database.FullName,
                "SELECT value FROM ItemTable WHERE key = 'agentSessions.model.cache'",
                $null,
                1
            )
            if ($null -eq $row -or [string]::IsNullOrWhiteSpace($row[0])) {
                continue
            }

            $sessions = $row[0] | ConvertFrom-Json
            foreach ($session in $sessions) {
                $resource = [string]$session.resource
                if ($resource.EndsWith("/$ThreadId", [StringComparison]::OrdinalIgnoreCase)) {
                    $label = Convert-ToCompactText $session.label $script:SessionPreviewLimit
                    if (-not [string]::IsNullOrWhiteSpace($label)) {
                        return $label
                    }
                }
            }
        } catch {
            continue
        }
    }

    return ""
}

function Get-CodexSessionName {
    param([string]$ThreadId)

    if ([string]::IsNullOrWhiteSpace($ThreadId)) {
        return ""
    }

    $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        Join-Path $HOME ".codex"
    } else {
        $env:CODEX_HOME
    }

    $databases = Get-ChildItem -LiteralPath $codexHome -Filter "state_*.sqlite" `
        -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending
    foreach ($database in @($databases)) {
        try {
            $row = [AgentNotify.NativeSqlite]::QueryFirst(
                $database.FullName,
                "SELECT name, title FROM threads WHERE id = ?",
                $ThreadId,
                2
            )
            if ($null -eq $row) {
                continue
            }

            foreach ($value in $row) {
                $name = Convert-ToCompactText $value $script:SessionPreviewLimit
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    return $name
                }
            }
        } catch {
            continue
        }
    }

    return ""
}

function Get-SessionName {
    param(
        [object]$Event,
        [string]$ThreadId
    )

    $payloadName = Get-EventValue $Event @(
        "conversation-title",
        "conversation-name",
        "session-title",
        "session-name",
        "thread-title",
        "title"
    )
    if (-not [string]::IsNullOrWhiteSpace($payloadName)) {
        return Convert-ToCompactText $payloadName $script:SessionPreviewLimit
    }

    try {
        Initialize-NativeSqlite
        $name = Get-VSCodeSessionName $ThreadId
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            return $name
        }

        $name = Get-CodexSessionName $ThreadId
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            return $name
        }
    } catch {
        # A title lookup failure must not prevent the base notification.
    }

    return "Unnamed session"
}

function Get-SourceContext {
    param([string]$Cwd)

    $knownNames = @(
        "Code", "Code - Insiders", "VSCodium", "Cursor", "Windsurf",
        "Codex", "WindowsTerminal", "wezterm-gui", "alacritty", "kitty",
        "ConEmu64", "mintty", "Tabby"
    )
    $vscodeProcessId = 0
    if ([int]::TryParse($env:VSCODE_PID, [ref]$vscodeProcessId) -and
        $vscodeProcessId -gt 0) {
        try {
            $vscodeProcess = Get-Process -Id $vscodeProcessId -ErrorAction Stop
            return [pscustomobject]@{
                WindowHandle = $vscodeProcess.MainWindowHandle.ToInt64()
                ProcessId = $vscodeProcess.Id
                ProcessName = $vscodeProcess.ProcessName
                ExecutablePath = $vscodeProcess.Path
            }
        } catch {
            # Continue with parent-chain and process-name detection.
        }
    }

    $chainNames = New-Object System.Collections.Generic.List[string]
    $chainIds = New-Object System.Collections.Generic.List[int]
    $currentId = $PID
    $processTable = @{}
    try {
        foreach ($processInfo in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
            $processTable[[int]$processInfo.ProcessId] = $processInfo
        }
    } catch {
        # Candidate window matching below still works without a process tree.
    }

    for ($depth = 0; $depth -lt 20 -and $currentId -gt 0; $depth++) {
        $processInfo = $processTable[$currentId]
        if ($null -eq $processInfo) {
            break
        }
        $parentId = [int]$processInfo.ParentProcessId

        if ($parentId -le 0 -or $chainIds.Contains($parentId)) {
            break
        }

        $chainIds.Add($parentId)
        try {
            $process = Get-Process -Id $parentId -ErrorAction Stop
            $chainNames.Add($process.ProcessName)
            if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
                return [pscustomobject]@{
                    WindowHandle = $process.MainWindowHandle.ToInt64()
                    ProcessId = $process.Id
                    ProcessName = $process.ProcessName
                    ExecutablePath = $process.Path
                }
            }
        } catch {
            # The process can exit while its parent chain is being inspected.
        }

        $currentId = $parentId
    }

    $candidateNames = @($chainNames | Where-Object { $knownNames -contains $_ })
    if ($candidateNames.Count -eq 0) {
        $candidateNames = $knownNames
    }

    $directory = ""
    if (-not [string]::IsNullOrWhiteSpace($Cwd)) {
        $directory = Split-Path -Leaf $Cwd.TrimEnd([char[]]"\/")
    }

    $allCandidates = foreach ($name in @($candidateNames | Select-Object -Unique)) {
        Get-Process -Name $name -ErrorAction SilentlyContinue
    }
    $candidates = @($allCandidates | Where-Object {
        $_.MainWindowHandle -ne [IntPtr]::Zero
    })
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        $matching = @($candidates | Where-Object {
            $_.MainWindowTitle.IndexOf(
                $directory,
                [StringComparison]::OrdinalIgnoreCase
            ) -ge 0
        })
        if ($matching.Count -gt 0) {
            $candidates = $matching
        }
    }

    $candidate = @($candidates | Select-Object -First 1)[0]
    if ($null -ne $candidate) {
        return [pscustomobject]@{
            WindowHandle = $candidate.MainWindowHandle.ToInt64()
            ProcessId = $candidate.Id
            ProcessName = $candidate.ProcessName
            ExecutablePath = $candidate.Path
        }
    }

    $fallback = @($allCandidates | Select-Object -First 1)[0]
    if ($null -ne $fallback) {
        return [pscustomobject]@{
            WindowHandle = 0
            ProcessId = $fallback.Id
            ProcessName = $fallback.ProcessName
            ExecutablePath = $fallback.Path
        }
    }

    return [pscustomobject]@{
        WindowHandle = 0
        ProcessId = 0
        ProcessName = ""
        ExecutablePath = ""
    }
}

function Start-NotificationServer {
    param([object]$Data)

    $json = $Data | ConvertTo-Json -Compress -Depth 5
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $executable = (Get-Process -Id $PID -ErrorAction Stop).Path
    $scriptPath = $PSCommandPath.Replace('"', '\"')

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $executable
    $startInfo.Arguments = '-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass ' +
        '-File "' + $scriptPath + '" -Serve -NotificationData ' + $encoded
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [Diagnostics.Process]::Start($startInfo)
    if ($null -ne $process) {
        $process.StandardInput.Close()
        $process.Dispose()
    }
}

function Initialize-WindowActivator {
    if ("AgentNotify.WindowActivator" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace AgentNotify
{
    public static class WindowActivator
    {
        [DllImport("user32.dll")]
        private static extern bool IsWindow(IntPtr window);

        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr window);

        [DllImport("user32.dll")]
        private static extern bool ShowWindowAsync(IntPtr window, int command);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr window);

        [DllImport("user32.dll")]
        private static extern bool BringWindowToTop(IntPtr window);

        public static bool Activate(long handle)
        {
            IntPtr window = new IntPtr(handle);
            if (window == IntPtr.Zero || !IsWindow(window))
                return false;

            if (IsIconic(window))
                ShowWindowAsync(window, 9);
            else
                ShowWindowAsync(window, 5);

            BringWindowToTop(window);
            return SetForegroundWindow(window);
        }
    }
}
'@
}

function Resolve-WindowHandle {
    param([object]$Data)

    $handle = [long]$Data.WindowHandle
    if ($handle -ne 0) {
        return $handle
    }

    $processId = [int]$Data.ProcessId
    if ($processId -gt 0) {
        try {
            $process = Get-Process -Id $processId -ErrorAction Stop
            if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
                return $process.MainWindowHandle.ToInt64()
            }
        } catch {
            # Continue with process-name and title matching.
        }
    }

    $processName = [string]$Data.ProcessName
    if ([string]::IsNullOrWhiteSpace($processName)) {
        return 0
    }

    $candidates = @(Get-Process -Name $processName -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })
    $directory = [string]$Data.Directory
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        $matching = @($candidates | Where-Object {
            $_.MainWindowTitle.IndexOf(
                $directory,
                [StringComparison]::OrdinalIgnoreCase
            ) -ge 0
        })
        if ($matching.Count -gt 0) {
            $candidates = $matching
        }
    }

    $candidate = @($candidates | Select-Object -First 1)[0]
    if ($null -eq $candidate) {
        return 0
    }
    return $candidate.MainWindowHandle.ToInt64()
}

function Activate-SourceWindow {
    param([object]$Data)

    $handle = Resolve-WindowHandle $Data
    if ($handle -ne 0) {
        if ([AgentNotify.WindowActivator]::Activate($handle)) {
            return
        }
    }

    $processName = [string]$Data.ProcessName
    $executablePath = [string]$Data.IconPath
    $editorNames = @("Code", "Code - Insiders", "VSCodium", "Cursor", "Windsurf")
    if ($editorNames -contains $processName -and
        -not [string]::IsNullOrWhiteSpace($executablePath) -and
        (Test-Path -LiteralPath $executablePath)) {
        try {
            Start-Process -FilePath $executablePath -ArgumentList "--reuse-window" `
                -WindowStyle Hidden
        } catch {
            # Window activation is best effort and must not break notification cleanup.
        }
    }
}

function Get-WindowsPowerShellAppId {
    try {
        $application = Get-StartApps -ErrorAction Stop | Where-Object {
            $_.Name -eq "Windows PowerShell" -and
            $_.AppID -like '*\WindowsPowerShell\v1.0\powershell.exe'
        } | Select-Object -First 1
        if ($null -ne $application -and
            -not [string]::IsNullOrWhiteSpace([string]$application.AppID)) {
            return [string]$application.AppID
        }
    } catch {
        # The StartApps cmdlet is unavailable on some older Windows builds.
    }

    return '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
}

function Get-SourceProtocolUri {
    param([object]$Data)

    if (-not (Test-Path -LiteralPath "Registry::HKEY_CLASSES_ROOT\agent-notify")) {
        return ""
    }

    $activationData = [ordered]@{
        WindowHandle = [long]$Data.WindowHandle
        ProcessId = [int]$Data.ProcessId
        ProcessName = [string]$Data.ProcessName
        IconPath = [string]$Data.IconPath
        Directory = [string]$Data.Directory
    }
    $json = $activationData | ConvertTo-Json -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $encoded = $encoded.TrimEnd('=').Replace('+', '-').Replace('/', '_')
    return "agent-notify://activate/$encoded"
}

function Get-ActivationData {
    param([string]$Uri)

    $prefix = "agent-notify://activate/"
    if (-not [string]::IsNullOrWhiteSpace($Uri) -and
        $Uri.StartsWith("codex-notify://activate/", [StringComparison]::OrdinalIgnoreCase)) {
        $prefix = "codex-notify://activate/"
    }
    if ([string]::IsNullOrWhiteSpace($Uri) -or
        -not $Uri.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Invalid Agent Notify activation URI."
    }

    $encoded = $Uri.Substring($prefix.Length).Replace('-', '+').Replace('_', '/')
    switch ($encoded.Length % 4) {
        2 { $encoded += "==" }
        3 { $encoded += "=" }
        1 { throw "Invalid Agent Notify activation payload." }
    }
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
    return $json | ConvertFrom-Json
}

function Show-WinRTNotification {
    param([object]$Data)

    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
        [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null

        $title = [Security.SecurityElement]::Escape([string]$Data.Title)
        $body = [Security.SecurityElement]::Escape([string]$Data.Body)
        $protocolUri = Get-SourceProtocolUri $Data
        $activation = ""
        if (-not [string]::IsNullOrWhiteSpace($protocolUri)) {
            $escapedUri = [Security.SecurityElement]::Escape($protocolUri)
            $activation = ' activationType="protocol" launch="' + $escapedUri + '"'
        }
        $logo = ""
        $provider = Get-EventValue $Data @("Provider")
        $iconUri = Get-NotificationIconUri -Provider $provider
        $iconName = if ($provider -eq "claude") { "Claude" } else { "Codex" }
        if (-not [string]::IsNullOrWhiteSpace($iconUri)) {
            $escapedIconUri = [Security.SecurityElement]::Escape($iconUri)
            $logo = '<image placement="appLogoOverride" src="' +
                $escapedIconUri + '" alt="' + $iconName + '"/>'
        }
        $xmlText = '<toast duration="long"' + $activation +
            '><visual><binding template="ToastGeneric">' +
            $logo + '<text>' + $title + '</text><text>' + $body +
            '</text></binding></visual></toast>'
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($xmlText)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)

        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(
            (Get-WindowsPowerShellAppId)
        )
        if (-not [string]::IsNullOrWhiteSpace($protocolUri)) {
            $notifier.Show($toast)
            return $true
        }

        $script:notificationClicked = $false
        $activatedHandler = {
            param($sender, $arguments)
            $script:notificationClicked = $true
        }
        $activatedToken = $toast.add_Activated($activatedHandler)
        try {
            $notifier.Show($toast)
            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            while ($stopwatch.Elapsed.TotalSeconds -lt $script:WatchSeconds) {
                [Windows.Forms.Application]::DoEvents()
                if ($script:notificationClicked) {
                    Activate-SourceWindow $Data
                    break
                }
                Start-Sleep -Milliseconds 50
            }
        } finally {
            $toast.remove_Activated($activatedToken)
        }
        return $true
    } catch {
        return $false
    }
}

function Show-NotifyIconNotification {
    param([object]$Data)

    $notifyIcon = New-Object Windows.Forms.NotifyIcon
    $ownedIcon = $null
    try {
        $iconPath = [string]$Data.IconPath
        if (-not [string]::IsNullOrWhiteSpace($iconPath) -and
            (Test-Path -LiteralPath $iconPath)) {
            try {
                $ownedIcon = [Drawing.Icon]::ExtractAssociatedIcon($iconPath)
            } catch {
                $ownedIcon = $null
            }
        }
        if ($null -ne $ownedIcon) {
            $notifyIcon.Icon = $ownedIcon
        } else {
            $notifyIcon.Icon = [Drawing.SystemIcons]::Information
        }

        $notifyIcon.Text = "Agent Notify"
        $notifyIcon.BalloonTipTitle = [string]$Data.Title
        $notifyIcon.BalloonTipText = [string]$Data.Body
        $notifyIcon.BalloonTipIcon = [Windows.Forms.ToolTipIcon]::None
        $notifyIcon.Visible = $true

        $clicked = $false
        $notifyIcon.add_BalloonTipClicked({
            $script:notificationClicked = $true
        })
        $script:notificationClicked = $false
        $notifyIcon.ShowBalloonTip(30000)

        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        while ($stopwatch.Elapsed.TotalSeconds -lt $script:WatchSeconds) {
            [Windows.Forms.Application]::DoEvents()
            if ($script:notificationClicked) {
                $clicked = $true
                break
            }
            Start-Sleep -Milliseconds 50
        }

        if ($clicked) {
            Activate-SourceWindow $Data
        }
    } finally {
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
        if ($null -ne $ownedIcon) {
            $ownedIcon.Dispose()
        }
    }
}

function Show-DesktopNotification {
    param([object]$Data)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Initialize-WindowActivator

    if ([string]::IsNullOrWhiteSpace((Get-SourceProtocolUri $Data)) -or
        -not (Show-WinRTNotification $Data)) {
        Show-NotifyIconNotification $Data
    }
}

if ($PSCmdlet.ParameterSetName -eq "Activate") {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Initialize-WindowActivator
        $activationData = Get-ActivationData $ActivationUri
        Activate-SourceWindow $activationData
        exit 0
    } catch {
        exit 1
    }
}

if ($Serve) {
    try {
        $json = [Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($NotificationData)
        )
        $data = $json | ConvertFrom-Json
        Show-DesktopNotification $data
        exit 0
    } catch {
        exit 1
    }
}

if ($Claude) {
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    $Payload = [Console]::In.ReadToEnd()
}
if ([string]::IsNullOrWhiteSpace($Payload)) {
    exit 2
}

try {
    $event = $Payload | ConvertFrom-Json
} catch {
    exit 0
}

$isClaude = (Get-EventValue $event @("hook_event_name")) -eq "Stop"
if ($Claude -and -not $isClaude) { exit 0 }
if (-not $isClaude -and (Get-EventValue $event @("type")) -ne "agent-turn-complete") {
    exit 0
}

$answer = if ($isClaude) {
    Get-EventValue $event @("last_assistant_message")
} else {
    Get-EventValue $event @("last-assistant-message")
}
if ([string]::IsNullOrWhiteSpace($answer)) {
    if ($isClaude) { $answer = "Claude Code completed a response." } else { exit 0 }
}

$threadId = Get-EventValue $event @("thread-id")
$cwd = Get-EventValue $event @("cwd")
$sessionName = if ($isClaude) { "Claude Code" } else { Get-SessionName $event $threadId }
$question = if ($isClaude) { "" } else {
    Convert-ToCompactText (Get-LastInputMessage $event) $script:QuestionPreviewLimit
}
$answerPreview = Convert-ToCompactText $answer $script:AnswerPreviewLimit

$directory = "Unknown folder"
if (-not [string]::IsNullOrWhiteSpace($cwd)) {
    $directory = Split-Path -Leaf $cwd.TrimEnd([char[]]"\/")
}
$directory = Convert-ToCompactText $directory $script:DirectoryPreviewLimit
$title = Convert-ToCompactText "[$sessionName] @ $directory" `
    $script:TitlePreviewLimit
$bodyParts = @($question, $answerPreview) | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_)
}
$body = $bodyParts -join [Environment]::NewLine

$source = Get-SourceContext $cwd
$data = [ordered]@{
    Title = $title
    Body = $body
    Provider = if ($isClaude) { "claude" } else { "codex" }
    WindowHandle = $source.WindowHandle
    ProcessId = $source.ProcessId
    ProcessName = $source.ProcessName
    IconPath = $source.ExecutablePath
    Directory = $directory
}

$notificationPayload = [pscustomobject]$data
try {
    $protocolUri = Get-SourceProtocolUri $notificationPayload
    if (-not [string]::IsNullOrWhiteSpace($protocolUri) -and
        (Show-WinRTNotification $notificationPayload)) {
        exit 0
    }
    Start-NotificationServer $data
} catch {
    Show-DesktopNotification $notificationPayload
}

exit 0
