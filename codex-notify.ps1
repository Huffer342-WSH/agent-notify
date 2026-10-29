# Compatibility entry point. Use agent-notify.ps1 for new integrations.
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

& (Join-Path $PSScriptRoot "agent-notify.ps1") @PSBoundParameters
exit $LASTEXITCODE
