using module .\process\scriptBundler.psm1
using module .\models\bundlerConfig.psm1
using module .\extra\ps-obfuscator.psm1

Class PsBundler { 
    [object]$_config

    PsBundler ([string]$configPath) {
        $this.Start($configPath)
    }

    [void]Start ([string]$configPath) {
        try {
            Write-Host "Start building..."

            $this._config = [BundlerConfig]::new($configPath)

            if (-not $this._config.entryPoints) { Throw "HANDLED: No entry points found in config" }

            foreach ($entryPoint in $this._config.entryPoints.Keys) {
                $bundleName = $this._config.entryPoints[$entryPoint]
                Write-Host "    Starting bundle: $entryPoint => $bundleName"
                $scriptBundler = [ScriptBundler]::new($entryPoint, $bundleName, $this._config)
                $resultPath = $scriptBundler.Start()
                if (-not $resultPath) { Throw "HANDLED: Build failed" }

                if ($this._config.obfuscate) {
                    $psObfuscator = [PsObfuscator]::new($resultPath, $null, @(), @(), $this._config.obfuscate)
                    $psObfuscator.Start()
                }

                Write-Host "    Bundle saved at: $resultPath"
            }

            Write-Host "Build completed at: $($this._config.outDir)"
        }
        catch {
            if ($_.Exception.Message -like "HANDLED:*") { Write-Host ($_.Exception.Message -replace "^HANDLED:\s*", "") -ForegroundColor Red }
            else { Write-Error -ErrorRecord $_ }
        }
    }
}

function Invoke-PSBundler {
    [CmdletBinding()]
    param(
        [string]$configPath = ""
    )
    $null = [PsBundler]::new($configPath) 
}
