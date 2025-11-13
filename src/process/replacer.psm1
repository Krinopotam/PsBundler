using module ..\models\bundlerConfig.psm1
using module ..\models\fileInfo.psm1
using module ..\helpers\astHelpers.psm1

Class Replacer {
    [BundlerConfig]$_config
    [AstHelpers]$_astHelper

    Replacer([BundlerConfig]$config) {
        $this._config = $config
        $this._astHelper = [AstHelpers]::new()
    }

    [System.Collections.ArrayList]getReplacements([System.Collections.Specialized.OrderedDictionary]$importsMap) {
        $replacements = [System.Collections.ArrayList]::new()

        foreach ($file in $importsMap.Values) {
            # Import replacements
            $importReplacements = $this.getImportReplacements($file)
            $replacements.AddRange($importReplacements)

            # Comment removals
            if ($this._config.stripComments) {
                $commentReplacements = $this.getCommentsReplacements($file)
                $replacements.AddRange($commentReplacements)
            }            
        }

        return $replacements
    }

    [System.Collections.ArrayList]getImportReplacements([FileInfo]$file) {
        $replacements = [System.Collections.ArrayList]::new()

        $processedImports = @{}

        foreach ($importInfo in $file.imports.Values) {
            $importFile = $importInfo.file
            $importId = $importFile.id
            if ($importInfo.type -eq 'dot') {
            
                $replacements.Add(@{
                        Start  = $importInfo.ImportAst.Extent.StartOffset
                        Length = $importInfo.ImportAst.Extent.EndOffset - $importInfo.PathAst.Extent.StartOffset
                        # replace whole dot-import statement
                        Value  = 'Invoke-Expression ($ExecutionContext.SessionState.PSVariable.GetValue("__PSBUNDLE_MODULES__"))[' + $importId + '].toString()'
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
            elseif ($importInfo.type -eq 'using') {
                $replacements.Add(@{
                        Start  = $importInfo.ImportAst.Extent.StartOffset
                        Length = $importInfo.ImportAst.Extent.EndOffset - $importInfo.ImportAst.Extent.StartOffset
                        # replace whole "using module <path>" statement
                        Value  = 'Import-Module (New-Module -ScriptBlock ($ExecutionContext.SessionState.PSVariable.GetValue("__PSBUNDLE_MODULES__"))[' + $importId + ']) -Force -DisableNameChecking'
                    })
            }
            elseif ($importInfo.type -eq 'module') {
                # Import-Module can be passed a paths array. We replace one import to many imports.
                $importParams = $this._astHelper.GetNamedParametersMap($importInfo.ImportAst)
                $importParams["Force"] = $null
                $importParams["DisableNameChecking"] = $null
                $paramsStr = $this._astHelper.ConvertParamsAstMapToString($importParams)

                $value = 'Import-Module (New-Module -ScriptBlock ($ExecutionContext.SessionState.PSVariable.GetValue("__PSBUNDLE_MODULES__"))[' + $importId + ']) ' + $paramsStr
                if ($processedImports.ContainsKey($importInfo.ImportAst)) {
                    $replacement = $processedImports[$importInfo.ImportAst]
                    $replacement.Value += "`r`n" + $value
                }
                else {
                    $replacement = @{
                        Start  = $importInfo.PathAst.Extent.StartOffset
                        Length = $importInfo.PathAst.Extent.EndOffset - $importInfo.ImportAst.Extent.StartOffset
                        # replace Import-Module statement path only
                        Value  = $value
                    }
                    $processedImports[$importInfo.ImportAst] = $replacement
                    $replacements.Add($replacement)
                }
            } 
        }

        return $replacements
    }

    [System.Collections.ArrayList]getCommentsReplacements([FileInfo]$file) {
        $replacements = [System.Collections.ArrayList]::new()
        $tokenKind = [System.Management.Automation.Language.TokenKind]

        for ($i = 0; $i -lt $file.tokens.Count; $i++) {
            $token = $file.tokens[$i]
            if ($token.Kind -ne $tokenKind::Comment) { continue }

            $replacements.Add(@{start = $token.Extent.StartOffset; Length = $token.Extent.EndOffset - $token.Extent.StartOffset; value = "" })
   
            if (($i - 1) -gt 0 -and $file.tokens[$i - 1].Kind -eq $tokenKind::NewLine) {
                $replacements.Add(@{start = $file.tokens[$i - 1].Extent.StartOffset; Length = $file.tokens[$i - 1].Extent.EndOffset - $file.tokens[$i - 1].Extent.StartOffset; value = "" })
            }
        }

        return $replacements
    }
}