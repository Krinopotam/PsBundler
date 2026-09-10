using module ..\models\bundlerConfig.psm1

class BuildHookRunner {
    [BundlerConfig]$_config

    BuildHookRunner ([BundlerConfig]$config) {
        $this._config = $config
    }

    [void]Run ([string[]]$scriptPaths, [string]$stage) {
        if (-not $scriptPaths -or $scriptPaths.Count -eq 0) { return }

        foreach ($scriptPath in $scriptPaths) {
            Write-Host "    Running $stage hook: $scriptPath"

            $oldLocation = Get-Location

            try {
                # Hooks are regular scripts, not dot-sourced files. This keeps
                # their variables and functions out of the bundler scope.
                $ErrorActionPreference = "Stop"
                Set-Location -LiteralPath $this._config.projectRoot
                & $scriptPath
            }
            catch {
                throw "HANDLED: Error in $stage hook '$scriptPath': $($_.Exception.Message)"
            }
            finally {
                Set-Location -LiteralPath $oldLocation.Path
            }
        }
    }
}
