[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "AgentNotify"),
    [string]$SourceUrl = "",
    [ValidateSet("codex", "claude", "all")]
    [string]$Target = "codex",
    [switch]$NoConfig,
    [switch]$Uninstall
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$programName = "agent-notify.ps1"
$defaultSourceUrl = "https://raw.githubusercontent.com/Huffer342-WSH/" +
    "agent-notify/refs/heads/main/agent-notify.ps1"
$installPath = Join-Path $InstallDir $programName
$legacyPath = Join-Path $InstallDir "codex-notify.ps1"
$legacyDefaultPath = Join-Path (Join-Path $env:LOCALAPPDATA "CodexNotify") "codex-notify.ps1"
$ownedPaths = @($installPath, $legacyPath, $legacyDefaultPath) | Select-Object -Unique
$launcherName = "agent-notify-activate.vbs"
$launcherPath = Join-Path $InstallDir $launcherName
$codexDir = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    Join-Path $HOME ".codex"
} else {
    $env:CODEX_HOME
}
$configPath = Join-Path $codexDir "config.toml"
$backupPath = $configPath + ".agent-notify.bak"
$protocolPath = "HKCU:\Software\Classes\agent-notify"
$claudeDir = if ([string]::IsNullOrWhiteSpace($env:CLAUDE_CONFIG_DIR)) {
    Join-Path $HOME ".claude"
} else { $env:CLAUDE_CONFIG_DIR }
$claudeConfigPath = Join-Path $claudeDir "settings.json"

function ConvertTo-JsonString {
    param([string]$Value)

    return ConvertTo-Json -InputObject $Value -Compress
}

function Get-NotifyConfiguration {
    param([string]$ScriptPath)

    $command = @(
        "powershell.exe",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $ScriptPath
    )
    $items = foreach ($item in $command) {
        ConvertTo-JsonString $item
    }
    $jsonCommand = ConvertTo-Json -InputObject $command -Compress

    return [pscustomobject]@{
        Direct = "notify = [" + ($items -join ", ") + "]"
        Nested = ConvertTo-JsonString $jsonCommand
    }
}

