<#
.SYNOPSIS
    Windows Kernel-level Firewall Kill-Switch for Desktop AI Apps (Claude, Antigravity, etc.).
    Blocks ALL non-loopback outbound traffic (IPv4/IPv6, TCP/UDP/QUIC/STUN/Direct-DNS),
    allowing ONLY 127.0.0.0/8 and ::1 (local IPC + local proxy such as 127.0.0.1:10808).
.PARAMETER GroupName
    Windows Defender Firewall rule group name. Default: ProxyKillSwitch.
.PARAMETER ExtraPrograms
    Optional array of additional .exe full paths to lock to loopback-only.
.PARAMETER DenyNonPackagedLocation
    Also set HKCU NonPackaged Location consent to Deny (blocks desktop apps from reading Wi-Fi geolocation).
#>
param(
    [string]$GroupName = "ProxyKillSwitch",
    [string[]]$ExtraPrograms = @(),
    [switch]$DenyNonPackagedLocation
)

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "Please run this script as Administrator."
}

$nonLoopback = @(
    "0.0.0.0-126.255.255.255",
    "128.0.0.0-255.255.255.255",
    "::",
    "::2-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
)

Write-Host "[1/4] Removing existing '$GroupName' firewall rules..."
Get-NetFirewallRule -Group $GroupName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue

$created = @()

# 1. Discover Claude MSIX / AppContainer Package SIDs dynamically
$pkgSids = New-Object System.Collections.Generic.HashSet[string]
Get-NetFirewallRule -DisplayName "Claude" -ErrorAction SilentlyContinue | ForEach-Object {
    $af = $_ | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
    if ($af -and $af.Package) {
        [void]$pkgSids.Add($af.Package)
    }
}

$idx = 0
foreach ($sid in $pkgSids) {
    $idx++
    $name = "${GroupName}_Claude_Package_$idx"
    New-NetFirewallRule `
        -DisplayName $name `
        -Group $GroupName `
        -Direction Outbound `
        -Action Block `
        -Package $sid `
        -RemoteAddress $nonLoopback `
        -Protocol Any `
        -Profile Any `
        -Enabled True `
        -Description "Kill-Switch: Force AppContainer package to loopback only" | Out-Null
    $created += [PSCustomObject]@{ Rule = $name; Target = "Package:$sid" }
}

# 2. Discover Claude & Antigravity executables dynamically
$targets = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

$winApps = Join-Path $env:ProgramFiles "WindowsApps"
if (Test-Path $winApps) {
    Get-ChildItem $winApps -Directory -Filter "Claude_*" -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem $_.FullName -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            [void]$targets.Add($_.FullName)
        }
    }
}

$claudeDataDir = Join-Path $env:LOCALAPPDATA "Claude-Data"
if (Test-Path $claudeDataDir) {
    Get-ChildItem $claudeDataDir -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$targets.Add($_.FullName)
    }
}

Get-Command claude -All -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Source -and $_.Source.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path $_.Source)) {
        [void]$targets.Add($_.Source)
    }
}

$agyDir = Join-Path $env:LOCALAPPDATA "Programs\Antigravity"
if (Test-Path $agyDir) {
    Get-ChildItem $agyDir -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -notmatch "^Uninstall") {
            [void]$targets.Add($_.FullName)
        }
    }
}

$geminiDir = Join-Path $env:USERPROFILE ".gemini"
if (Test-Path $geminiDir) {
    Get-ChildItem $geminiDir -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$targets.Add($_.FullName)
    }
}

foreach ($p in $ExtraPrograms) {
    if ($p -and (Test-Path $p)) {
        [void]$targets.Add((Resolve-Path $p).Path)
    }
}

$sha = [Security.Cryptography.SHA256]::Create()
try {
    foreach ($exe in ($targets | Sort-Object)) {
        $leaf = [IO.Path]::GetFileNameWithoutExtension($exe)
        $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($exe))).Replace("-", "").Substring(0, 6)
        $name = "${GroupName}_${leaf}_$hash"
        New-NetFirewallRule `
            -DisplayName $name `
            -Group $GroupName `
            -Direction Outbound `
            -Action Block `
            -Program $exe `
            -RemoteAddress $nonLoopback `
            -Protocol Any `
            -Profile Any `
            -Enabled True `
            -Description "Kill-Switch: Force binary to loopback only" | Out-Null
        $created += [PSCustomObject]@{ Rule = $name; Target = $exe }
    }
} finally {
    $sha.Dispose()
}

if ($DenyNonPackagedLocation) {
    $locKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\NonPackaged"
    if (Test-Path $locKey) {
        Set-ItemProperty -Path $locKey -Name "Value" -Value "Deny"
        Write-Host "[opt] Set NonPackaged Windows Location consent to Deny."
    }
}

Write-Host "[2/4] Applied $($created.Count) Kill-Switch firewall rules:"
$created | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "[3/4] Verifying all '$GroupName' rules in Windows Defender Firewall..."
$verified = Get-NetFirewallRule -Group $GroupName -ErrorAction SilentlyContinue
$bad = $verified | Where-Object { $_.Enabled -ne "True" -or $_.Action -ne "Block" -or $_.Direction -ne "Outbound" }
if ($bad) {
    throw "Verification failed for some rules!"
}
$count = ($verified | Measure-Object).Count
Write-Host "[4/4] All $count rules verified: Enabled=True, Direction=Outbound, Action=Block (Loopback 127.0.0.0/8 & ::1 ONLY)."
