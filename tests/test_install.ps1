# Configuration and migration tests. No real registry writes or desktop notifications.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$temp = Join-Path ([IO.Path]::GetTempPath()) ("agent-notify-test-" + [guid]::NewGuid())
$oldLocalAppData = $env:LOCALAPPDATA
$oldCodexHome = $env:CODEX_HOME
$oldClaudeConfig = $env:CLAUDE_CONFIG_DIR
try {
    $env:LOCALAPPDATA = Join-Path $temp "local"
    $env:CODEX_HOME = Join-Path $temp "codex"
    $env:CLAUDE_CONFIG_DIR = Join-Path $temp "claude"
    [void](New-Item -ItemType Directory -Path $temp -Force)
    $source = [IO.File]::ReadAllText((Join-Path $root "install.ps1"))
    $boundary = $source.IndexOf('if ($Uninstall) {', [StringComparison]::Ordinal)
    Assert-True ($boundary -gt 0) "Installer function boundary not found"
    # Load the installer's declarations without running installation or registry code.
    . ([scriptblock]::Create($source.Substring(0, $boundary))) `
        -InstallDir (Join-Path $temp "Agent Notify's tools") -Target all

    [void](New-Item -ItemType Directory -Path $codexDir, $claudeDir -Force)
    $legacyCommand = Get-ClaudeCommand $legacyDefaultPath
    $original = [pscustomobject]@{
        env = [pscustomobject]@{ EXAMPLE = "keep" }
        hooks = [pscustomobject]@{ Stop = @([pscustomobject]@{ hooks = @(
            [pscustomobject]@{ type = "command"; command = $legacyCommand },
            [pscustomobject]@{ type = "command"; command = "echo keep" }
        ) }) }
    }
    Set-Utf8Text $claudeConfigPath (ConvertTo-Json -InputObject $original -Depth 20)
    Set-Utf8Text $configPath ((Get-NotifyConfiguration $legacyDefaultPath).Direct + "`nmodel = `"keep`"`n")
    Update-SelectedConfig "Install"
    Assert-True (([IO.File]::ReadAllText($configPath)).Contains((Get-NotifyConfiguration $installPath).Direct)) "Codex old path was not migrated"
    Assert-True (([IO.File]::ReadAllText($configPath)).Contains('model = "keep"')) "Codex model was lost"
    Assert-True (Test-Path -LiteralPath $backupPath) "Codex backup missing"
    Assert-True (Test-Path -LiteralPath ($claudeConfigPath + ".agent-notify.bak")) "Claude backup missing"
    Update-ClaudeConfig "Install"
    $data = [IO.File]::ReadAllText($claudeConfigPath) | ConvertFrom-Json
    $handlers = @($data.hooks.Stop | ForEach-Object { $_.hooks })
    Assert-True ($handlers.Count -eq 2) "Duplicate Claude notification hook"
    Assert-True ($data.env.EXAMPLE -eq "keep") "Unrelated Claude setting lost"
    Assert-True (@($handlers | Where-Object { $_.command -ceq $legacyCommand }).Count -eq 0) "Old Claude command retained"
    Assert-True (@($handlers | Where-Object { $_.command -ceq (Get-ClaudeCommand $installPath) }).Count -eq 1) "New Claude command missing"
    Assert-True (Test-SharedConfiguration) "Shared configuration not detected"

    [void](Update-CodexConfig "Uninstall")
    Assert-True (Test-SharedConfiguration) "Claude reference must retain installation"
    Update-ClaudeConfig "Uninstall"
    Assert-True (-not (Test-SharedConfiguration)) "Removed hooks still reported as references"
    $data = [IO.File]::ReadAllText($claudeConfigPath) | ConvertFrom-Json
    Assert-True ($data.hooks.Stop[0].hooks[0].command -eq "echo keep") "Other Claude hook removed"

    # Preserve an outer callback while migrating and uninstalling --previous-notify.
    $legacyConfig = Get-NotifyConfiguration $legacyDefaultPath
    Set-Utf8Text $configPath ('notify = ["outer", "--previous-notify", ' + $legacyConfig.Nested + "]`n")
    [void](Update-CodexConfig "Install")
    Assert-True (([IO.File]::ReadAllText($configPath)).Contains((Get-NotifyConfiguration $installPath).Nested)) "Nested callback not migrated"
    Assert-True (Test-SharedConfiguration) "Nested callback reference not detected"
    [void](Update-CodexConfig "Uninstall")
    Assert-True (([IO.File]::ReadAllText($configPath)).Trim() -eq 'notify = ["outer"]') "Outer callback was not preserved"

    # Fake only the legacy registry entry; filesystem operations remain real.
    $script:oldProtocolCommand = $null
    function Test-Path {
        param([string]$LiteralPath, [string]$PathType)
        if ($LiteralPath.StartsWith("HKCU:")) { return $null -ne $script:oldProtocolCommand }
        Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
    }
    function Get-Item {
        param([string]$LiteralPath)
        if ($LiteralPath.StartsWith("HKCU:")) {
            $item = [pscustomobject]@{}
            $item | Add-Member ScriptMethod GetValue { param($name) $script:oldProtocolCommand }
            return $item
        }
        Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
    }
    function Set-Item {
        param([string]$LiteralPath, [string]$Value)
        Assert-True ($LiteralPath -eq "HKCU:\Software\Classes\codex-notify\shell\open\command") "Unexpected registry write"
        $script:oldProtocolCommand = $Value
    }
    [void](New-Item -ItemType Directory -Path $InstallDir, (Split-Path -Parent $legacyDefaultPath) -Force)
    $fixtureRoot = Join-Path $PSScriptRoot "fixtures/legacy"
    $pythonPath = Join-Path $InstallDir "codex-notify.py"
    $pythonText = [IO.File]::ReadAllText((Join-Path $fixtureRoot "codex-notify.py")).Replace("`r`n", "`n")
    $powershellText = [IO.File]::ReadAllText((Join-Path $fixtureRoot "codex-notify.ps1"))
    Set-Utf8Text $legacyDefaultPath $powershellText
    # Git checkouts and Windows editors can change line endings and add a BOM.
    [IO.File]::WriteAllText($pythonPath, $pythonText.Replace("`n", "`r`n"), (New-Object Text.UTF8Encoding($true)))
    Set-Utf8Text $legacyPath ($powershellText + "`n# user change")
    $script:oldProtocolCommand = '"wscript.exe" "' + (Join-Path (Split-Path -Parent $legacyDefaultPath) "codex-notify-activate.vbs") + '" "%1"'
    $NoConfig = $true
    Remove-KnownLegacyScripts
    Assert-True (Test-Path -LiteralPath $pythonPath) "NoConfig removed an old script"
    $NoConfig = $false
    Set-Utf8Text $configPath ("notify = [`"python`", " + (ConvertTo-JsonString $pythonPath) + "]`n")
    Remove-KnownLegacyScripts
    Assert-True (Test-Path -LiteralPath $pythonPath) "Referenced Python script removed"
    Assert-True (Test-Path -LiteralPath $legacyPath) "Modified script removed"
    Assert-True (-not (Test-Path -LiteralPath $legacyDefaultPath)) "Known PowerShell script retained"
    Assert-True ($script:oldProtocolCommand -eq (Get-ActivationProtocolCommand)) "Old notification protocol not migrated"
    Update-SelectedConfig "Install"
    Remove-KnownLegacyScripts
    Assert-True (-not (Test-Path -LiteralPath $pythonPath)) "Known Python script retained after migration"
    Set-Utf8Text $legacyDefaultPath $powershellText
    $script:oldProtocolCommand = '"custom-launcher.exe"'
    Remove-KnownLegacyScripts
    Assert-True (Test-Path -LiteralPath $legacyDefaultPath) "Script with unknown protocol removed"
    $script:oldProtocolCommand = $null
    Set-Utf8Text $claudeConfigPath (ConvertTo-Json -Depth 10 -InputObject ([pscustomobject]@{
        hooks = @{ Stop = @(@{ hooks = @(@{ type = "command"; command = (Get-ClaudeCommand $legacyDefaultPath) }) }) }
    }))
    Remove-KnownLegacyScripts
    Assert-True (Test-Path -LiteralPath $legacyDefaultPath) "Other client's reference was ignored"
    Update-ClaudeConfig "Install"
    Remove-KnownLegacyScripts
    Assert-True (-not (Test-Path -LiteralPath $legacyDefaultPath)) "Migrated script retained"

    # Run the real installation body with network and Windows-only side effects replaced.
    function Invoke-WebRequest {
        param($Uri, $OutFile, [switch]$UseBasicParsing)
        Copy-Item -LiteralPath (Join-Path $root "agent-notify.ps1") -Destination $OutFile
    }
    function Update-ActivationProtocol {
        param($Mode)
        Assert-True (Test-Path -LiteralPath $installPath) "Protocol configured before script installation"
        Assert-True (Test-Path -LiteralPath $launcherPath) "Activation launcher missing"
        Assert-True (([IO.File]::ReadAllText($configPath)).Contains((Get-NotifyConfiguration $installPath).Direct)) "Protocol configured before config migration"
        return $true
    }
    function Write-NotificationDurationWarning {}
    Set-Utf8Text $legacyPath $powershellText
    Set-Utf8Text $pythonPath $pythonText
    Set-Utf8Text $configPath ((Get-NotifyConfiguration $legacyPath).Direct + "`n")
    . ([scriptblock]::Create($source.Substring($boundary)))
    Assert-True (Test-Path -LiteralPath $installPath) "New script missing after installation"
    Assert-True (-not (Test-Path -LiteralPath $legacyPath)) "Installer recreated old PowerShell copy"
    Assert-True (-not (Test-Path -LiteralPath $pythonPath)) "Installer retained old Python copy"
    Assert-True (([IO.File]::ReadAllText($launcherPath)).Contains('"agent-notify.ps1"')) "Launcher points at old script"
    Remove-Item Function:\Invoke-WebRequest, Function:\Update-ActivationProtocol, Function:\Write-NotificationDurationWarning
    Remove-Item Function:\Test-Path, Function:\Get-Item, Function:\Set-Item

    # A malformed JSON file must remain untouched.
    Set-Utf8Text $claudeConfigPath "{broken"
    $failed = $false
    try { Update-ClaudeConfig "Install" } catch { $failed = $true }
    Assert-True $failed "Malformed Claude JSON accepted"
    Assert-True (([IO.File]::ReadAllText($claudeConfigPath)) -eq "{broken") "Malformed JSON overwritten"
    # Both URI schemes remain decodable without touching Windows APIs.
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $root "agent-notify.ps1"), [ref]$tokens, [ref]$parseErrors
    )
    Assert-True ($parseErrors.Count -eq 0) "Notification script has syntax errors"
    $definition = $ast.Find({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Get-ActivationData"
    }, $false)
    . ([scriptblock]::Create($definition.Extent.Text))
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"Directory":"example"}'))
    $encoded = $encoded.TrimEnd('=').Replace('+', '-').Replace('/', '_')
    foreach ($scheme in @("agent-notify", "codex-notify")) {
        $activation = Get-ActivationData ($scheme + "://activate/" + $encoded)
        Assert-True ($activation.Directory -eq "example") "Activation URI compatibility failed"
    }
    Write-Host "PowerShell configuration and activation URI tests passed."
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:CODEX_HOME = $oldCodexHome
    $env:CLAUDE_CONFIG_DIR = $oldClaudeConfig
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
