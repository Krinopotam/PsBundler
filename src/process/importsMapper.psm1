using module ..\helpers\cyclesDetector.psm1
using module ..\parsers\importParser.psm1
using module ..\models\bundlerConfig.psm1
using module ..\models\fileInfo.psm1
using namespace System.Management.Automation.Language

Class ImportsMapper {
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

        # A file containing only classes can normally disappear after its classes
        # are extracted. It must remain executable, however, when it imports a
        # dependency with runtime code (for example, a guarded Add-Type). Propagate
        # that fact through the acyclic import graph before replacements are built.
        $entryFile = $this.GetEntryFile($importMap)
        $this.UpdateTypesOnly($entryFile, @{})

        return $importMap
    }

    [void]UpdateTypesOnly([FileInfo]$file, [hashtable]$processed) {
        if (-not $file -or $processed.ContainsKey($file.path)) { return }
        $processed[$file.path] = $true

        foreach ($importInfo in $file.imports.Values) {
            $importFile = $importInfo.file
            $this.UpdateTypesOnly($importFile, $processed)

            # "typesOnly" is used to remove both a file body and imports pointing
            # to it. A runtime dependency makes the importing file runtime-relevant
            # as well, even if its own body contains only PowerShell classes.
            if (-not $importFile.typesOnly) { $file.typesOnly = $false }
        }
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

        $file = [FileInfo]::new($filePath, $this._config, $isEntry, $consumerInfo)
        $importMap[$file.path] = $file

        $importsInfo = $this._importParser.ParseFile($file)

        foreach ($importInfo in $importsInfo) {
            $consumerInfo = @{
                File      = $file
                PathAst   = $importInfo.PathAst
                ImportAst = $importInfo.ImportAst
                Type      = $importInfo.Type
            }
            $this.GenerateMap( $importInfo.Path, $false, $consumerInfo, $importMap)
        }
       
        return $importMap
    }

    # Get entry file
    [FileInfo]getEntryFile([System.Collections.Specialized.OrderedDictionary]$importsMap) {
        foreach ($file in $importsMap.Values) {
            if ($file.isEntry) { return $file }
        }
        return $null
    }
}
