using module ..\models\bundlerConfig.psm1
using module ..\models\fileInfo.psm1
using module ..\helpers\astHelpers.psm1

using namespace System.Management.Automation.Language

class Replacer {
    [BundlerConfig]$_config
    [AstHelpers]$_astHelper

    Replacer([BundlerConfig]$config) {
        $this._config = $config
        $this._astHelper = [AstHelpers]::new()
    }

    [hashtable]getReplacements([System.Collections.Specialized.OrderedDictionary]$importsMap) {
        $replacementsMap = @{}
        $namespaces = [System.Collections.Specialized.OrderedDictionary]::new()
        $addTypes = [System.Collections.Specialized.OrderedDictionary]::new()
        $classes = [System.Collections.Specialized.OrderedDictionary]::new()
        $headerComments = ""
        $paramBlock = ""

        foreach ($file in $importsMap.Values) {
            $replacements = [System.Collections.ArrayList]::new()
            $replacementsMap[$file.id] = $replacements

            if ($file.isEntry) { 
                $headerComments = $this.fillHeaderCommentsReplacements($file, $replacements) 
                $paramBlock = $this.fillRootParamsReplacements($file, $replacements)
            }

            # Fill import replacements
            $this.fillImportReplacements($file, $replacements)
            
            # Namespaces replacements
            $this.fillNamespacesReplacements($file, $namespaces, $replacements)

            # Add-Types replacements
            $this.fillAddTypesReplacements($file, $addTypes, $replacements)

            # Classes replacements
            $this.fillClassesReplacements($file, $classes, $replacements)
        }

        return @{
            headerComments  = $headerComments
            namespaces      = $namespaces
            paramBlock      = $paramBlock
            addTypes        = $addTypes
            classes         = $classes
            replacementsMap = $replacementsMap
        }
    }

