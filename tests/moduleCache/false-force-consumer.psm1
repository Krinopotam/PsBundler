function Get-PsBundlerNoReloadDecision {
    $global:PsBundlerFalseForceExpressionEvaluations++
    return $false
}

Import-Module "$PSScriptRoot\runtime.psm1" -Force:(Get-PsBundlerNoReloadDecision)
$script:PsBundlerFalseForceRuntimeId = Get-PsBundlerCacheRuntimeInstanceId

function Get-PsBundlerFalseForceRuntimeId {
    $script:PsBundlerFalseForceRuntimeId
}

Export-ModuleMember -Function Get-PsBundlerFalseForceRuntimeId
