using module .\bundler-config.psm1
using module .\imports-map.psm1
using module .\bundle-saver.psm1

class BundleScript {
    [string]$_entryPath
    [string]$_bundleName
    [BundlerConfig]$_config

    BundleScript ([string]$entryPath, [string]$bundleName, [BundlerConfig]$config) {
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
        $iMapCls = [ImportsMap]::new($this._config)
        $importsMap = $iMapCls.GetImportsMap($this._entryPath)
        if (-not $importsMap) {
            Write-Host "Can't build bundle: no modules map created" -ForegroundColor Red
            return $null
        }

        Write-Verbose "    Check cycles complete"

        $bundleSaver = [BundleSaver]::new($this._config)
        $outputPath = $bundleSaver.Generate($importsMap, $this._bundleName)
        return $outputPath
    }
    
}
