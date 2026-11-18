<#
.SYNOPSIS
    Rollback Windows Defender Firewall Kill-Switch rules created by apply_killswitch.ps1.
#>
param(
    [string]$GroupName = "ProxyKillSwitch"
)

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "Please run this script as Administrator."
}

$rules = Get-NetFirewallRule -Group $GroupName -ErrorAction SilentlyContinue
if ($rules) {
    $count = ($rules | Measure-Object).Count
    $rules | Remove-NetFirewallRule
    Write-Host "Removed $count '$GroupName' firewall rules."
} else {
    Write-Host "No '$GroupName' firewall rules found."
}
