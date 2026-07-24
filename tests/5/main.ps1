. "$PSScriptRoot\module.ps1"

if (-not ("PsBundler.Tests.HoistedType" -as [type])) {
    throw "Static root Add-Type was not executed before deferred class compilation."
}

if (-not ("PsBundler.Tests.ShouldLoad" -as [type])) {
    throw "Add-Type was not executed at the original import location."
}

if (-not ("PsBundler.Tests.DynamicType" -as [type])) {
    throw "Dynamic root Add-Type was moved away from its prerequisite assignment."
}

if (-not ("PsBundler.Tests.PipelineType" -as [type])) {
    throw "Add-Type from a multi-command pipeline was not preserved."
}

if ("PsBundler.Tests.ShouldStayUnloaded" -as [type]) {
    throw "Add-Type escaped from its original condition."
}

$instance = [AddTypePlacementTestClass]::new()
if (-not $instance.CreateHoistedType()) {
    throw "Deferred PowerShell class cannot use the hoisted CLR type."
}

Write-Output "Add-Type placement test passed."
