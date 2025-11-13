using module ..\models\bundlerConfig.psm1
using module ..\process\importsMapper.psm1
using module ..\process\replacer.psm1
using module ..\classes\bundle-saver.psm1

class ScriptBundler {
    [string]$_entryPath
    [string]$_bundleName
    [BundlerConfig]$_config

    ScriptBundler ([string]$entryPath, [string]$bundleName, [BundlerConfig]$config) {
        $this._entryPath = $entryPath
        $this._bundleName = $bundleName
        $this._config = $config
    }

    [string]Start () {
        if (-not (Test-Path $this._entryPath)) {
            Write-Host "Can't build bundle: no entry point found" -ForegroundColor Red
            return $null
        }

        Write-Verbose "    Prepare import map"
        $importsMapper = [ImportsMapper]::new($this._config)
        $importsMap = $importsMapper.GetImportsMap($this._entryPath)
        if (-not $importsMap) {
            Write-Host "Can't build bundle: no modules map created" -ForegroundColor Red
            return $null
        }

        $entryFile = $importsMapper.GetEntryFile($importsMap)
        if (-not $entryFile) { Throw "Entry file is not found in imports map" }

        $replacer = [Replacer]::new($this._config)
        $replacements = $replacer.GetReplacements($importsMap)

        return ""

        $bundleSaver = [BundleSaver]::new($this._config)
        $outputPath = $bundleSaver.Generate($importsMap, $this._bundleName)
        return $outputPath
    }

    
    
}
