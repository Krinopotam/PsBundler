Import-Module "$PSScriptRoot\runtime.psm1"
$script:PsBundlerAfterRuntimeId = Get-PsBundlerCacheRuntimeInstanceId

function Get-PsBundlerAfterRuntimeId {
    $script:PsBundlerAfterRuntimeId
}

Export-ModuleMember -Function Get-PsBundlerAfterRuntimeId
