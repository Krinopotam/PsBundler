Remove-Module PsBundler -ErrorAction SilentlyContinue
$modulePath = Resolve-Path ".\src\PsBundler.psd1"
Import-Module $modulePath -Force
Invoke-PsBundler -verbose