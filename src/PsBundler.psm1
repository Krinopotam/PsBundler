###################################### PSBundler #########################################
#Author: Zaytsev Maksim
#Version: 2.0.4
#requires -Version 5.1
##########################################################################################

using module .\process\scriptBundler.psm1
using module .\models\bundlerConfig.psm1
using module .\classes\ps-obfuscator.psm1


class PsBundler { 
    [object]$_config

    PsBundler () {
        $this.Start()
    }

    [void]Start () {
        Write-Host "Building..."

        $this._config = [BundlerConfig]::new()

        if (-not $this._config.entryPoints) {
            Write-Error "No entry points found in config"
            exit
        }

        foreach ($entryPoint in $this._config.entryPoints.Keys) {
            $bundleName = $this._config.entryPoints[$entryPoint]
            Write-Verbose "  Starting bundle: $entryPoint => $bundleName"
            $scriptBundler = [ScriptBundler]::new($entryPoint, $bundleName, $this._config)
            $resultPath = $scriptBundler.Start()
            if (-not $resultPath) {
                Write-Host "Build failed" -ForegroundColor Red
                return 
            }

            Write-Verbose "  End bundle: $resultPath"
            
            if ($this._config.obfuscate) {
                Write-Verbose "  Start obfuscation: $resultPath"
                $psObfuscator = [PsObfuscator]::new($resultPath, $null, @(), @(), $this._config.obfuscate)
                $psObfuscator.Start()
                Write-Verbose "  End obfuscation: $resultPath"
            }
        }

        Write-Host "Build completed at: $($this._config.outDir)"
    }
}

function Invoke-PSBundler {
    [CmdletBinding()]
    $null = New-Object PsBundler 
}