using module .\bundler-config.psm1
using module .\cycles-detector.psm1
using module .\file-info.psm1
using namespace System.Management.Automation.Language

class ImportsMapper {
    [BundlerConfig]$_config

    ImportsMapper ([BundlerConfig]$config) {
        $this._config = $config
    }

    [hashtable]GetImportsMap ([string]$entryPath) {
        $importMap = $this.GenerateMap($entryPath, $true, $null, $null, @{})
        $cyclesDetector = [CyclesDetector]::new()
        $hasCycles = $cyclesDetector.Check($importMap)
        if ($hasCycles) { return  $null }
        return $importMap
    }

    [hashtable]GenerateMap (       
        [string]$filePath,
        [bool]$isEntry = $false,
        [FileInfo]$consumer = $null,
        [string]$importType = $null,
        [hashtable]$importMap = @{}) {

        if ($importMap.ContainsKey($filePath)) {
            $file = $importMap[$filePath]
            $file.LinkToConsumer($consumer)
            return $importMap
        }

        Write-Verbose "      Add file to map: $filePath"

        $file = [FileInfo]::new($filePath, $this._config, $isEntry, $consumer, $importType)
        $importMap[$file.path] = $file

        $importsInfo = $file.ResolveImports()

        foreach ($importInfo in $importsInfo) {
            $path = $importInfo.path
            $type = $importInfo.type
            $this.GenerateMap($path, $false, $file, $type, $importMap)
        }
        
       
        return $importMap
    }
}
