$ErrorActionPreference = 'Stop'
$global:PsBundlerCacheRuntimeInitializations = 0
$global:PsBundlerForceExpressionEvaluations = 0

Import-Module "$PSScriptRoot\first-consumer.psm1"
Import-Module "$PSScriptRoot\force-consumer.psm1"
Import-Module "$PSScriptRoot\after-consumer.psm1"

$firstId = Get-PsBundlerFirstRuntimeId
$forcedId = Get-PsBundlerForcedRuntimeId
$afterId = Get-PsBundlerAfterRuntimeId

if ($global:PsBundlerCacheRuntimeInitializations -ne 2) {
    throw "Runtime initialized $global:PsBundlerCacheRuntimeInitializations times; expected two."
}
if ($global:PsBundlerForceExpressionEvaluations -ne 1) {
    throw "Force expression evaluated $global:PsBundlerForceExpressionEvaluations times; expected once."
}
if ($firstId -eq $forcedId) {
    throw 'The forced import did not create a new runtime instance.'
}
if ($forcedId -ne $afterId) {
    throw 'The import after -Force did not reuse the refreshed runtime instance.'
}

Write-Output "PASS Force Initializations=$global:PsBundlerCacheRuntimeInitializations ForceEvaluations=$global:PsBundlerForceExpressionEvaluations RefreshedInstanceReused=$($forcedId -eq $afterId)"
