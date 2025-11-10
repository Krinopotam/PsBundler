using namespace System.Management.Automation.Language

[CmdletBinding()]
param (
    [string]$config1
)

. "$PSScriptRoot/b.ps1"

function Use-Test1 {
    Write-Host "Use-Test1 config1: $config1"
}

Use-Test1
Use-Test2



