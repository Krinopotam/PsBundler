using module ..\helpers\cyclesDetector.psm1
using module ..\parsers\importParser.psm1
using module ..\models\bundlerConfig.psm1
using module ..\models\fileInfo.psm1
using namespace System.Management.Automation.Language

class ImportsMapper {
    [BundlerConfig]$_config
    [ImportParser]$_importParser

    ImportsMapper ([BundlerConfig]$config) {
        $this._config = $config
        $this._importParser = [ImportParser]::new($config)
    }

    [System.Collections.Specialized.OrderedDictionary]GetImportsMap ([string]$entryPath) {
        $importMap = $this.GenerateMap($entryPath, $true, $null, [ordered]@{})
        $cyclesDetector = [CyclesDetector]::new()
        $hasCycles = $cyclesDetector.Check($importMap)
        if ($hasCycles) { return  $null }
        return $importMap
    }

    [System.Collections.Specialized.OrderedDictionary]GenerateMap (       
        [string]$filePath,
        [bool]$isEntry,
        [hashtable]$consumerInfo,
        [System.Collections.Specialized.OrderedDictionary]$importMap) {

        if ($importMap.Contains($filePath)) {
            $file = $importMap[$filePath]
            $file.LinkToConsumer($consumerInfo)
            return $importMap
        }

        Write-Verbose "      Add file to map: $filePath"

        $file = [FileInfo]::new($filePath, $this._config, $isEntry, $consumerInfo)
        $importMap[$file.path] = $file

        $importsInfo = $this._importParser.ParseFile($file)

        foreach ($importInfo in $importsInfo) {
            $consumerInfo = @{
                File = $file
                PathAst = $importInfo.PathAst
                ImportAst = $importInfo.ImportAst
                Type = $importInfo.Type
            }
            $this.GenerateMap( $importInfo.Path, $false, $consumerInfo, $importMap)
        }
       
        return $importMap
    }
}
