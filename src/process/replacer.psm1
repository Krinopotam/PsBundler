using module ..\models\bundlerConfig.psm1
using module ..\models\fileInfo.psm1

Class Replacer {
    [BundlerConfig]$_config

    Replacer([BundlerConfig]$config) {
        $this._config = $config
    }

    [hashtable]prepareReplacements([FileInfo]$file) {
        $replacements = [System.Collections.ArrayList]::new()
    }

    [System.Collections.ArrayList]getImportReplacements([FileInfo]$file) {
        $replacements = [System.Collections.ArrayList]::new()

        foreach ($importInfo in $file.imports.Values) {
            $importFile = $importInfo.file
            $importId = $importFile.id
            if ($importInfo.type -eq 'dot' -or $importInfo.type -eq 'module') {
            
                $replacements.Add(@{
                        Start  = $importInfo.ImportAst.Extent.StartOffset
                        Length = $importInfo.ImportAst.Extent.EndOffset - $importInfo.PathAst.Extent.StartOffset
                        # replace whole dot-import statement
                        Value  = 'Invoke-Expression ($ExecutionContext.SessionState.PSVariable.GetValue("__PSBUNDLE_MODULES__"))['+$importId+'].toString()'
                    })
            }
            elseif ($importInfo.type -eq 'ampersand') {
                $replacements.Add(@{
                        Start  = $importInfo.ImportAst.Extent.StartOffset
                        Length = $importInfo.ImportAst.Extent.EndOffset - $importInfo.ImportAst.Extent.StartOffset
                        # replace whole ampersand-import statement
                        Value  = '(($ExecutionContext.SessionState.PSVariable.GetValue("__PSBUNDLE_MODULES__"))[' + $importId + ']).Invoke()'
                    })
            }
            elseif ($importInfo.type -eq 'module') {
                $replacements.Add(@{
                        Start  = $importInfo.PathAst.Extent.StartOffset
                        Length = $importInfo.PathAst.Extent.EndOffset - $importInfo.ImportAst.Extent.StartOffset
                        # replace Import-Module statement path only
                        Value  = '(New-Module -ScriptBlock ($ExecutionContext.SessionState.PSVariable.GetValue("__PSBUNDLE_MODULES__"))[' + $importId + '])'
                    })
            }
            elseif ($importInfo.type -eq 'using') {
                $replacements.Add(@{
                        Start  = $importInfo.ImportAst.Extent.StartOffset
                        Length = $importInfo.ImportAst.Extent.EndOffset - $importInfo.ImportAst.Extent.StartOffset
                        # replace whole "using module <path>" statement
                        Value  = 'Import-Module (New-Module -ScriptBlock ($ExecutionContext.SessionState.PSVariable.GetValue("__PSBUNDLE_MODULES__"))[' + $importId + ']) -Force -DisableNameChecking'
                    })
            }
 
            
        }

        return $replacements
    }
}