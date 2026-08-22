function Get-PsBundlerReloadDecision {
    $global:PsBundlerForceExpressionEvaluations++
    return $true
}

Import-Module "$PSScriptRoot\runtime.psm1" -Force:(Get-PsBundlerReloadDecision)
$script:PsBundlerForcedRuntimeId = Get-PsBundlerCacheRuntimeInstanceId

function Get-PsBundlerForcedRuntimeId {
    $script:PsBundlerForcedRuntimeId
}

Export-ModuleMember -Function Get-PsBundlerForcedRuntimeId