function Set-Utf8Text {
    param(
        [string]$Path,
        [string]$Text
    )

    $encoding = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Write-NotificationDurationWarning {
    $accessibilityPath = "HKCU:\Control Panel\Accessibility"
    $settings = Get-ItemProperty -LiteralPath $accessibilityPath `
        -Name "MessageDuration" -ErrorAction SilentlyContinue
    $duration = if ($null -eq $settings) { $null } else { $settings.MessageDuration }
    if ($null -ne $duration -and [int]$duration -lt 30) {
        Write-Warning (
            "Windows currently dismisses notification banners after $duration seconds. " +
            "To keep Agent Notify banners visible longer, open Settings > Accessibility > " +
            "Visual effects > Dismiss notifications after this amount of time. " +
            "This global setting is not changed by the installer."
        )
    }
}

function Get-ActivationProtocolCommand {
    return '"wscript.exe" "' + $launcherPath.Replace('"', '\"') + '" "%1"'
}

function Install-ActivationLauncher {
    $content = @'
Option Explicit

Dim fileSystem, shell, scriptPath, activationUri, command
Set fileSystem = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptPath = fileSystem.BuildPath(fileSystem.GetParentFolderName(WScript.ScriptFullName), "agent-notify.ps1")
activationUri = WScript.Arguments(0)
command = "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & scriptPath & """ -ActivationUri """ & activationUri & """"

shell.Run command, 0, False
'@
    Set-Utf8Text $launcherPath ($content + [Environment]::NewLine)
}

function Update-ActivationProtocol {
    param([ValidateSet("Install", "Uninstall")][string]$Mode)

    $commandPath = Join-Path $protocolPath "shell\open\command"
    $expectedCommand = Get-ActivationProtocolCommand
    if ($Mode -eq "Uninstall") {
        if (-not (Test-Path -LiteralPath $commandPath)) {
            return $false
        }
        $currentCommand = (Get-Item -LiteralPath $commandPath).GetValue("")
        if ($currentCommand -ne $expectedCommand) {
            return $false
        }
        Remove-Item -LiteralPath $protocolPath -Recurse -Force
        $oldProtocolPath = "HKCU:\Software\Classes\codex-notify"
        $oldCommandPath = Join-Path $oldProtocolPath "shell\open\command"
        if ((Test-Path -LiteralPath $oldCommandPath) -and
            (Get-Item -LiteralPath $oldCommandPath).GetValue("") -eq $expectedCommand) {
            Remove-Item -LiteralPath $oldProtocolPath -Recurse -Force
        }
        return $true
    }

    if (Test-Path -LiteralPath $protocolPath) {
        $description = (Get-Item -LiteralPath $protocolPath).GetValue("")
        if ($description -and $description -ne "URL:Agent Notify") {
            throw "The agent-notify URL protocol is already owned by another application."
        }
    }

    [void](New-Item -Path $commandPath -Force)
    Set-Item -LiteralPath $protocolPath -Value "URL:Agent Notify"
    New-ItemProperty -LiteralPath $protocolPath -Name "URL Protocol" -Value "" `
        -PropertyType String -Force > $null
    Set-Item -LiteralPath $commandPath -Value $expectedCommand
    return $true
}

function Update-CodexConfig {
    param([ValidateSet("Install", "Uninstall")][string]$Mode)

    [void](New-Item -ItemType Directory -Path $codexDir -Force)
    $text = if (Test-Path -LiteralPath $configPath) {
        [IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8)
    } else {
        ""
    }

    if (Test-Path -LiteralPath $configPath) {
        Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
    }

    $configuration = Get-NotifyConfiguration $installPath
    $ownedConfigurations = @($ownedPaths | ForEach-Object { Get-NotifyConfiguration $_ })
    $firstTable = [regex]::Match($text, '(?m)^\s*\[')
    $topLength = if ($firstTable.Success) { $firstTable.Index } else { $text.Length }
    $top = $text.Substring(0, $topLength)
    $rest = $text.Substring($topLength)
    $notifyMatch = [regex]::Match($top, '(?m)^notify\s*=.*(?:\r?\n|$)')

    if ($notifyMatch.Success) {
        $lineWithEnding = $notifyMatch.Value
        $ending = if ($lineWithEnding.EndsWith("`r`n")) {
            "`r`n"
        } elseif ($lineWithEnding.EndsWith("`n")) {
            "`n"
        } else {
            ""
        }
        $line = $lineWithEnding.TrimEnd("`r", "`n")
        if (-not $line.TrimEnd().EndsWith("]")) {
            throw "Multi-line top-level notify configuration is not supported."
        }

        $nestedPattern = `
            '(?<remove>\s*,\s*"--previous-notify"\s*,\s*(?<value>"(?:\\.|[^"\\])*"))'
        $nestedMatch = [regex]::Match($line, $nestedPattern)

        if ($Mode -eq "Install") {
            if ($nestedMatch.Success) {
                $value = $nestedMatch.Groups["value"]
                $line = $line.Substring(0, $value.Index) +
                    $configuration.Nested +
                    $line.Substring($value.Index + $value.Length)
            } else {
                $line = $configuration.Direct
            }
        } else {
            if ($line -cin @($ownedConfigurations | ForEach-Object { $_.Direct })) {
                $line = ""
            } elseif ($nestedMatch.Success -and
                $nestedMatch.Groups["value"].Value -cin @($ownedConfigurations | ForEach-Object { $_.Nested })) {
                $remove = $nestedMatch.Groups["remove"]
                $line = $line.Remove($remove.Index, $remove.Length)
            } else {
                return $false
            }
        }

        $replacement = if ([string]::IsNullOrEmpty($line)) { "" } else { $line + $ending }
        $top = $top.Substring(0, $notifyMatch.Index) + $replacement +
            $top.Substring($notifyMatch.Index + $notifyMatch.Length)
    } elseif ($Mode -eq "Install") {
        $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
        if ($top.Length -gt 0 -and -not $top.EndsWith($newline)) {
            $top += $newline
        }
        if ($top.Length -gt 0 -and -not [string]::IsNullOrWhiteSpace($top)) {
            $top += $newline
        }
        $top += $configuration.Direct + $newline
        if ($rest.Length -gt 0) {
            $top += $newline
        }
    } else {
        return $false
    }

    Set-Utf8Text $configPath ($top + $rest)
    return $true
}

function Get-ClaudeCommand {
    param([string]$ScriptPath)
    $invocation = "& '" + $ScriptPath.Replace("'", "''") + "' -Claude"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($invocation))
    return "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded"
}

function Update-ClaudeConfig {
    param([ValidateSet("Install", "Uninstall")][string]$Mode)

    if ($Mode -eq "Uninstall" -and -not (Test-Path -LiteralPath $claudeConfigPath)) {
        return
    }
    # EncodedCommand avoids path interpolation by either Bash or PowerShell.
    $commands = @($ownedPaths | ForEach-Object { Get-ClaudeCommand $_ })
    $command = Get-ClaudeCommand $installPath
    $settings = if (Test-Path -LiteralPath $claudeConfigPath) {
        [IO.File]::ReadAllText($claudeConfigPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    } else { [pscustomobject]@{} }
    if ($null -eq $settings -or $settings -isnot [pscustomobject]) {
        throw "Claude settings must be a JSON object."
    }
    if (-not $settings.PSObject.Properties["hooks"]) {
        $settings | Add-Member NoteProperty hooks ([pscustomobject]@{})
    }
    $hooks = $settings.hooks
    if ($null -eq $hooks -or $hooks -isnot [pscustomobject]) {
        throw "Claude hooks must be a JSON object."
    }
    $entries = if ($hooks.PSObject.Properties["Stop"]) { @($hooks.Stop) } else { @() }
    $updated = @(
        foreach ($entry in $entries) {
            $handlers = @($entry.hooks)
            $kept = @($handlers | Where-Object {
                -not ($_.PSObject.Properties["type"] -and $_.type -eq "command" -and
                    $_.PSObject.Properties["command"] -and $_.command -cin $commands)
            })
            if ($kept.Count -eq $handlers.Count) { $entry }
            elseif ($kept.Count -gt 0) { $entry.hooks = $kept; $entry }
        }
    )
    if ($Mode -eq "Install") {
        $updated += [pscustomobject]@{ hooks = @(
            [pscustomobject]@{ type = "command"; command = $command; timeout = 10 }
        ) }
    }
    if ($updated.Count -gt 0) {
        $hooks | Add-Member NoteProperty Stop $updated -Force
    } else { $hooks.PSObject.Properties.Remove("Stop") }
    if (@($hooks.PSObject.Properties).Count -eq 0) {
        $settings.PSObject.Properties.Remove("hooks")
    }
    $json = ConvertTo-Json -InputObject $settings -Depth 100
    [void](New-Item -ItemType Directory -Path $claudeDir -Force)
    if (Test-Path -LiteralPath $claudeConfigPath) {
        Copy-Item -LiteralPath $claudeConfigPath -Destination ($claudeConfigPath + ".agent-notify.bak") -Force
    }
    Set-Utf8Text $claudeConfigPath ($json + [Environment]::NewLine)
}

function Update-SelectedConfig {
    param([string]$Mode)
    if ($Target -in @("codex", "all")) { [void](Update-CodexConfig $Mode) }
    if ($Target -in @("claude", "all")) { Update-ClaudeConfig $Mode }
}

function Test-SharedConfiguration {
    param([string[]]$Paths = @($installPath, $legacyPath))
    # Only files installed in this directory depend on this installation.
    foreach ($path in $Paths) {
        if (Test-Path -LiteralPath $configPath) {
            $text = [IO.File]::ReadAllText($configPath)
            $escaped = ConvertTo-JsonString $path
            if ($text.Contains($escaped)) { return $true }
            $nested = (Get-NotifyConfiguration $path).Nested
            if ($text.Contains($nested)) { return $true }
        }
        if (Test-Path -LiteralPath $claudeConfigPath) {
            $text = [IO.File]::ReadAllText($claudeConfigPath)
            if ($text.Contains((Get-ClaudeCommand $path))) { return $true }
            if ($text.Contains($path) -or $text.Contains((ConvertTo-JsonString $path).Trim('"'))) { return $true }
        }
    }
    return $false
}

function Remove-KnownLegacyScripts {
    if ($NoConfig) { return }
    # SHA256 of historical UTF-8 content, ignoring BOM and CRLF checkout differences.
    $knownHashes = @(
        "fb37396324e5c35339fefddd8d24400200e6c4c05a70b05727a258c43230472f", # 50dab9e Python wrapper
        "8c4e60dd9e183d8ef0dbbb1e000df9eaca77a7d5ffe28286cb11fe837d3a7159", # 50dab9e PowerShell wrapper
        "6d4212e21afa2eb1d7027c6b7904d0e345a2990c77f644cbd6b88b8571a37f30", # 50dab9e installed PowerShell copy
        "9c72604a4ab848c74b7a6dcaf22cf6c751ce2ffd2c5d5564c8468ef8e0c58258", # eb8c321 Python
        "0a837c7e6ea9aa39afb74e971e73def6beeee81ba21d5dece7d94cf33a7e71cb", # eb8c321 PowerShell
        "95408f180f392470b34a052a79dd2bd9bf1608e499d10654cc5ed1ea46e2ed96", # c63aee5 PowerShell
        "f39af893ab4d2129e184bdf4c1269a736dee25c74e8f7494857763875c9a28e1"  # d186ac4 Python
    )
    $directories = @($InstallDir, (Split-Path -Parent $legacyDefaultPath)) | Select-Object -Unique
    foreach ($directory in $directories) {
        foreach ($name in @("codex-notify.ps1", "codex-notify.py")) {
            $path = Join-Path $directory $name
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $item = Get-Item -LiteralPath $path
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $content = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8).Replace("`r`n", "`n")
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($content))).Replace("-", "").ToLowerInvariant()
            } finally { $sha.Dispose() }
            if ($hash -notin $knownHashes -or (Test-SharedConfiguration -Paths @($path))) {
                Write-Warning "Retained modified, unknown, or still-referenced legacy script: $path"
                continue
            }
            # Existing notification clicks must reach the new script before the old one is removed.
            if ($name -eq "codex-notify.ps1") {
                $oldCommandPath = "HKCU:\Software\Classes\codex-notify\shell\open\command"
                if (Test-Path -LiteralPath $oldCommandPath) {
                    $oldLauncher = Join-Path $directory "codex-notify-activate.vbs"
                    $expected = '"wscript.exe" "' + $oldLauncher.Replace('"', '\"') + '" "%1"'
                    $current = (Get-Item -LiteralPath $oldCommandPath).GetValue("")
                    if ($current -eq $expected) {
                        Set-Item -LiteralPath $oldCommandPath -Value (Get-ActivationProtocolCommand)
                    } elseif ($current -ne (Get-ActivationProtocolCommand)) {
                        Write-Warning "Retained legacy script because its activation protocol is unrecognized: $path"
                        continue
                    }
                }
            }
            Remove-Item -LiteralPath $path -Force
            Write-Host "Removed known legacy script: $path"
        }
    }
}

