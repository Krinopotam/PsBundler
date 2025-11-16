using module ..\models\bundlerConfig.psm1
using module ..\process\importsMapper.psm1
using module ..\process\replacer.psm1
using module ..\process\bundleBuilder.psm1

Class ScriptBundler {
    [string]$_entryPath
    [string]$_bundleName
    [BundlerConfig]$_config

    ScriptBundler ([string]$entryPath, [string]$bundleName, [BundlerConfig]$config) {
        $this._entryPath = $entryPath
        $this._bundleName = $bundleName
        $this._config = $config
    }

    [string]Start () {
        if (-not (Test-Path $this._entryPath)) { Throw "HANDLED: Entry point not found: $($this._entryPath)" }

        $importsMapper = [ImportsMapper]::new($this._config)
        $importsMap = $importsMapper.GetImportsMap($this._entryPath)
        if (-not $importsMap) { Throw "HANDLED: Can't build bundle: no modules map created" }

        $entryFile = $importsMapper.GetEntryFile($importsMap)
        if (-not $entryFile) { Throw "HANDLED: Entry file is not found in imports map" }

        $replacer = [Replacer]::new($this._config)
        $replacementsInfo = $replacer.GetReplacements($importsMap)

        $bundleBuilder = [BundleBuilder]::new($this._config)
        $outputPath = $bundleBuilder.Build($importsMap, $replacementsInfo, $this._bundleName)
        return $outputPath
    }
}
