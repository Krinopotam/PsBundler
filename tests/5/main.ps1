. "$PSScriptRoot\module.ps1"

if (-not ("PsBundler.Tests.ShouldLoad" -as [type])) {
    throw "Add-Type was not executed at the original import location."
}

if ("PsBundler.Tests.ShouldStayUnloaded" -as [type]) {
    throw "Add-Type escaped from its original condition."
}

Write-Output "Add-Type placement test passed."
