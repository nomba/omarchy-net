[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'on', 'off', 'ru')]
    [string]$Command = 'status',

    [Parameter(Position = 1)]
    [string]$Action,

    [Parameter(Position = 2, ValueFromRemainingArguments = $true)]
    [string[]]$Domains
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$hostDir = $PSScriptRoot
$root = Split-Path $hostDir -Parent
$settingsPath = Join-Path $root 'settings.json'
$installerPath = Join-Path $hostDir 'install-host.ps1'
$taskName = 'OmarchyProxy'
$idn = New-Object System.Globalization.IdnMapping

function Get-Settings {
    return Get-Content $settingsPath -Raw | ConvertFrom-Json
}

function Get-ProxyTask {
    return Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
}

function Test-Listener([int]$Port) {
    $listener = Get-NetTCPConnection -State Listen -LocalAddress '127.0.0.1' -LocalPort $Port -ErrorAction SilentlyContinue
    return $null -ne $listener
}

function Write-Status {
    $s = Get-Settings
    $task = Get-ProxyTask
    $taskState = if ($task) { [string]$task.State } else { 'Отсутствует' }
    $tunnel = Test-Listener ([int]$s.tunnelPort)
    $socks = Test-Listener ([int]$s.socksPort)
    $ip = $null

    if ($socks) {
        $response = & curl.exe --fail --silent --show-error --max-time 8 `
            --socks5 "127.0.0.1:$($s.socksPort)" https://api.ipify.org 2>$null
        if ($LASTEXITCODE -eq 0) { $ip = ($response -join '').Trim() }
    }

    $healthy = $taskState -eq 'Running' -and $tunnel -and $socks -and -not [string]::IsNullOrWhiteSpace($ip)
    $state = if ($healthy) {
        'OK'
    } elseif (-not $task) {
        'NOT INSTALLED'
    } elseif ($taskState -ne 'Running' -and -not $tunnel -and -not $socks) {
        'OFF'
    } else {
        'DEGRADED'
    }

    $tunnelText = if ($tunnel) { 'слушается' } else { 'закрыт' }
    $socksText = if ($socks) { 'слушается' } else { 'закрыт' }
    $ipText = if ($ip) { $ip } else { 'недоступен' }

    Write-Host "Omarchy Net: $state"
    Write-Host "  Задача:      $taskState"
    Write-Host "  SSH-туннель: 127.0.0.1:$($s.tunnelPort) ($tunnelText)"
    Write-Host "  SOCKS:       127.0.0.1:$($s.socksPort) ($socksText)"
    Write-Host "  Внешний IP:  $ipText"
    Write-Host "  VDS:         $($s.vdsHost)"
    Write-Host "  ruDomains:   $(@($s.ruDomains).Count) (omarchy-net ru list)"

    return $healthy
}

function Stop-ProxyChildren {
    $s = Get-Settings
    $singBoxPath = Join-Path $hostDir 'runtime\sing-box.exe'
    $forward = "127.0.0.1:$($s.tunnelPort):127.0.0.1:$($s.vdsProxyPort)"
    $processes = Get-CimInstance Win32_Process -Filter "Name='ssh.exe' OR Name='sing-box.exe'"

    foreach ($p in $processes) {
        $owned = $false
        if ($p.Name -ieq 'sing-box.exe' -and $p.ExecutablePath -eq $singBoxPath) {
            $owned = $true
        } elseif ($p.Name -ieq 'ssh.exe') {
            $commandLine = [string]$p.CommandLine
            if ($commandLine.Contains($forward) -and $commandLine.Contains([string]$s.vdsHost)) {
                $owned = $true
            }
        }
        if ($owned) {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}

function Wait-ProxyPorts {
    $s = Get-Settings
    for ($i = 0; $i -lt 25; $i++) {
        if ((Test-Listener ([int]$s.tunnelPort)) -and (Test-Listener ([int]$s.socksPort))) {
            return
        }
        Start-Sleep -Seconds 1
    }
}

function Invoke-On {
    $task = Get-ProxyTask
    if (-not $task) {
        throw 'OmarchyProxy не установлен. Сначала запустите host\install-host.ps1 от администратора.'
    }
    if ($task.State -ne 'Running') {
        Stop-ProxyChildren
        Start-ScheduledTask -TaskName $taskName
    }
    Wait-ProxyPorts
}

function Invoke-Off {
    $task = Get-ProxyTask
    if ($task -and $task.State -eq 'Running') {
        Stop-ScheduledTask -TaskName $taskName
    }
    Start-Sleep -Seconds 2
    Stop-ProxyChildren
    Write-Host 'Omarchy Net: OFF'
    Write-Host 'Интернет в госте заблокирован его kill switch. Windows-приложения не затронуты.'
    Write-Host 'Автозапуск сохранён: включить — omarchy-net on.'
}

function Invoke-HostInstaller {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        & $installerPath
        return
    }

    Write-Host 'Для перезапуска OmarchyProxy потребуется подтверждение UAC.'
    $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$installerPath`"" `
        -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        throw "install-host.ps1 завершился с кодом $($p.ExitCode)."
    }
}

function Normalize-Domain([string]$Domain) {
    $value = $Domain.Trim().TrimEnd('.').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw 'Domain cannot be empty.'
    }
    try {
        $value = $idn.GetAscii($value).ToLowerInvariant()
    } catch {
        throw "Invalid domain: $Domain"
    }
    $pattern = '^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'
    if ($value -notmatch $pattern) {
        throw "Invalid domain: $Domain"
    }
    return $value
}

function Show-RuDomains {
    $s = Get-Settings
    $domains = @($s.ruDomains)
    Write-Host "ruDomains ($($domains.Count)):"
    foreach ($domain in $domains) {
        Write-Host "  $domain"
    }
}

function Update-RuDomains([string]$Mode, [string[]]$InputDomains) {
    if (-not $InputDomains -or $InputDomains.Count -eq 0) {
        throw "Usage: omarchy-net ru $Mode <domain> [domain...]"
    }

    $s = Get-Settings
    $current = @($s.ruDomains | ForEach-Object { Normalize-Domain ([string]$_) })
    $updated = @($current)

    foreach ($inputDomain in $InputDomains) {
        $domain = Normalize-Domain $inputDomain
        if ($Mode -eq 'add') {
            if ($updated -notcontains $domain) { $updated += $domain }
        } else {
            $updated = @($updated | Where-Object { $_ -ne $domain })
        }
    }

    if (($current -join "`n") -ceq ($updated -join "`n")) {
        Write-Host 'ruDomains не изменился; перезапуск прокси не требуется.'
        return
    }

    $originalJson = [System.IO.File]::ReadAllText($settingsPath)
    $s.ruDomains = @($updated)
    $json = $s | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))

    try {
        Invoke-HostInstaller
    } catch {
        [System.IO.File]::WriteAllText($settingsPath, $originalJson, [System.Text.UTF8Encoding]::new($false))
        throw
    }

    Write-Host 'ruDomains обновлён, OmarchyProxy перезапущен.'
    $healthy = Write-Status
    if (-not $healthy) { exit 1 }
}

try {
    switch ($Command) {
        'status' {
            $healthy = Write-Status
            if ($healthy) { exit 0 } else { exit 1 }
        }
        'on' {
            Invoke-On
            $healthy = Write-Status
            if ($healthy) { exit 0 } else { exit 1 }
        }
        'off' {
            Invoke-Off
            exit 0
        }
        'ru' {
            if ([string]::IsNullOrWhiteSpace($Action) -or $Action -eq 'list') {
                Show-RuDomains
                exit 0
            }
            if ($Action -in 'add', 'remove') {
                Update-RuDomains $Action $Domains
                exit 0
            }
            throw 'Usage: omarchy-net ru [list|add|remove] [domain...]'
        }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
