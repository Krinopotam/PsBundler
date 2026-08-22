Import-Module "$PSScriptRoot\runtime.psm1"
$script:PsBundlerFirstRuntimeId = Get-PsBundlerCacheRuntimeInstanceId

function Get-PsBundlerFirstRuntimeId {
    $script:PsBundlerFirstRuntimeId
}

Export-ModuleMember -Function Get-PsBundlerFirstRuntimeId