if ($Uninstall) {
    $protocolChanged = $false
    if (-not $NoConfig) {
        Update-SelectedConfig "Uninstall"
        if (Test-SharedConfiguration) {
            Write-Host "Removed selected configuration; retained shared executable and activation protocol."
            exit 0
        }
        $protocolChanged = Update-ActivationProtocol "Uninstall"
    }
    if (Test-Path -LiteralPath $installPath) {
        Remove-Item -LiteralPath $installPath -Force
    }
    if (Test-Path -LiteralPath $legacyPath) {
        Remove-Item -LiteralPath $legacyPath -Force
    }
    if (Test-Path -LiteralPath $launcherPath) {
        Remove-Item -LiteralPath $launcherPath -Force
    }

    Write-Host "Removed $programName from $installPath"
    if ($protocolChanged) {
        Write-Host "Removed the agent-notify activation protocol."
    }
    Write-Host "Restart the selected clients to apply the change."
    exit 0
}

[void](New-Item -ItemType Directory -Path $InstallDir -Force)
$temporaryPath = $installPath + ".tmp." + $PID
try {
    if (-not [string]::IsNullOrWhiteSpace($SourceUrl)) {
        if ($SourceUrl -notmatch '^https?://') {
            throw "SourceUrl must use http:// or https://."
        }
        Invoke-WebRequest -Uri $SourceUrl -OutFile $temporaryPath -UseBasicParsing
    } else {
        $localSource = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            ""
        } else {
            Join-Path $PSScriptRoot $programName
        }
        if (-not [string]::IsNullOrWhiteSpace($localSource) -and
            (Test-Path -LiteralPath $localSource)) {
            Copy-Item -LiteralPath $localSource -Destination $temporaryPath -Force
        } else {
            Invoke-WebRequest -Uri $defaultSourceUrl -OutFile $temporaryPath `
                -UseBasicParsing
        }
    }

    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $temporaryPath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        $messages = ($parseErrors | ForEach-Object { $_.Message }) -join "; "
        throw "Downloaded notification script is invalid: $messages"
    }

    Move-Item -LiteralPath $temporaryPath -Destination $installPath -Force
    Install-ActivationLauncher
} finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

if (-not $NoConfig) {
    Update-SelectedConfig "Install"
    [void](Update-ActivationProtocol "Install")
    Remove-KnownLegacyScripts
}

Write-Host "Installed $programName to $installPath"
if (-not $NoConfig) {
    Write-Host "Configured $Target notifications (Codex: $configPath; Claude: $claudeConfigPath)"
    Write-Host "Registered the agent-notify activation protocol for notification clicks."
    if (Test-Path -LiteralPath $backupPath) {
        Write-Host "Backup: $backupPath"
    }
}
Write-NotificationDurationWarning
Write-Host "Restart the selected clients to apply the change."
