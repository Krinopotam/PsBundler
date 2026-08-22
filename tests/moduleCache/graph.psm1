Import-Module "$PSScriptRoot\left.psm1"
Import-Module "$PSScriptRoot\right.psm1"
Import-Module "$PSScriptRoot\runtime.psm1"

function Get-PsBundlerGraphRuntimeIds {
    @(
        Get-PsBundlerLeftRuntimeId
        Get-PsBundlerRightRuntimeId
        Get-PsBundlerCacheRuntimeInstanceId
    )
}

Export-ModuleMember -Function Get-PsBundlerGraphRuntimeIds