    # Fill import replacements
    [void]fillImportReplacements([FileInfo]$file, [System.Collections.ArrayList]$replacements) {
        $processedImports = @{}

        foreach ($importInfo in $file.imports.Values) {
            $importFile = $importInfo.file
            $importId = $importFile.id
            $value = ""
            $replacement = @{
                Start  = $importInfo.ImportAst.Extent.StartOffset
                Length = $importInfo.ImportAst.Extent.EndOffset - $importInfo.ImportAst.Extent.StartOffset
                # replace whole dot-import statement
                Value  = $value
            }

            $replacements.Add($replacement)

            # Not import types (Classes, interfaces, structs, enums)
            if ($importFile.typesOnly) { continue }

            if ($importInfo.type -eq 'dot') {
                $replacement.Value = '. $global:' + $this._config.modulesSourceMapVarName + '["' + $importId + '"]' 
            }
            elseif ($importInfo.type -eq 'ampersand') {
                $replacement.Value = '& $global:' + $this._config.modulesSourceMapVarName + '["' + $importId + '"]' 
            }
            elseif ($importInfo.type -eq 'using') {
                $replacement.Value = 'Import-Module (New-Module -ScriptBlock $' + $this._config.modulesSourceMapVarName + '["' + $importId + '"] -ArgumentList $global:' + $this._config.modulesSourceMapVarName + ') -Force -DisableNameChecking' 
            }
            elseif ($importInfo.type -eq 'module') {
                # Import-Module can be passed a paths array. We replace one import to many imports.
                $importParams = $this._astHelper.GetNamedParametersMap($importInfo.ImportAst)
                $importParams["Force"] = $null
                $importParams["DisableNameChecking"] = $null
                <#                 if (-not $importParams.Contains("Name")) {
                     $importParams["Name"] = [System.IO.Path]::GetFileNameWithoutExtension($file.path) } #>
                $paramsStr = $this._astHelper.ConvertParamsAstMapToString($importParams)

                $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($importInfo.File.Path)
                #$value = 'Import-Module (New-Module -Name "' + $moduleName + '" -ScriptBlock $' + $this._config.modulesSourceMapVarName + '["' + $importId + '"] -ArgumentList $script:' + $this._config.modulesSourceMapVarName + ')' + $paramsStr
                
                $createModule = '(& { $mod = New-Object System.Management.Automation.PSModuleInfo($' + $this._config.modulesSourceMapVarName + '["' + $importId + '"])'
                $createModule += [Environment]::NewLine + '    $flags  = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic'
                $createModule += [Environment]::NewLine + '    $setName = [System.Management.Automation.PSModuleInfo].GetMethod("SetName", $flags)'
                $createModule += [Environment]::NewLine + '    $setName.Invoke($mod, @("' + $moduleName + '")) | Out-Null'
                $createModule += [Environment]::NewLine + '    $mod })'

                $value = 'Import-Module ' + $createModule + $paramsStr

                if ($processedImports.ContainsKey($importInfo.ImportAst)) {
                    $replacement = $processedImports[$importInfo.ImportAst]
                    $replacement.Value += [Environment]::NewLine + $value
                }
                else {
                    $replacement.Value = $value
                }
            } 
        }
    }

    # Fill replacements for namespaces
    [void]fillNamespacesReplacements([FileInfo]$file, [System.Collections.Specialized.OrderedDictionary]$namespaces, [System.Collections.ArrayList]$replacements) {
        $usingStatements = $file.Ast.FindAll( { $args[0] -is [UsingStatementAst] -and $args[0].UsingStatementKind -eq "Namespace" }, $false)
        foreach ($usingStatement in $usingStatements) {
            $namespaces[$usingStatement.Name.Value] = "using namespace $($usingStatement.Name.Value)"
            $replacements.Add(@{start = $usingStatement.Extent.StartOffset; Length = $usingStatement.Extent.EndOffset - $usingStatement.Extent.StartOffset; value = "" })
        }
    }

    # Fill replacements for Add-Type
    [void]fillAddTypesReplacements([FileInfo]$file, [System.Collections.Specialized.OrderedDictionary]$addTypes, [System.Collections.ArrayList]$replacements) {
        $usingStatements = $file.Ast.FindAll( { $args[0] -is [CommandAst] -and $args[0].GetCommandName() -eq "Add-Type" }, $false)
        foreach ($usingStatement in $usingStatements) {
            $text = $usingStatement.Extent.Text
            $addTypes[$text] = $text
            $replacements.Add(@{start = $usingStatement.Extent.StartOffset; Length = $usingStatement.Extent.EndOffset - $usingStatement.Extent.StartOffset; value = "" })
        }
    }

    # Fill classes replacements
    [void]fillClassesReplacements([FileInfo]$file, [System.Collections.Specialized.OrderedDictionary]$classes, [System.Collections.ArrayList]$replacements) {
        $typeDefinitions = $file.Ast.FindAll( { $args[0] -is [TypeDefinitionAst] }, $false)
        foreach ($typeDefinition in $typeDefinitions) {
            if ($classes.Contains($typeDefinition.Name)) { Write-Host "        Duplicate class name: '$($typeDefinition.Name)' in file: $($file.path)" -ForegroundColor Orange }
            $classes[$typeDefinition.Name] = $typeDefinition.Extent.Text
            $replacements.Add(@{start = $typeDefinition.Extent.StartOffset; Length = $typeDefinition.Extent.EndOffset - $typeDefinition.Extent.StartOffset; value = "" })
        }
    }

    # Fill replacements and extract header comments
    [string]fillHeaderCommentsReplacements([FileInfo]$file, [System.Collections.ArrayList]$replacements) {
        if (-not $file.isEntry -or -not $this._config.keepHeaderComments) { return "" }
        $tokenKind = [System.Management.Automation.Language.TokenKind]
        $header = ""
        $headerEnd = 0
        foreach ($token in $file.tokens) {
            if ($token.Kind -ne $tokenKind::Comment -and $token.Kind -ne $tokenKind::NewLine) { break }
            $headerEnd = $token.Extent.EndOffset
            $header += $token.Extent.Text
        }
        if ($header) {
            $replacements.Add(@{start = 0; Length = $headerEnd; value = "" })
            return $header.Trim()
        }

        return ""
    }

    # Fill replacements and extract param block for entry file
    [string]fillRootParamsReplacements([FileInfo]$file, [System.Collections.ArrayList]$replacements) {
        if (-not $file.isEntry -or -not $file.Ast.ParamBlock) { return "" }
        $fileAst = $file.Ast
        $source = $fileAst.Extent.Text

        $startOffset = $fileAst.ParamBlock.Extent.StartOffset
        $endOffset = $fileAst.ParamBlock.Extent.EndOffset

        if ($fileAst.ParamBlock.Attributes) { 
            $startOffset = $fileAst.ParamBlock.Attributes[0].Extent.StartOffset
        }

        $replacements.Add(@{start = $startOffset; Length = $endOffset - $startOffset; value = "" })
        return ($source.Substring($startOffset, $endOffset - $startOffset)).Trim()
    }
}