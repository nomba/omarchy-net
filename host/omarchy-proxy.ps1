# Единый супервизор Omarchy Proxy: SSH-туннель до VDS + sing-box для гостя.
# Запускается задачей планировщика OmarchyProxy (см. install-host.ps1) или вручную.
# Следит за обоими процессами, перезапускает при падении, при своей остановке гасит обоих.

$root = Split-Path $PSScriptRoot -Parent
$settingsPath = Join-Path $root 'settings.local.json'
if (-not (Test-Path $settingsPath)) { $settingsPath = Join-Path $root 'settings.json' }
$s = Get-Content $settingsPath -Raw | ConvertFrom-Json
$vdsHost = [string]$s.vdsHost
if ([string]::IsNullOrWhiteSpace($vdsHost) -or $vdsHost.Contains('YOUR_VDS_IP')) {
    throw 'Настройте vdsHost в settings.local.json или settings.json.'
}
$dir = $PSScriptRoot
$log = "$dir\proxy.log"

$sshExe  = 'C:\Windows\System32\OpenSSH\ssh.exe'
$sshArgs = "-N -T -L 127.0.0.1:$($s.tunnelPort):127.0.0.1:$($s.vdsProxyPort) " +
           '-o BatchMode=yes -o ConnectTimeout=15 -o ExitOnForwardFailure=yes ' +
           "-o ServerAliveInterval=30 -o ServerAliveCountMax=3 $($s.vdsHost)"
$sbExe   = "$dir\runtime\sing-box.exe"
$sbArgs  = "run -c `"$dir\config.json`""

function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File -Append -Encoding utf8 $log }

$ssh = $null
$sb  = $null
try {
    while ($true) {
        if ($null -eq $ssh -or $ssh.HasExited) {
            if ($ssh) { Log "ssh exited (code $($ssh.ExitCode)), restart in 10s"; Start-Sleep 10 }
            Log 'starting ssh tunnel'
            $ssh = Start-Process $sshExe -ArgumentList $sshArgs -WindowStyle Hidden -PassThru
        }
        if ($null -eq $sb -or $sb.HasExited) {
            if ($sb) { Log "sing-box exited (code $($sb.ExitCode)), restart in 5s"; Start-Sleep 5 }
            Log 'starting sing-box'
            $sb = Start-Process $sbExe -ArgumentList $sbArgs -WorkingDirectory $dir -WindowStyle Hidden -PassThru
        }
        Start-Sleep 5
    }
}
finally {
    foreach ($p in @($ssh, $sb)) {
        if ($null -ne $p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    }
    Log 'supervisor stopped, children terminated'
}
