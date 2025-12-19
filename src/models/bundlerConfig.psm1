using module ..\helpers\objectHelpers.psm1
using module ..\helpers\pathHelpers.psm1

class BundlerConfig {
    # config path
    [string]$configPath
    # project folder root path
    [string]$projectRoot = ".\"
    # output folder path in project folder (relative to projectRoot)
    [string]$outDir = "build"
    # map of entry points path (relative to projectRoot)
    [hashtable]$entryPoints = @{}
    # strip comments in bundle
    [bool]$stripComments = $true
    # keep comments at the top of entry file
    [bool]$keepHeaderComments = $true
    # whether to obfuscate the output bundle (Natural/Hard)
    [string]$obfuscate = ""
    # whether to defer classes compilation by wrapping classes source in Invoke-Expression
    [bool]$deferClassesCompilation = $false
    # whether to embed deferred classes as base64. If false, classes will be embedded as here-strings (no here-string escaping)
    [bool]$embedClassesAsBase64 = $false

    # Source map variable name used in bundle
    [string]$modulesSourceMapVarName # = "__PS_BUNDLER_MODULES__"

    [ObjectHelpers]$_objectHelpers
    [PathHelpers]$_pathHelpers

    BundlerConfig ([string]$configPath = "") {
        $this._objectHelpers = [ObjectHelpers]::New()
        $this._pathHelpers = [PathHelpers]::New()
        
        if ($configPath) {
            $this.configPath = $this._pathHelpers.GetFullPath($configPath)
        }
        
        if (-not $this.configPath) { 
            $scriptLaunchPath = Get-Location # current PS active path
            $this.configPath = [System.IO.Path]::Combine($scriptLaunchPath, 'psbundler.config.json')
        }
        
        $this.Load()
        $this.modulesSourceMapVarName = "__MODULES_" + [Guid]::NewGuid().ToString("N")
    }

    [void]Load() {
        # -- Default config
        $config = @{
            projectRoot             = ".\"          # project folder root path
            outDir                  = "build"       # output folder path in project folder
            entryPoints             = @{}           # list of entry points path
            stripComments           = $true         # strip comments in bundle
            keepHeaderComments      = $true         # keep comments at the top of entry file
            obfuscate               = ""            # whether to obfuscate the output bundle (Natural/Hard)
            deferClassesCompilation = $false   # whether to defer classes compilation by wrapping classes source in Invoke-Expression
            embedClassesAsBase64    = $false      # whether to embed deferred classes as base64. If false, classes will be embedded as here-strings (no here-string escaping)
        }

        $userConfig = $this.GetConfigFromFile()

        foreach ($key in $userConfig.Keys) { $config[$key] = $userConfig[$key] }

        # -- Prepare project root path 
        $configDir = [System.IO.Path]::GetDirectoryName($this.configPath)
        $root = $this._pathHelpers.GetFullPath($config.projectRoot, $configDir)
        $this.projectRoot = $root
    
        # -- Prepare outDir path 
        if (-not $config.outDir) { $config.outDir = "" }
        $this.outDir = $this._pathHelpers.GetFullPath($config.outDir, $root)

        # -- Prepare entries paths
        if (-not $userConfig.entryPoints -or $userConfig.entryPoints.Count -eq 0) { throw "No entry points found in config" }

        $this.entryPoints = @{}
        foreach ($entryPath in $config.entryPoints.Keys) {
            $bundleName = $config.entryPoints[$entryPath]
            if (-not ($this._pathHelpers.IsValidPath($bundleName))) { throw "Invalid bundle name: $bundleName" }
            $entryAbsPath = $this._pathHelpers.GetFullPath($entryPath, $root)
            if (-not $entryAbsPath) { throw "Invalid entry path: $entryPath" }
            $this.entryPoints[$entryAbsPath] = $bundleName
        }

        $this.stripComments = $config.stripComments
        $this.keepHeaderComments = $config.keepHeaderComments
        $this.obfuscate = ""
        if ($config.obfuscate) {
            if ($config.obfuscate -eq "Natural") { $this.obfuscate = $config.obfuscate } 
            else { $this.obfuscate = "Hard" }
        }

        $this.deferClassesCompilation = $config.deferClassesCompilation
        $this.embedClassesAsBase64 = $config.embedClassesAsBase64
    }

    [PSCustomObject]GetConfigFromFile () {
        if ((Test-Path $this.configPath)) {
            try {
                $config = Get-Content $this.configPath -Raw | ConvertFrom-Json
                $configHashTable = $this._objectHelpers.ConvertToHashtable($config)
                Write-Host "Using config: $($this.configPath)"
                return $configHashTable
            }
            catch {
                Write-Host "Error reading config file: $($_.Exception.Message)" -ForegroundColor Red
                exit 1
            }
        }
    
        Write-Host "Config file not found: $($this.configPath)" -ForegroundColor Red
        exit 1
    }
}
