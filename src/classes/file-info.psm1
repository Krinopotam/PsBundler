using module .\bundler-config.psm1
using namespace System.Management.Automation.Language

class FileInfo {
    [string]$path
    [hashtable]$consumers = @{}
    [hashtable]$imports = @{}
    [bool]$isEntry = $false
    [Ast]$ast = $null
    [System.Collections.ObjectModel.ReadOnlyCollection[System.Management.Automation.Language.Token]]$tokens = $null
    [hashtable]$namespaces = @{}
    [string]$topHeader = ""
    [string]$paramBlock = ""
    [hashtable[]]$replacements = @()
    [string]$clearSource = ""

    [BundlerConfig]$_config

    FileInfo ([string]$filePath, [BundlerConfig]$config, [bool]$isEntry = $false, [FileInfo]$consumer = $null, [string]$importType = $null) {
        $this._config = $config
        $fileContent = $this.GetFileContent($filePath, $consumer)

        $this.path = $filePath
        $this.isEntry = $isEntry
        $this.ast = $fileContent.ast
        $this.tokens = $fileContent.tokens

        $this.LinkToConsumer($consumer, $importType)
        $this.ResolveHederSrc()

        if ($this._config.stripComments) { $this.ResolveComments() }
    }

    [hashtable]GetFileContent([string]$filePath, [FileInfo]$consumer = $null) {
        try {

            if (-not (Test-Path $filePath)) {
                $consumerInfo = ""
                if ($consumer) { $consumerInfo = "imported by $($consumer.path)" }
                Throw "File not found: $($filePath) $consumerInfo"
            }

            $source = Get-Content $filePath -Raw 

            $errors = $null
            $tokensVal = $null
            $astVal = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokensVal, [ref]$errors)
            #$realErrors = $errors | Where-Object { $_.ErrorId -notin @('TypeNotFound', 'VariableNotFound', 'CommandNotFound') }
            $realErrors = $errors | Where-Object { $_.ErrorId -notin @('TypeNotFound') }

            if ($realErrors.Count -gt 0) {
                Write-Host "Found syntax errors in script '$filePath':" -ForegroundColor Red
                foreach ($err in $realErrors) {
                    $lineNum = $source.Substring(0, $err.Extent.StartOffset).Split("`n").Count
                    Write-Host ("[{0}] {1}" -f $lineNum, $err.Message) -ForegroundColor Yellow
                }
                throw "Syntax errors in script."
            }

            return @{
                tokens = $tokensVal
                ast    = $astVal
            }
        }
        catch {
            Write-Error "Error parsing file: $($_.Exception.Message)"
            exit
        }
    }

    [void]LinkToConsumer([FileInfo]$consumer, [string]$importType) {
        if (-not $consumer) { return }
        $this.consumers[$consumer.path] = {
            file = $consumer
            type = $importType
        }

        $consumer.imports[$this.path] = {
            file = $this
            type = $importType
        }   
    }

    [string[]]ResolveImports() {



        
        return $result
    }

    # process "Import-Module" (like: Import-Module "file.psm1")
    [string[]]ResolveImportModuleImports([string]$importPath) {
        $result = @()

        $importCommands = $this.Ast.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].CommandElements -and $args[0].CommandElements[0].Value -eq "Import-Module" }, $false)
        if (-not $importCommands) { return $result }
        
        $type = "ImportModule"
        foreach ($importCommand in $importCommands) {
            if ($importCommand.CommandElements.length -lt 2) { continue }

            $importPath = $importCommand.CommandElements[0].Value
            $result += @{
                path = $this.ResolveImportPath($importPath)
                type = $type
                ast  = $importCommand
            }
        }
        
        return $result
    }

    [string[]]ParsePathFromImportCommand([ast]$importAst) {
        if ($importAst.CommandElements.length -lt 2) { return @() }

        function ParseParameter([ast]$parameter) {
            if ($parameter -is [StringConstantExpressionAst] -and $parameter.Value) { return @($parameter.Value) }
            if ($parameter -is [ArrayLiteralAst] -and $parameter.Elements) { 
                $result = @()
                foreach ($element in $parameter.Elements) {
                    if ($element -is [StringConstantExpressionAst] -and $element.Value) { $result += $element.Value }
                }
            }
        }
        
        # first parameter is string without parameter name (like Import-Module "file.psm1")
        $result = ParseParameter($importAst.CommandElements[1])
        if ($result) { return $result } 

        for ($i = 1; $i -lt $importAst.CommandElements.Count; $i++) {
            if (-not ($importAst.CommandElements[$i].Value -is [CommandParameterAst]) -or $i -ge $importAst.CommandElements.Count) { continue }
            $parameterAst = $importAst.CommandElements[$i].Value
            if ($parameterAst.ParameterName -ne "Name" ) { continue }
            
            $parameter = $importAst.CommandElements[$i + 1]
            return ParseParameter($parameter)
        }

        return @()
    }

    # process "using module" (like: using module "file.psm1")
    [string[]]ResolveUsingModuleImports([string]$importPath) {
        $result = @()
        $usingStatements = $this.Ast.UsingStatements

        if (-not $usingStatements) { return $result }
        $type = "UsingModule"
        foreach ($usingStatement in $usingStatements) {
            if ($usingStatement.UsingStatementKind -ne "Module") { continue }
            
            $result += @{
                path = $this.ResolveImportPath($usingStatement.Name.Value) 
                type = $type
                ast  = $usingStatement
            }
        }

        return $result
    }

    # process "Dot commands" (like: . "file.ps1")
    [string[]]ResolveDotImports() {
        $result = @()

        $dotCommands = $this.Ast.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].InvocationOperator -eq "Dot" }, $false)
        if (-not $dotCommands) { return $result }
        
        $type = "DotCommand"
        foreach ($dotCommand in $dotCommands) {
            if (-not $dotCommand.CommandElements) { continue }
            $importPath = $dotCommand.CommandElements[0].Value
            $result += @{
                path = $this.ResolveImportPath($importPath)
                type = $type
                ast  = $dotCommand
            }
        }
        
        return $result
    }

    # process "Ampersand commands" (like: & "file.ps1")
    [string[]]ResolveAmpersandImports() {
        $result = @()

        $ampCommands = $this.Ast.FindAll( { $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].InvocationOperator -eq "Ampersand" }, $false)
        if (-not $ampCommands) { return $result }
        
        $type = "AmpCommand"
        foreach ($ampCommand in $ampCommands) {
            if (-not $ampCommand.CommandElements) { continue }
            $importPath = $ampCommand.CommandElements[0].Value
            $result += @{
                path = $this.ResolveImportPath($importPath)
                type = $type
                ast  = $ampCommand
            }
        }
        
        return $result
    }


    # TODO: move to builder mode
    # -- Main entry file can have commands that must be placed at the top. This function will extract them
    ResolveHederSrc() {
        $fileAst = $this.ast
        $source = $fileAst.Extent.Text

        # extract header
        if ($this.isEntry -and $this._config.keepHeaderComments) {
            $tokenKind = [System.Management.Automation.Language.TokenKind]
            $header = ""
            $headerEnd = 0
            foreach ($token in $this.tokens) {
                if ($token.Kind -ne $tokenKind::Comment -and $token.Kind -ne $tokenKind::NewLine) { break }
                $headerEnd = $token.Extent.EndOffset
                $header += $token.Extent.Text
            }
            if ($header) {
                $this.replacements += @{start = 0; Length = $headerEnd; value = "" }
                $this.topHeader = $header.Trim()
            }
        }
        
        # extract param block
        if ($fileAst.ParamBlock) { 
            if (-not $this.IsEntry) { Throw "File '$($this.path)' has a param block. Only entry files can have param block" }

            $startOffset = $fileAst.ParamBlock.Extent.StartOffset
            $endOffset = $fileAst.ParamBlock.Extent.EndOffset

            if ($fileAst.ParamBlock.Attributes) { 
                $startOffset = $fileAst.ParamBlock.Attributes[0].Extent.StartOffset
            }

            $this.Replacements += @{start = $startOffset; Length = $endOffset - $startOffset; value = "" }
            $this.paramBlock = ($source.Substring($startOffset, $endOffset - $startOffset)).Trim()
        }
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
                        path = $this.ResolveImportPath($usingStatement.Name.Value) 
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
                $result += $this.ResolveImportPath($importPath)
                $this.replacements += @{start = $dotCommand.Extent.StartOffset; Length = $dotCommand.Extent.EndOffset - $dotCommand.Extent.StartOffset; value = "" }
            }
        }
        
        return $result
    }

    [string]ResolveImportPath([string]$ImportPath) {
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

    [void]ResolveComments() {
        $tokenKind = [System.Management.Automation.Language.TokenKind]

        for ($i = 0; $i -lt $this.tokens.Count; $i++) {
            $token = $this.tokens[$i]
            if ($token.Kind -ne $tokenKind::Comment) { continue }

            $this.replacements += @{start = $token.Extent.StartOffset; Length = $token.Extent.EndOffset - $token.Extent.StartOffset; value = "" }
   
            if ($i - 1 -gt 0 -and $this.tokens[$i - 1].Kind -eq $tokenKind::NewLine) {
                $this.replacements += @{start = $this.tokens[$i - 1].Extent.StartOffset; Length = $this.tokens[$i - 1].Extent.EndOffset - $this.tokens[$i - 1].Extent.StartOffset; value = "" }
            }
        }
    }
}