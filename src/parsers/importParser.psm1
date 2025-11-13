using module ..\models\bundlerConfig.psm1
using module ..\models\fileInfo.psm1
using module ..\helpers\astHelpers.psm1

using namespace System.Management.Automation.Language

Class ImportParser {
    [BundlerConfig]$_config
    [AstHelpers]$_astHelper

    ImportParser ([BundlerConfig]$Config) {
        $this._config = $Config
        $this._astHelper = [AstHelpers]::new()
    }
    
    [hashtable[]]ParseFile([FileInfo]$file) {
        $result = @()
        $result += $this.ParseImportModule($file)
        $result += $this.ParseUsingModuleImports($file)
        $result += $this.ParseDotImports($file)
        $result += $this.ResolveAmpersandImports($file)
        return $result
    }

    # process "Import-Module" (like: Import-Module "file.psm1")
    [hashtable[]]ParseImportModule([FileInfo]$file) {
        $result = @()

        $commandAsts = $file.Ast.FindAll( { $args[0] -is [CommandAst] -and $args[0].CommandElements -and $args[0].CommandElements[0].Value -eq "Import-Module" }, $true)
        if (-not $commandAsts) { return $result }
        
        $type = "module"
        foreach ($commandAst in $commandAsts) {
            $paths = $this.ParseImportModuleCommandAst($commandAst)
            foreach ($pathInfo in $paths) {
                $result += @{
                    Path      = $this.ResolveImportPath($file, $type, $pathInfo.Path)
                    PathAst   = $pathInfo.Ast
                    ImportAst = $commandAst
                    Type      = $type
                }
            }
        }
        
        return $result
    }

    # Get path properties from Import-Module CommandAst
    [hashtable[]]ParseImportModuleCommandAst([CommandAst]$commandAst) {
        $parameters = $this._astHelper.GetCommandAstParamsAst($commandAst)
        if (-not $parameters) { return @() }

        for ($i = 0; $i -lt $parameters.Count; $i++) {
            $param = $parameters[$i]
            if (($i -eq 0 -and -not $param.name) -or $param.name -eq "Name") {
                # first parameter without name or parameter -Name
                $paths = $this.ParseParameterValueAst($param.value)
                return $paths
            }
        }

        return @()
    }

    # get path value property from parameter value AST
    [hashtable[]]ParseParameterValueAst([ast]$parameter) {
        $result = @()
        $elements = @()
        if ($parameter -is [StringConstantExpressionAst] -or $parameter -is [ExpandableStringExpressionAst]) { $elements = @($parameter) }
        elseif ($parameter -is [ArrayLiteralAst] -and $parameter.Elements) { $elements = $parameter.Elements }
        else { return $result }

        foreach ($element in $elements) {
            if (($element -isnot [StringConstantExpressionAst] -and $element -isnot [ExpandableStringExpressionAst]) -or -not $this.IsStrIsPsFilePath($element.Value)) { continue }
            $result += @{
                Path = $element.Value
                Ast  = $element
            }
            
        }

        return $result
    }

    # TODO: implement .psd1 mainfest file parsing
    [bool]IsStrIsPsFilePath([string]$str) {
        return  $str.EndsWith(".ps1") -or $str.EndsWith(".psm1")
    }


    # process "using module" (like: using module "file.psm1")
    [hashtable[]]ParseUsingModuleImports([FileInfo]$file) {
        $result = @()
        $usingStatements = $file.Ast.UsingStatements

        if (-not $usingStatements) { return $result }
        $type = "using"
        foreach ($usingStatement in $usingStatements) {
            if ($usingStatement.UsingStatementKind -ne "Module") { continue }
            
            $result += @{
                Path      = $this.ResolveImportPath($file, $type, $usingStatement.Name.Value) 
                PathAst   = $usingStatement.Name
                ImportAst = $usingStatement
                Type      = $type
            }
        }

        return $result
    }

    # process "Dot commands" (like: . "file.ps1")
    [hashtable[]]ParseDotImports([FileInfo]$file) {
        $result = @()

        $commandAsts = $file.Ast.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].InvocationOperator -eq "Dot" }, $true)
        if (-not $commandAsts) { return $result }
        
        $type = "dot"
        foreach ($commandAst in $commandAsts) {
            if (-not $commandAst.CommandElements) { continue }
            $importPath = $commandAst.CommandElements[0].Value
            $result += @{
                Path      = $this.ResolveImportPath($file, $type, $importPath)
                PathAst   = $commandAst.CommandElements[0]
                ImportAst = $commandAst
                Type      = $type
            }
        }
        
        return $result
    }

    # process "Ampersand commands" (like: & "file.ps1")
    [string[]]ResolveAmpersandImports([FileInfo]$file) {
        $result = @()

        $commandAsts = $file.Ast.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].InvocationOperator -eq "Ampersand" }, $true)
        if (-not $commandAsts) { return $result }
        
        $type = "ampersand"
        foreach ($commandAst in $commandAsts) {
            if (-not $commandAst.CommandElements) { continue }
            $importPath = $commandAst.CommandElements[0].Value
            $result += @{
                Path      = $this.ResolveImportPath( $file, $type, $importPath)
                PathAst   = $commandAst.CommandElements[0]
                ImportAst = $commandAst
                Type      = $type
            }
        }
        
        return $result
    }

    #TODO: move "using namespaces" part to bulder module
    [string[]]ResolveImports2() {
        $usingStatements = $this.Ast.UsingStatements

        $result = @()

        # process "using" (like: using module "file.psm1")
        if ($usingStatements) {
            foreach ($usingStatement in $usingStatements) {
                if ($usingStatement.UsingStatementKind -eq "Namespace") { 
                    $this.namespaces[$usingStatement.Name.Value] = $true
                    $this.replacements += @{start = $usingStatement.Extent.StartOffset; Length = $usingStatement.Extent.EndOffset - $usingStatement.Extent.StartOffset; value = "" }
                }
                elseif ($usingStatement.UsingStatementKind -eq "Module") {
                    $result += @{
                        path = $this.ResolvePath($usingStatement.Name.Value) 
                        type = "UsingModule"
                    }
                    $this.replacements += @{start = $usingStatement.Extent.StartOffset; Length = $usingStatement.Extent.EndOffset - $usingStatement.Extent.StartOffset; value = "" }
                }
            }
        }

        # process "dot commands" (like: . "file.ps1")
        $dotCommands = $this.Ast.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].InvocationOperator -eq "Dot" }, $false)
        if ($dotCommands) {
            foreach ($dotCommand in $dotCommands) {
                if (-not $dotCommand.CommandElements) { continue }
                $importPath = $dotCommand.CommandElements[0].Value
                $result += $this.ResolvePath($importPath)
                $this.replacements += @{start = $dotCommand.Extent.StartOffset; Length = $dotCommand.Extent.EndOffset - $dotCommand.Extent.StartOffset; value = "" }
            }
        }
        
        return $result
    }

    [string] ResolveImportPath(
        [FileInfo]$caller,                             # caller file info
        [string] $ImportType,                          # import kind ("dot", "ampersand", "module", "using")
        [string] $ImportPath                           # path string from the import statement
    ) {
        if (-not $ImportPath) { return $null }

        $callerPath = $caller.path
        $projectRoot = $this._config.projectRoot

        $Resolved = $ImportPath

        $callerDir = [System.IO.Path]::GetDirectoryName($callerPath)
        $pathVars = @{
            "PSScriptRoot" = $callerDir
            "PWD"          = $projectRoot         # emulate session path
            "HOME"         = [Environment]::GetFolderPath('UserProfile')
        }

        # Expand ${PSScriptRoot} or $PSScriptRoot form first to avoid partial matches
        foreach ($key in $pathVars.Keys) {
            $value = $pathVars[$key]
            $Resolved = $Resolved -replace ("\$\{?$key\}?"), $value
        }

        # Tilde (~) expansion at the start of the path
        if ($Resolved -match '^(~)([\\/]|$)') { $Resolved = $Resolved -replace '^~', $pathVars['HOME'] }

        # --- absolute? normalize and return -------------------------------------
        if ([System.IO.Path]::IsPathRooted($Resolved)) { return [System.IO.Path]::GetFullPath($Resolved) }

        # --- choose base dir per import semantics (bundler rules) ---------------
        # dot, ampersand, module -> session PWD; in bundler we emulate it as ProjectRoot
        # using -> relative to the file where it's written
        $baseDir = switch ($ImportType) {
            'using' { $callerDir }
            'dot' { $projectRoot }
            'ampersand' { $projectRoot }
            'module' { $projectRoot }
        }

        # --- combine and normalize ----------------------------------------------
        $combined = [System.IO.Path]::Combine($baseDir, $Resolved)
        return [System.IO.Path]::GetFullPath($combined)
    }


    # TODO: Remove
    [string]ResolvePath_old([string]$ImportPath) {
        # Resolve script root path
        $baseDir = Split-Path -Path $this.path -Parent

        # Create a map with environment variables
        $context = @{
            PSScriptRoot = $baseDir
            PWD          = (Get-Location).Path
            HOME         = [Environment]::GetFolderPath('UserProfile')
        }

        # Substitute variables like $PSScriptRoot, $HOME and so on
        $resolved = $ImportPath
        foreach ($key in $context.Keys) {
            $resolved = $resolved -replace ("\$" + $key), [regex]::Escape($context[$key])
        }

        # Convert relative path to absolute
        if (-not [System.IO.Path]::IsPathRooted($resolved)) {
            $resolved = Join-Path -Path $baseDir -ChildPath $resolved
        }

        # Dots and slashes expansion
        $resolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $resolved -ErrorAction SilentlyContinue).Path)

        return $resolved
    }
}