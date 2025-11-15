using module ..\models\bundlerConfig.psm1
using namespace System.Management.Automation.Language

Class FileInfo {
    # App config
    [BundlerConfig]$_config

    # file unique id
    [string]$id
    # file full path
    [string]$path
    # File consumers inf @{[FileInfo]File, [Ast]PathAst, [Ast]ImportAst, [string]Type}o
    [hashtable]$consumers = @{}
    # File imports info @{[FileInfo]File, [Ast]PathAst, [Ast]ImportAst, [string]Type}
    [hashtable]$imports = @{}
    # Is file entry
    [bool]$isEntry = $false
    # File Ast
    [Ast]$ast = $null
    # File tokens
    [System.Collections.ObjectModel.ReadOnlyCollection[System.Management.Automation.Language.Token]]$tokens = $null
    # Is file contains only types (classes, interfaces, structs, enums)
    [bool]$typesOnly

    FileInfo ([string]$filePath, [BundlerConfig]$config, [bool]$isEntry = $false, [hashtable]$consumerInfo = $null) {
        $this._config = $config
        $fileContent = $this.GetFileContent($filePath, $consumerInfo)

        $this.id = [Guid]::NewGuid().ToString()
        $this.path = $filePath
        $this.isEntry = $isEntry
        $this.ast = $fileContent.ast
        $this.tokens = $fileContent.tokens
        $this.typesOnly = $this.IsFileContainsTypesOnly()
        $this.LinkToConsumer($consumerInfo)
    }

    [hashtable]GetFileContent([string]$filePath, [hashtable]$consumerInfo = $null) {
        try {

            if (-not (Test-Path $filePath)) {
                $consumerStr = ""
                if ($consumerInfo) { $consumerStr = "imported by $($consumerInfo.file.path)" }
                Throw "File not found: $($filePath) $consumerStr"
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

    [void]LinkToConsumer([hashtable]$consumerInfo) {
        if (-not $consumerInfo) { return }
        $this.consumers[$consumerInfo.file.path] = $consumerInfo

        $consumerInfo.file.imports[$this.path] = @{
            File      = $this
            PathAst   = $consumerInfo.pathAst
            ImportAst = $consumerInfo.importAst
            Type      = $consumerInfo.type
        }   
    }

    [bool]IsFileContainsTypesOnly() {
        $types = $this.Ast.FindAll( { $args[0] -is [TypeDefinitionAst] }, $false)
        if (-not $types) { return $false }

        $varsAndFunctions = $this.Ast.FindAll( {
                param($node)

                #WORKAROUND: FindAll with nested parameter $false ignores nested scriptblocks only, and finds all nodes within class
                # So we need manually check if node is inside class
                $p = $node.Parent
                while ($null -ne $p) {
                    if ($p -is [TypeDefinitionAst]) { return $false }
                    $p = $p.Parent
                }

                return $node -is [AssignmentStatementAst] -or $node -is [FunctionDefinitionAst]
            }, $false)
        if ($varsAndFunctions) { return $false }

        return $true
    }
}