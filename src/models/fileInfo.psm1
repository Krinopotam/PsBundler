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

        $this.id = [Guid]::NewGuid().ToString("N")
        $this.path = $filePath
        $this.isEntry = $isEntry
        
        $fileContent = $this.GetFileContent($filePath, $consumerInfo)
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
            if ($this._config.stripComments) { $source = $this.stripComments($source) }

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

    [string]stripComments([string]$source) {
        $errors = $null
        $tokensVal = $null
        [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokensVal, [ref]$errors)

        $replacements = [System.Collections.ArrayList]::new()
        $tokenKind = [System.Management.Automation.Language.TokenKind]

        $fileBegin = $true
        for ($i = 0; $i -lt $tokensVal.Count; $i++) {
            $token = $tokensVal[$i]
            if ( $this._config.keepHeaderComments -and $this.isEntry -and $fileBegin -and ($token.Kind -eq $tokenKind::Comment -or $token.Kind -eq $tokenKind::NewLine)) { continue }

            $fileBegin = $false

            if ($token.Kind -ne $tokenKind::Comment) { continue }

            $replacements.Add(@{start = $token.Extent.StartOffset; Length = $token.Extent.EndOffset - $token.Extent.StartOffset; value = "" })
   
            if (($i - 1) -gt 0 -and $tokensVal[$i - 1].Kind -eq $tokenKind::NewLine) {
                $replacements.Add(@{start = $tokensVal[$i - 1].Extent.StartOffset; Length = $tokensVal[$i - 1].Extent.EndOffset - $tokensVal[$i - 1].Extent.StartOffset; value = "" })
            }
        }

        # WORKAROUND: System.Collections.ArrayList may unfold hashtables when sorting. So we have to convert it to array 
        $sorted = ([hashtable[]]$replacements) | Sort-Object { $_['Start'] } -Descending

        $sb = [System.Text.StringBuilder]::new($source)
        foreach ($r in $sorted) {
            $sb.Remove($r.Start, $r.Length)
        }
        return $sb.ToString()
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