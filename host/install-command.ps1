$ErrorActionPreference = 'Stop'
$manage = Join-Path $PSScriptRoot 'manage.ps1'
$shimDir = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
$shim = Join-Path $shimDir 'omarchy-net.cmd'

New-Item -ItemType Directory $shimDir -Force | Out-Null
$content = '@echo off' + "`r`n" + '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "' + $manage + '" %*' + "`r`n"
[System.IO.File]::WriteAllText($shim, $content, [System.Text.Encoding]::ASCII)

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathParts = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($pathParts -notcontains $shimDir) {
    $newPath = (@($pathParts) + $shimDir) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host 'Откройте новый терминал, чтобы использовать omarchy-net.'
} else {
    Write-Host 'OK. Команда omarchy-net доступна в текущем PATH.'
}
Write-Host "Shim: $shim"
Write-Host 'Проверка: omarchy-net status'
