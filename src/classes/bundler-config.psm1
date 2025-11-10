using module .\object-helpers.psm1
using module .\path-helpers.psm1

class BundlerConfig {
    # project folder root path
    [string]$projectRoot = ".\"
    # src folder path in project folder
    [string]$srcRoot = "src"
    # output folder path in project folder
    [string]$outDir = "build"
    # map of entry points path
    [hashtable]$entryPoints = @{}
    # add comment with source file names to bundle
    [bool]$addSourceFileNames = $true
    # strip comments in bundle
    [bool]$stripComments = $true
    # keep comments at the top of entry file
    [bool]$keepHeaderComments = $true     
    # whether to obfuscate the output bundle (Natural/Hard)
    [string]$obfuscate = ""

    [ObjectHelpers]$_objectHelpers
    [PathHelpers]$_pathHelpers

    BundlerConfig () {
        $this._objectHelpers = [ObjectHelpers]::New()
        $this._pathHelpers = [PathHelpers]::New()
        $this.Load()
    }

    [void]Load() {
        # -- Default config
        $config = @{
            projectRoot        = ".\"          # project folder root path
            srcRoot            = "src"         # src folder path in project folder
            outDir             = "build"       # output folder path in project folder
            entryPoints        = @{}           # list of entry points path
            addSourceFileNames = $true         # add comment with source file names to bundle
            stripComments      = $true        # strip comments in bundle
            keepHeaderComments = $true         # keep comments at the top of entry file
            obfuscate          = ""            # whether to obfuscate the output bundle (Natural/Hard)
        }

        $userConfig = $this.GetConfigFromFile()

        foreach ($key in $userConfig.Keys) { $config[$key] = $userConfig[$key] }

        # -- Prepare project root path 
        $root = [System.IO.Path]::GetFullPath($config.projectRoot)
        $this.projectRoot = $root

        # -- Prepare src path 
        $src = $config.srcRoot
        if (-not $src) { $src = "" }
        if (-not ([System.IO.Path]::IsPathRooted($src))) { $src = Join-Path $root $src }
        $this.srcRoot = [System.IO.Path]::GetFullPath($src)
    
        # -- Prepare outDir path 
        if (-not $config.outDir) { $config.outDir = "" }
        if (-not ([System.IO.Path]::IsPathRooted($config.outDir))) { $config.outDir = Join-Path $root $config.outDir }
        $this.outDir = [System.IO.Path]::GetFullPath($config.outDir)

        # -- Prepare entries paths
        if (-not $userConfig.entryPoints -or $userConfig.entryPoints.Count -eq 0) { throw "No entry points found in config" }

        $this.entryPoints = @{}
        foreach ($entryPath in $config.entryPoints.Keys) {
            $bundleName = $config.entryPoints[$entryPath]
            if (-not ($this._pathHelpers.IsValidPath($bundleName))) { throw "Invalid bundle name: $bundleName" }

            $entryAbsPath = [System.IO.Path]::GetFullPath( (Join-Path $src $entryPath))
            $this.entryPoints[$entryAbsPath] = $bundleName
        }

        $this.addSourceFileNames = $config.addSourceFileNames
        $this.stripComments = $config.stripComments
        $this.keepHeaderComments = $config.keepHeaderComments
        $this.obfuscate = ""
        if ($config.obfuscate) {
            if ($config.obfuscate -eq "Natural") { $this.obfuscate = $config.obfuscate } 
            else { $this.obfuscate = "Hard" }
        }
    }

    [PSCustomObject]GetConfigFromFile () {
        $scriptLaunchPath = Get-Location # current PS active path

        $configPath = Join-Path -Path $scriptLaunchPath -ChildPath 'psbundler.config.json'

        if ((Test-Path $configPath)) {
            try {
                $config = Get-Content $configPath -Raw | ConvertFrom-Json
                $configHashTable = $this._objectHelpers.ConvertToHashtable($config)
                return $configHashTable
            }
            catch {
                throw "Error reading config file: $_.Exception.Message"
            }
        }
    
        throw "Config file not found: $configPath"
    }
}
