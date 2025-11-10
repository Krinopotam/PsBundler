using module .\bundler-config.psm1
using module .\cycles-detector.psm1
using module .\file-info.psm1
using namespace System.Management.Automation.Language

class ImportsMap {
    [BundlerConfig]$_config

    importsMap ([BundlerConfig]$config) {
        $this._config = $config
    }

    [hashtable]GetImportsMap ([string]$entryPath) {
        $importMap = $this.GenerateImportsMap($entryPath, $true, $null, @{})
        $cyclesDetector = [CyclesDetector]::new()
        $hasCycles = $cyclesDetector.Check($importMap)
        if ($hasCycles) { return  $null }
        return $importMap
    }

    [hashtable]GenerateImportsMap (       
        [string]$filePath,
        [bool]$isEntry = $false,
        [FileInfo]$consumer = $null,
        [hashtable]$resultMap = @{}) {

        if ($resultMap.ContainsKey($filePath)) {
            $file = $resultMap[$filePath]
            $file.LinkToConsumer($consumer)
            return $resultMap
        }

        Write-Verbose "      Add file to map: $filePath"

        $file = [FileInfo]::new($filePath, $this._config, $isEntry, $consumer)
        $resultMap[$file.path] = $file

        $importsPaths = $file.ResolveImports()

        foreach ($importPath in $importsPaths) {
            $this.GenerateImportsMap($importPath, $false, $file, $resultMap)
        }
        
       
        return $resultMap
    }
}
