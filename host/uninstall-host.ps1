#requires -RunAsAdministrator
# Полное удаление Omarchy Proxy с хоста: задача, процессы, runtime, сгенерированный конфиг, лог.
# settings.json и скрипты остаются (репозиторий можно удалить целиком).

$dir = $PSScriptRoot
Stop-ScheduledTask -TaskName 'OmarchyProxy' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'OmarchyProxy' -Confirm:$false -ErrorAction SilentlyContinue
Get-Process sing-box -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
foreach ($p in 'runtime', 'config.json', 'proxy.log') {
    Remove-Item "$dir\$p" -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'OK. OmarchyProxy удалён. HAPP и другие приложения не затронуты.'
