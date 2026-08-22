$ErrorActionPreference = 'Stop'
$global:PsBundlerCacheRuntimeInitializations = 0
$global:PsBundlerFalseForceExpressionEvaluations = 0

Import-Module "$PSScriptRoot\graph.psm1"
Import-Module "$PSScriptRoot\false-force-consumer.psm1"

$instanceIds = @(Get-PsBundlerGraphRuntimeIds | Select-Object -Unique)
$falseForceRuntimeId = Get-PsBundlerFalseForceRuntimeId

if ($global:PsBundlerCacheRuntimeInitializations -ne 1) {
    throw "Runtime initialized $global:PsBundlerCacheRuntimeInitializations times; expected once."
}
if ($instanceIds.Count -ne 1) {
    throw "Consumers received $($instanceIds.Count) runtime instances; expected one."
}
if ($global:PsBundlerFalseForceExpressionEvaluations -ne 1) {
    throw "False Force expression evaluated $global:PsBundlerFalseForceExpressionEvaluations times; expected once."
}
if ($falseForceRuntimeId -ne $instanceIds[0]) {
    throw 'The -Force:$false import replaced the cached runtime instance.'
}

Write-Output "PASS Diamond Initializations=$global:PsBundlerCacheRuntimeInitializations Instances=$($instanceIds.Count) FalseForceEvaluations=$global:PsBundlerFalseForceExpressionEvaluations"
