$ErrorActionPreference = 'Stop'

function Invoke-PsBundlerTransferredMapWorker {
    param([hashtable]$BundledModules)

    $global:__PS_BUNDLER_MODULES = $BundledModules
    Import-Module "$PSScriptRoot\first-consumer.psm1"

    $instanceId = Get-PsBundlerFirstRuntimeId
    $runtimeContext = $ExecutionContext.SessionState.PSVariable.GetValue(
        '__PS_BUNDLER_MODULES_RUNTIME_CONTEXT'
    )
    $sourceMapMatches = $runtimeContext -is [hashtable] -and
        [object]::ReferenceEquals(
            $runtimeContext['SourceMap'],
            $global:__PS_BUNDLER_MODULES
        )

    return "$instanceId|$global:PsBundlerCacheRuntimeInitializations|$sourceMapMatches|$($runtimeContext['Cache'].Count)"
}

$sourceMap = $global:__PS_BUNDLER_MODULES
$workerText = (Get-Command -Name Invoke-PsBundlerTransferredMapWorker).Definition
$parentContextBefore = $ExecutionContext.SessionState.PSVariable.GetValue(
    '__PS_BUNDLER_MODULES_RUNTIME_CONTEXT'
)

if ($null -ne $parentContextBefore) {
    throw 'The parent runspace unexpectedly had a module runtime context before the transfer test.'
}

$workerResults = @()
for ($workerIndex = 0; $workerIndex -lt 2; $workerIndex++) {
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace

    try {
        [void]$powershell.AddScript($workerText).AddArgument($sourceMap)
        $output = @($powershell.Invoke())
        if ($powershell.Streams.Error.Count -gt 0) {
            throw $powershell.Streams.Error[0]
        }
        $workerResults += [string]($output | Select-Object -Last 1)
    }
    finally {
        $powershell.Dispose()
        $runspace.Dispose()
    }
}

$first = @($workerResults[0] -split '\|')
$second = @($workerResults[1] -split '\|')

if ($first[0] -eq $second[0]) {
    throw 'Two worker runspaces reused the same runtime module instance.'
}
foreach ($result in @($first, $second)) {
    if ($result[1] -ne '1') {
        throw "Worker runtime initialized $($result[1]) times; expected once."
    }
    if ($result[2] -ne 'True') {
        throw 'Worker runtime context is not bound to its transferred source map.'
    }
    if ($result[3] -ne '2') {
        throw "Worker cache contains $($result[3]) modules; expected consumer and runtime."
    }
}

$parentContextAfter = $ExecutionContext.SessionState.PSVariable.GetValue(
    '__PS_BUNDLER_MODULES_RUNTIME_CONTEXT'
)
if ($null -ne $parentContextAfter) {
    throw 'Worker module initialization leaked its runtime context into the parent runspace.'
}

Write-Output 'PASS RunspaceTransfer WorkerCachesDistinct=True ParentContextLeaked=False'
