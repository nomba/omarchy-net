#requires -RunAsAdministrator
# Идемпотентная установка Omarchy Proxy на Windows-хост:
#   1. sing-box pinned-версии с проверкой SHA256 -> host\runtime\
#   2. host\config.json генерируется из settings.json (не редактируйте его вручную)
#   3. Задача планировщика OmarchyProxy (автозапуск супервизора при входе)
# Повторный запуск = обновление конфигурации. Запуск:
#   powershell -ExecutionPolicy Bypass -File host\install-host.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$s = Get-Content "$root\settings.json" -Raw | ConvertFrom-Json
$dir = $PSScriptRoot
$runtime = "$dir\runtime"
$v = $s.singBoxVersion
$exePath = "$runtime\sing-box.exe"

# --- 1. sing-box ---
$needDownload = -not (Test-Path $exePath)
if (-not $needDownload) {
    $current = & $exePath version 2>$null | Select-Object -First 1
    if ($current -notmatch [regex]::Escape($v)) { $needDownload = $true }
}
if ($needDownload) {
    Write-Host "Downloading sing-box $v ..."
    $zip = "$env:TEMP\sing-box-$v-windows-amd64.zip"
    Invoke-WebRequest "https://github.com/SagerNet/sing-box/releases/download/v$v/sing-box-$v-windows-amd64.zip" -OutFile $zip
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($hash -ne $s.singBoxSha256.ToUpper()) { throw "SHA256 mismatch: got $hash, expected $($s.singBoxSha256)" }
    Expand-Archive $zip "$env:TEMP\sing-box-extract" -Force
    New-Item -ItemType Directory $runtime -Force | Out-Null
    Copy-Item "$env:TEMP\sing-box-extract\sing-box-$v-windows-amd64\sing-box.exe" $runtime -Force
    Remove-Item "$env:TEMP\sing-box-extract" -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 2. config.json ---
$config = [ordered]@{
    inbounds  = @(@{ type = 'socks'; tag = 'socks-in'; listen = '127.0.0.1'; listen_port = $s.socksPort })
    outbounds = @(
        @{ type = 'http';   tag = 'vds';    server = '127.0.0.1'; server_port = $s.tunnelPort },
        @{ type = 'direct'; tag = 'direct' }
    )
    route = [ordered]@{
        rules = @(@{ action = 'sniff' })
        final = 'vds'
        auto_detect_interface = $true
    }
}
if (@($s.ruDomains).Count -gt 0) {
    $config.route.rules += @{ domain_suffix = $s.ruDomains; outbound = 'direct' }
}
$json = $config | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText("$dir\config.json", $json, [System.Text.UTF8Encoding]::new($false))

# --- 3. задача планировщика ---
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dir\omarchy-proxy.ps1`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName 'OmarchyProxy' -Action $action -Trigger $trigger `
    -Description 'SSH tunnel + sing-box for Omarchy guest (see omarchy-net repo)' -Force | Out-Null

# перезапуск, чтобы подхватить новый конфиг
Stop-ScheduledTask -TaskName 'OmarchyProxy' -ErrorAction SilentlyContinue
Start-Sleep 1
Get-CimInstance Win32_Process -Filter "Name='sing-box.exe'" |
    Where-Object { $_.ExecutablePath -eq $exePath } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
$forward = "127.0.0.1:$($s.tunnelPort):127.0.0.1:$($s.vdsProxyPort)"
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
    Where-Object { ([string]$_.CommandLine).Contains($forward) -and ([string]$_.CommandLine).Contains([string]$s.vdsHost) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-ScheduledTask -TaskName 'OmarchyProxy'
Start-Sleep 3

Write-Host ''
Write-Host 'OK. Omarchy Proxy запущен и добавлен в автозапуск.'
Write-Host "  Лог:       $dir\proxy.log"
Write-Host "  Проверка:  curl.exe --socks5 127.0.0.1:$($s.socksPort) https://api.ipify.org  (ожидается IP VDS)"
Write-Host "  Стоп:      Stop-ScheduledTask OmarchyProxy"
