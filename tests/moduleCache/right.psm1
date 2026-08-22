Import-Module "$PSScriptRoot\runtime.psm1"

function Get-PsBundlerRightRuntimeId {
    Get-PsBundlerCacheRuntimeInstanceId
}

Export-ModuleMember -Function Get-PsBundlerRightRuntimeId
