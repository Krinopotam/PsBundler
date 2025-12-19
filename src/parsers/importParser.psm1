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
        
        $type = "Module"
        foreach ($commandAst in $commandAsts) {
            $paths = $this.ParseImportModuleCommandAst($commandAst)
            foreach ($pathInfo in $paths) {
                $importPath = $this.ResolveImportPath($file, $type, $pathInfo.Path)
                if (-not $importPath) { continue }
                $result += @{
                    Path      = $importPath
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
        $type = "Using"
        foreach ($usingStatement in $usingStatements) {
            if ($usingStatement.UsingStatementKind -ne "Module") { continue }
            
            $importPath = $this.ResolveImportPath($file, $type, $usingStatement.Name.Value) 
            if (-not $importPath) { continue }

            $result += @{
                Path      = $importPath
                PathAst   = $usingStatement.Name
                ImportAst = $usingStatement
                Type      = $type
            }
        }

        return $result
    }

    # process invocation imports, Dot and Ampersand (like: '& file.ps1' or '. file.ps1')
    [hashtable[]]ParseInvocationImports([FileInfo]$file, [string]$type) {
        $result = @()
        $commandAsts = $null
        if ($type -eq "Dot") { $commandAsts = $file.Ast.FindAll( { $args[0] -is [CommandAst] -and $args[0].InvocationOperator -eq 'Dot' }, $true) }
        elseif ($type -eq "Ampersand") { $commandAsts = $file.Ast.FindAll( { $args[0] -is [CommandAst] -and $args[0].InvocationOperator -eq 'Ampersand' }, $true) }
        else { return $result }
        
        if (-not $commandAsts) { return $result }
        
        foreach ($commandAst in $commandAsts) {
            if (-not $commandAst.CommandElements `
                    -or ($commandAst.CommandElements[0] -isnot [StringConstantExpressionAst] -and $commandAst.CommandElements[0] -isnot [ExpandableStringExpressionAst]) `
                    -or -not $commandAst.CommandElements[0].Value) { continue }
            $importPath = $this.ResolveImportPath($file, $type, $commandAst.CommandElements[0].Value)
            if (-not $importPath) { continue }
            $result += @{
                Path      = $importPath
                PathAst   = $commandAst.CommandElements[0]
                ImportAst = $commandAst
                Type      = $type
            }
        }
        
        return $result
    }

    # process "Dot commands" (like: . "file.ps1")
    [hashtable[]]ParseDotImports([FileInfo]$file) {
        return $this.ParseInvocationImports($file, "Dot")
    }

    # process "Ampersand commands" (like: & "file.ps1")
    [string[]]ResolveAmpersandImports([FileInfo]$file) {
        return $this.ParseInvocationImports($file, "Ampersand")
    }

    [string] ResolveImportPath(
        [FileInfo]$caller,                             # caller file info
        [string] $importType,                          # import kind ("dot", "ampersand", "module", "using")
        [string] $importPath                           # path string from the import statement
    ) {
        if (-not $importPath) { return $null }

        $callerPath = $caller.path
        $projectRoot = $this._config.projectRoot

        $resolved = $importPath

        $callerDir = [System.IO.Path]::GetDirectoryName($callerPath)
        $pathVars = @{
            "PSScriptRoot" = $callerDir
            "PWD"          = $projectRoot         # emulate session path
            "HOME"         = [Environment]::GetFolderPath('UserProfile')
        }

        # Expand ${PSScriptRoot} or $PSScriptRoot form first to avoid partial matches
        foreach ($key in $pathVars.Keys) {
            $value = $pathVars[$key]
            $resolved = $resolved -replace ("\$\{?$key\}?"), $value
        }

        # Tilde (~) expansion at the start of the path
        if ($resolved -match '^(~)([\\/]|$)') { $resolved = $resolved -replace '^~', $pathVars['HOME'] }

        # --- absolute? normalize and return -------------------------------------
        if ([System.IO.Path]::IsPathRooted($resolved)) { return [System.IO.Path]::GetFullPath($resolved) }

        # --- choose base dir per import semantics (bundler rules) ---------------
        # dot, ampersand, module -> session PWD; in bundler we emulate it as ProjectRoot
        # using -> relative to the file where it's written
        $baseDir = switch ($importType) {
            'using' { $callerDir }
            'dot' { $projectRoot }
            'ampersand' { $projectRoot }
            'module' { $projectRoot }
        }

        # --- combine and normalize ----------------------------------------------
        $combined = [System.IO.Path]::Combine($baseDir, $resolved)
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