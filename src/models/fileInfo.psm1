using module ..\models\bundlerConfig.psm1
using namespace System.Management.Automation.Language

class FileInfo {
    [string]$id
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

    FileInfo ([string]$filePath, [BundlerConfig]$config, [bool]$isEntry = $false, [hashtable]$consumerInfo = $null) {
        $this._config = $config
        $fileContent = $this.GetFileContent($filePath, $consumerInfo)

        $this.id = [Guid]::NewGuid().ToString()
        $this.path = $filePath
        $this.isEntry = $isEntry
        $this.ast = $fileContent.ast
        $this.tokens = $fileContent.tokens

        $this.LinkToConsumer($consumerInfo)
        $this.ResolveHederSrc()
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
            File = $this
            PathAst = $consumerInfo.pathAst
            ImportAst = $consumerInfo.importAst
            Type = $consumerInfo.type
        }   
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
}