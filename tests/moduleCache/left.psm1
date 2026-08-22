Import-Module "$PSScriptRoot\runtime.psm1"

function Get-PsBundlerLeftRuntimeId {
    Get-PsBundlerCacheRuntimeInstanceId
}

Export-ModuleMember -Function Get-PsBundlerLeftRuntimeId
