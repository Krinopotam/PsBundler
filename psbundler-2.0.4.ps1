###################################### PSBundler #########################################
#Author: Zaytsev Maksim
#Version: 2.0.4
#requires -Version 5.1
##########################################################################################

using namespace System.Management.Automation.Language

[CmdletBinding()]
param(
    [string]$myParam
)



### FILE: D:\projects\repo\packages\powerShell\PSBundler\src\classes\path-helpers.psm1 ###

class PathHelpers {
    [bool]IsValidPath([string]$path) {
        try {
            [System.IO.Path]::GetFullPath($path) | Out-Null
            return $true
        }
        catch {
            return $false
        }
    }
}

### FILE: D:\projects\repo\packages\powerShell\PSBundler\src\classes\object-helpers.psm1 ###

class ObjectHelpers {
    
    [object]ConvertToHashtable([object]$inputObject) {
        if ($null -eq $inputObject) { return $null }
        
        if ($inputObject -is [System.Collections.IDictionary]) {
            $output = @{}
            foreach ($key in $inputObject.Keys) {
                $output[$key] = $this.ConvertToHashtable($inputObject[$key])
            }
            return $output
        }
        
        if ($inputObject -is [System.Collections.IEnumerable] -and -not ($inputObject -is [string])) { return $inputObject }
        
        if ($inputObject -is [psobject]) {
            $output = @{}
            foreach ($property in $inputObject.PSObject.Properties) {
                if ($property.IsGettable) {
                    try {
                        $output[$property.Name] = $this.ConvertToHashtable($property.Value)
                    }
                    catch {
                        $output[$property.Name] = $null
                    }
                }
            }
            return $output
        }
        
        return $inputObject
    }
}

### FILE: D:\projects\repo\packages\powerShell\PSBundler\src\classes\bundler-config.psm1 ###

class BundlerConfig {    
    [string]$projectRoot = ".\"    
    [string]$srcRoot = "src"    
    [string]$outDir = "build"    
    [hashtable]$entryPoints = @{}    
    [bool]$addSourceFileNames = $true    
    [bool]$stripComments = $true    
    [bool]$keepHeaderComments = $true         
    [string]$obfuscate = ""

    [ObjectHelpers]$_objectHelpers
    [PathHelpers]$_pathHelpers

    BundlerConfig () {
        $this._objectHelpers = [ObjectHelpers]::New()
        $this._pathHelpers = [PathHelpers]::New()
        $this.Load()
    }

    [void]Load() {        
        $config = @{
            projectRoot        = ".\"          
            srcRoot            = "src"         
            outDir             = "build"       
            entryPoints        = @{}           
            addSourceFileNames = $true         
            stripComments      = $true        
            keepHeaderComments = $true         
            obfuscate          = ""            
        }

        $userConfig = $this.GetConfigFromFile()

        foreach ($key in $userConfig.Keys) { $config[$key] = $userConfig[$key] }
        
        $root = [System.IO.Path]::GetFullPath($config.projectRoot)
        $this.projectRoot = $root
        
        $src = $config.srcRoot
        if (-not $src) { $src = "" }
        if (-not ([System.IO.Path]::IsPathRooted($src))) { $src = Join-Path $root $src }
        $this.srcRoot = [System.IO.Path]::GetFullPath($src)
            
        if (-not $config.outDir) { $config.outDir = "" }
        if (-not ([System.IO.Path]::IsPathRooted($config.outDir))) { $config.outDir = Join-Path $root $config.outDir }
        $this.outDir = [System.IO.Path]::GetFullPath($config.outDir)
        
        if (-not $userConfig.entryPoints -or $userConfig.entryPoints.Count -eq 0) { throw "No entry points found in config" }

        $this.entryPoints = @{}
        foreach ($entryPath in $config.entryPoints.Keys) {
            $bundleName = $config.entryPoints[$entryPath]
            if (-not ($this._pathHelpers.IsValidPath($bundleName))) { throw "Invalid bundle name: $bundleName" }

            $entryAbsPath = [System.IO.Path]::GetFullPath( (Join-Path $src $entryPath))
            $this.entryPoints[$entryAbsPath] = $bundleName
        }

        $this.addSourceFileNames = $config.addSourceFileNames
        $this.stripComments = $config.stripComments
        $this.keepHeaderComments = $config.keepHeaderComments
        $this.obfuscate = ""
        if ($config.obfuscate) {
            if ($config.obfuscate -eq "Natural") { $this.obfuscate = $config.obfuscate } 
            else { $this.obfuscate = "Hard" }
        }
    }

    [PSCustomObject]GetConfigFromFile () {
        $scriptLaunchPath = Get-Location 

        $configPath = Join-Path -Path $scriptLaunchPath -ChildPath 'psbundler.config.json'

        if ((Test-Path $configPath)) {
            try {
                $config = Get-Content $configPath -Raw | ConvertFrom-Json
                $configHashTable = $this._objectHelpers.ConvertToHashtable($config)
                return $configHashTable
            }
            catch {
                throw "Error reading config file: $_.Exception.Message"
            }
        }
    
        throw "Config file not found: $configPath"
    }
}

### FILE: D:\projects\repo\packages\powerShell\PSBundler\src\classes\file-info.psm1 ###

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

    FileInfo ([string]$filePath, [BundlerConfig]$config, [bool]$isEntry = $false, [FileInfo]$consumer = $null) {
        $this._config = $config
        $fileContent = $this.GetFileContent($filePath, $consumer)

        $this.path = $filePath
        $this.isEntry = $isEntry
        $this.ast = $fileContent.ast
        $this.tokens = $fileContent.tokens

        $this.LinkToConsumer($consumer)
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

    [void]LinkToConsumer([FileInfo]$consumer) {
        if (-not $consumer) { return }
        $this.consumers[$consumer.path] = $consumer
        $consumer.imports[$this.path] = $this
    }
    
    ResolveHederSrc() {
        $fileAst = $this.ast
        $source = $fileAst.Extent.Text
        
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

    [string[]]ResolveImports() {
        $usingStatements = $this.Ast.UsingStatements

        $result = @()
        
        if ($usingStatements) {
            foreach ($usingStatement in $usingStatements) {
                if ($usingStatement.UsingStatementKind -eq "Namespace") { 
                    $this.namespaces[$usingStatement.Name.Value] = $true
                    $this.replacements += @{start = $usingStatement.Extent.StartOffset; Length = $usingStatement.Extent.EndOffset - $usingStatement.Extent.StartOffset; value = "" }
                }
                elseif ($usingStatement.UsingStatementKind -eq "Module") {
                    $result += $this.ResolveImportPath($usingStatement.Name.Value)
                    $this.replacements += @{start = $usingStatement.Extent.StartOffset; Length = $usingStatement.Extent.EndOffset - $usingStatement.Extent.StartOffset; value = "" }
                }
            }
        }
        
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
        $baseDir = Split-Path -Path $this.path -Parent
        
        $context = @{
            PSScriptRoot = $baseDir
            PWD          = (Get-Location).Path
            HOME         = [Environment]::GetFolderPath('UserProfile')
        }
        
        $resolved = $ImportPath
        foreach ($key in $context.Keys) {
            $resolved = $resolved -replace ("\$" + $key), [regex]::Escape($context[$key])
        }
        
        if (-not [System.IO.Path]::IsPathRooted($resolved)) {
            $resolved = Join-Path -Path $baseDir -ChildPath $resolved
        }
        
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

### FILE: D:\projects\repo\packages\powerShell\PSBundler\src\classes\bundle-saver.psm1 ###

Class BundleSaver {
    [BundlerConfig]$_config

    BundleSaver ([BundlerConfig]$config) {
        $this._config = $config
    }

    [string]Generate([hashtable]$importsMap, [string]$bundleName) {
        try {
            $entryFile = $this.GetEntryFile($importsMap)
            $bundleName = $this.PrepareBundleName($bundleName, $entryFile)
            $outputPath = Join-Path $this._config.outDir $bundleName
            Write-Host "    Start save bundle at: $outputPath"

            if ((Test-Path $outputPath)) { Remove-Item -Path $outputPath -Force }
            New-Item -ItemType Directory -Force -Path (Split-Path $outputPath) | Out-Null

            $headerContent = $this.GetHeaders($importsMap, $entryFile) + [Environment]::NewLine + $entryFile.content
            $this.AddContentToFile($outputPath, $headerContent)
            $this.SaveSource($entryFile, $outputPath, @{})
            Write-Verbose "    Bundle saved at: $outputPath"
            return $outputPath
        }
        catch {
            Write-Error "Error creating bundle: $($_.Exception.Message)"
            exit
        }
    }

    [string]GetHeaders ([hashtable]$importsMap, [FileInfo]$entryFile) {
        $headers = @()
        if ($entryFile.topHeader) { $headers += ($entryFile.topHeader + [Environment]::NewLine) }
        
        $namespacesString = ($this.GetNamespacesString($importsMap)).trim()
        if ($namespacesString) { $headers += ($namespacesString + [Environment]::NewLine) }
        if ($entryFile.paramBlock) { $headers += ($entryFile.paramBlock + [Environment]::NewLine) }
        return $headers -join [Environment]::NewLine
    }

    [string]GetNamespacesString ([hashtable]$importsMap) {
        $namespacesMap = @{}
        foreach ($file in $importsMap.Values) {
            foreach ($namespace in $file.namespaces.Keys) {
                $namespacesMap["using namespace $namespace"] = $true
            }
        }

        return $namespacesMap.Keys -join [Environment]::NewLine
    }

    [FileInfo]GetEntryFile ([hashtable]$importsMap) {
        foreach ($file in $importsMap.Values) {
            if ($file.isEntry) { return $file }
        }
        
        Throw "Entry file is not found in imports map"
    }

    [hashtable[]] NormalizeReplacements([hashtable[]] $replacements) {
        [hashtable[]]$sorted = $replacements | Sort-Object { $_['Start'] }
        $normalized = @()
        if ($sorted.Count -eq 0) { return $normalized }

        $current = $sorted[0]

        for ($i = 1; $i -lt $sorted.Count; $i++) {
            $r = $sorted[$i]

            $currStart = [int]$current.Start
            $currEnd = $currStart + [int]$current.Length
            $rStart = [int]$r.Start
            $rEnd = $rStart + [int]$r.Length

            if ($rStart -le $currEnd) {                
                $newStart = [Math]::Min($currStart, $rStart)
                $newEnd = [Math]::Max($currEnd, $rEnd)
                $newLength = $newEnd - $newStart
                $current = @{
                    Start       = $newStart
                    Length      = $newLength
                    Replacement = "$($current.Replacement)$($r.Replacement)"
                }
            }
            else {                
                $normalized += $current
                $current = $r
            }
        }
        
        $normalized += $current

        [hashtable[]]$sortedNormalized = $normalized | Sort-Object { $_['Start'] } -Descending
        return $sortedNormalized
    }

    [string]PrepareSource ([FileInfo]$file) {
        $source = $file.ast.Extent.Text
        $sb = [System.Text.StringBuilder]::new($source)
        $replacements = $this.NormalizeReplacements($file.replacements)
        foreach ($r in $replacements) {
            $sb.Remove($r.Start, $r.Length) | Out-Null
            $sb.Insert($r.Start, $r.Replacement) | Out-Null
        }
        return $sb.ToString()
    }

    [void]SaveSource([FileInfo]$file, [string]$outFile, [hashtable]$processed = @{}) {

        if ($file.imports.Keys.Count -gt 0) {
            foreach ($importFile in $file.imports.Values) {
                if ($processed[$importFile.path]) { continue }
                $this.SaveSource($importFile, $outFile, $processed)
            }
        }

        if ($this._config.addSourceFileNames) {
            $this.AddContentToFile($outFile, "`n### FILE: $($file.path) ###`n")
        }

        $source = $this.PrepareSource($file)
        $this.AddContentToFile($outFile, $source.Trim())
        Write-Host "        File '$($file.path)' added to bundle." -ForegroundColor Green
        $processed[$file.path] = $true
    }

    [void]AddContentToFile([string]$path, [string]$content) {
        Add-Content -Path $path -Value $content -Encoding UTF8 | Out-Null
    }   

    [string]ParseVersion([FileInfo]$file) {
        $tokens = $file.tokens
        
        $versionRegex = '#\s*version[:]?\s*([0-9]+(?:\.[0-9]+){0,3})'

        $tokenKind = [System.Management.Automation.Language.TokenKind]
        foreach ($token in $tokens) {
            if ($token.Kind -ne $tokenKind::Comment -and $token.Kind -ne $tokenKind::NewLine) { break }

            if ($token.Extent.Text -match $versionRegex) { return $matches[1] }
        }

        return ""
    }

    [string]PrepareBundleName ($bundleName, [FileInfo]$entryFile) { 

        $version = $this.ParseVersion($entryFile)
        if (-not $version) { return $bundleName }

        Write-Verbose "    Bundle version detected: $version"

        $name = [System.IO.Path]::GetFileNameWithoutExtension($bundleName)
        $ext = [System.IO.Path]::GetExtension($bundleName)

        return "$name-$version$ext"
    }
}

### FILE: D:\projects\repo\packages\powerShell\PSBundler\src\classes\cycles-detector.psm1 ###

Class CyclesDetector {

    [boolean]Check([hashtable]$importsMap) {
        foreach ($file in $importsMap.Values) {
            $result = $this.FindCycle($file, @{}, @{}, [System.Collections.Generic.List[string]]::new())
            if (-not $result) { continue }
            Write-Host "Circular import of the file '$($file.path)' found:" -ForegroundColor Red
            $this.ShowCycledValsPretty($result)
            return $true
        }

        return $false
    }


    [System.Collections.Generic.List[string]]FindCycle(
        [FileInfo]$file,
        [hashtable]$visited = @{},
        [hashtable]$stack = @{},
        [System.Collections.Generic.List[string]]$pathList = [System.Collections.Generic.List[string]]::new()
    ) {

        $path = $file.path
        
        if ($stack.ContainsKey($path)) {            
            $startIndex = $pathList.IndexOf($path)
            if ($startIndex -ge 0) {                
                return $pathList[$startIndex..($pathList.Count - 1)]
            }
        }
        
        if ($visited.ContainsKey($path)) { return $null }
        
        $stack[$path] = $true
        $pathList.Add($path)
        
        foreach ($importFile in $file.imports.Values) {
            $result = $this.FindCycle( $importFile, $visited, $stack, $pathList)
            if ($result) { return $result }
        }
        
        $stack.Remove($path)
        $visited[$path] = $true
        [void]$pathList.RemoveAt($pathList.Count - 1)
        
        return $null
    }

    [void]ShowCycledValsPretty([array]$Cycles) {
        if (-not $Cycles) { return }

        $maxWidth = 0
        for ($i = 0; $i -lt $Cycles.Count; $i++) {
            $val = $Cycles[$i]
            $gap = "    " * $i
            $maxWidth = [Math]::Max($maxWidth, $gap.Length + 1 + $val.Length ) 
        }
    

        for ($i = 0; $i -lt $Cycles.Count ; $i++) {
            $val = $Cycles[$i]
            $gap = "    " * $i
            $lines1 = "└─>"
            $gap2Len = $maxWidth - $val.Length - $gap.Length
            $lines2 = " " + "$(" " * $gap2Len)│" 
            if ($i -eq 0) {
                $lines1 = "   " 
                $lines2 = "<" + "$("─" * $gap2Len)┐"
            }
            elseif ($i -eq $Cycles.Count - 1) {
                $lines2 = " " + "$("─" * $gap2Len)┘"
            }

            $text = "$gap$lines1 $val $lines2"
            Write-Host $text -ForegroundColor Red
        }
    }
}

### FILE: D:\projects\repo\packages\powerShell\PSBundler\src\classes\imports-map.psm1 ###

class ImportsMap {
    [BundlerConfig]$_config

    importsMap ([BundlerConfig]$config) {
        $this._config = $config
    }

    [hashtable]GetImportsMap ([string]$entryPath) {
        $importMap = $this.GenerateImportsMap($entryPath, $true, $null, @{})
        $cyclesDetector = [CyclesDetector]::new()
        $hasCycles = $cyclesDetector.Check($importMap)
        if ($hasCycles) { return  $null }
        return $importMap
    }

    [hashtable]GenerateImportsMap (       
        [string]$filePath,
        [bool]$isEntry = $false,
        [FileInfo]$consumer = $null,
        [hashtable]$resultMap = @{}) {

        if ($resultMap.ContainsKey($filePath)) {
            $file = $resultMap[$filePath]
            $file.LinkToConsumer($consumer)
            return $resultMap
        }

        Write-Verbose "      Add file to map: $filePath"

        $file = [FileInfo]::new($filePath, $this._config, $isEntry, $consumer)
        $resultMap[$file.path] = $file

        $importsPaths = $file.ResolveImports()

        foreach ($importPath in $importsPaths) {
            $this.GenerateImportsMap($importPath, $false, $file, $resultMap)
        }
        
       
        return $resultMap
    }
}

### FILE: D:\projects\repo\packages\powerShell\PSBundler\src\classes\bundle-script.psm1 ###

class BundleScript {
    [string]$_entryPath
    [string]$_bundleName
    [BundlerConfig]$_config

    BundleScript ([string]$entryPath, [string]$bundleName, [BundlerConfig]$config) {
        $this._entryPath = $entryPath
        $this._bundleName = $bundleName
        $this._config = $config
    }

    [string]Start () {
        if (-not (Test-Path $this._entryPath)) {
            Write-Error "Entry point not found: $($this._entryPath)"
            return $null
        }

        Write-Verbose "    Prepare import map"
        $iMapCls = [ImportsMap]::new($this._config)
        $importsMap = $iMapCls.GetImportsMap($this._entryPath)
        if (-not $importsMap) {
            Write-Host "Can't build bundle: no modules map created" -ForegroundColor Red
            return $null
        }

        Write-Verbose "    Check cycles complete"

        $bundleSaver = [BundleSaver]::new($this._config)
        $outputPath = $bundleSaver.Generate($importsMap, $this._bundleName)
        return $outputPath
    }
    
}

### FILE: D:\projects\repo\packages\powerShell\PSBundler\src\classes\ps-obfuscator.psm1 ###

Class VarInfo {    
    [string]$Name    
    [string]$FullName    
    [string]$OriginalName    
    [string]$Scope    
    [bool]$IsScoped    
    [bool]$IsSplatted    
    [Ast]$Ast    
    [ScriptBlockAst]$ScriptBlockAst    
    [bool]$IsParameter    
    [string]$ObfuscatedName=""

    VarInfo (
        [string]$Name,
        [string]$FullName,
        [string]$OriginalName,
        [string]$Scope,
        [bool]$IsScoped,
        [bool]$IsSplatted,
        [bool]$IsParameter,
        [Ast]$Ast,
        [ScriptBlockAst]$ScriptBlockAst
    ) {
        $this.Name = $Name
        $this.FullName = $FullName
        $this.OriginalName = $OriginalName
        $this.Scope = $Scope
        $this.IsScoped = $IsScoped
        $this.IsSplatted = $IsSplatted
        $this.IsParameter = $IsParameter
        $this.Ast = $Ast
        $this.ScriptBlockAst = $ScriptBlockAst
        $this.ObfuscatedName = $OriginalName
    }
}
Class AstModel {
    [hashtable]$builtinVars
    [hashtable]$builtinFuncs
    [Ast]$ast
    [hashtable]$astMap

    AstModel([string]$Path) {
        $this.builtinVars = $this.GetBuiltinVariables()
        $this.builtinFuncs = $this.GetBuiltinFunctions()
        $this.ast = $this.FileToAst($Path)
        $this.astMap = $this.GetAstHierarchyMap($this.ast)
    }
    
    [Ast]FileToAst([string]$Path) {
        if (-not (Test-Path $Path)) { throw "File not found: $Path" }

        $script = Get-Content -Raw -LiteralPath $Path
        return $this.ScriptToAst($script)
    }

    [Ast]ScriptToAst([string]$script) {
        $errors = $null
        $scriptAst = [Parser]::ParseInput($script, [ref]$null, [ref]$errors)
        if ($errors) { throw "Parsing failed" }

        return $scriptAst
    }
                
    [System.Collections.Specialized.OrderedDictionary]GetAstHierarchyMap([Ast]$rootAst) {
        $map = [ordered]@{}

        $items = $rootAst.FindAll( { $true }, $true)
        foreach ($item in $items) {
            if (-not $item.Parent) { continue }
            $parent = $item.Parent
            if (-not $map.Contains($parent)) { $map[$parent] = [System.Collections.ArrayList]@() }
            [void]$map[$parent].Add($item)
        }

        return $map
    }
    
    [System.Collections.ArrayList]FindAstChildrenByType(        
        [System.Management.Automation.Language.Ast]$Ast,                         
        [Type]$ChildType = $null,        
        [string]$Select = "firstChildren",        
        [Type]$UntilType = $null

    ) {
        $result = [System.Collections.ArrayList]::new()

        function Recurse($current) {
            if (-not $this.astMap.Contains($current)) { return }
    
            foreach ($child in $this.astMap[$current]) {
                if ($UntilType -and $child -is $UntilType) { continue }
            
                if (-not $ChildType -or $child -is $ChildType) {
                    [void]$result.Add($child)
                    if ($Select -eq "firstChildren") { continue }
                }

                if ($Select -eq "directChildren") { continue }
                Recurse $child
            }
        }

        Recurse $Ast
        return $result
    }
    
    [VarInfo]GetAstVariableInfo(
        [VariableExpressionAst]$varExpressionAst,
        [ScriptBlockAst]$parentScriptBlockAst

    ) {

        if (-not ($varExpressionAst -is [VariableExpressionAst]) ) { throw "Expected VariableExpressionAst" }
        
        $root = -not $parentScriptBlockAst.Parent
    
        $params = $varExpressionAst.VariablePath

        if (-not $params.IsVariable -or $params.IsDriveQualified -or $this.BuiltinVars.ContainsKey($varExpressionAst.VariablePath.UserPath)) { return $null }

        $originalName = $params.UserPath 

        $scope = "local"
        $name = $originalName
        if (-not $params.IsUnscopedVariable ) {
            if ($params.IsGlobal) { $scope = "global" }
            elseif ($params.IsScript) { $scope = "script" }
            elseif ($params.IsPrivate) { $scope = "private" }

            $name = $originalName.Split(":", 2)[1]
        }
        elseif ($root) { $scope = 'script' }

        return [VarInfo]::new(
            $name, 
            "$($scope):$name", 
            $originalName, 
            $scope, 
            -not $params.IsUnscopedVariable, 
            $varExpressionAst.Splatted, 
            $varExpressionAst.Parent -is [ParameterAst], 
            $varExpressionAst, 
            $parentScriptBlockAst 

        )
    }

    [Ast]GetAstParentByType([Ast]$Ast, [Type]$Type) {
        $current = $Ast.Parent
        while ($current -and -not ($current -is $Type)) {
            $current = $current.Parent
        }

        return $current
    }

    [ScriptBlockAst]GetAstParentScriptBlock([Ast]$Ast) {
        return $this.GetAstParentByType($Ast, [ScriptBlockAst])
    }

    [ScriptBlockAst]GetAstRootScripBlock([Ast]$Ast) {
        if (-not $Ast) { return $null }
        if (-not $Ast.Parent) {
            if ($Ast -is [ScriptBlockAst]) { return $Ast }
            return $null
        }
        return $this.GetAstRootScripBlock($Ast.Parent)
    }

    [hashtable]GetBuiltinFunctions() {
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()

        $ps = [powershell]::Create()
        $ps.Runspace = $runspace

        $funcs = $ps.AddScript('Get-Command -CommandType Function | Select-Object -ExpandProperty Name').Invoke()

        $ps.Dispose()
        $runspace.Close()
        $runspace.Dispose()

        $cleanFuncs = $funcs | ForEach-Object { $_ -replace '^[A-Z]:', '' }
        $ht = @{}
        foreach ($f in $cleanFuncs) { $ht[$f] = $true }

        return $ht
    }

    [hashtable]GetBuiltinVariables() {
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()

        $ps = [powershell]::Create()
        $ps.Runspace = $runspace

        $vars = $ps.AddScript('Get-Variable | Select-Object -ExpandProperty Name').Invoke()

        $ps.Dispose()
        $runspace.Close()
        $runspace.Dispose()

        $ht = @{}
        foreach ($v in $vars) { $ht[$v] = $true }

        $ht['_'] = $true
        $ht['s'] = $true
        $ht['p'] = $true
        $ht['PSItem'] = $true
        $ht['sender'] = $true
        $ht['this'] = $true
        $ht['form'] = $true 
        $ht['PSCmdlet'] = $true
        $ht['LASTEXITCODE'] = $true
        $ht['Profile'] = $true
        $ht['matches'] = $true

        return $ht
    }
}
Class VarsNameGenerator {
    $usedMap = @{}
    $builtinNames = @{}
    $words = @(
        'Id', 'Object', 'Value', 'Table', 'Data', 'Item', 'Row', 'Cell', 'Index', 'Count', 'Filter',
        'Field', 'List', 'Array', 'Node', 'Key', 'Param', 'Entry', 'Type', 'Name', 'Source',
        'Target', 'Range', 'Size', 'Length', 'Result', 'Status', 'Option', 'Group', 'Parent', 'Child',
        'Column', 'Header', 'Record', 'Recordset', 'Buffer', 'Stream', 'Stack', 'Queue', 'Cache', 'Token',
        'Session', 'Context', 'Handle', 'Path', 'File', 'Folder', 'Driver', 'Engine', 'Query', 'Script',
        'Config', 'Method', 'Event', 'Action', 'Command', 'Process', 'Task', 'Thread', 'Lock', 'Flag',
        'Error', 'Message', 'Report', 'Log', 'Trace', 'Level', 'State', 'Mode', 'Format', 'Output',
        'Input', 'Source', 'Destination', 'Time', 'Date', 'Count', 'Limit', 'Offset', 'Filter', 'Pattern',
        'Value', 'Key', 'Index', 'Type', 'Status', 'Version', 'Option', 'Setting', 'Profile', 'Client'
    )

    VarsNameGenerator([hashtable]$builtinNames) {
        $this.builtinNames = $builtinNames
    }

    [string]GetObfuscatedName([string]$Mode) {
        if ($Mode -ieq "Natural") { return $this.GetNaturalName() }
        else { return $this.GetHardName() }
    }

    [string]GetNaturalName() {
        $new = ""

        while (-not $new -or $this.usedMap.ContainsKey($new)) {            
            $count = Get-Random -Minimum 3 -Maximum 5
            $chosen = Get-Random -InputObject $this.words -Count $count
            $new = ($chosen -join '')            
            if ($this.builtinNames.ContainsKey($new)) { $new = "" }
        }
        $this.usedMap[$new] = $true
        return $new
    }


    [string]GetHardName() {
        $chars = @()
        $lChars = [char[]]'abcdefghijklmnopqrstuvwxyz'
        $uChars = [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        $nChars = [char[]]'0123456789'
        $chars += $lChars
        $chars += $uChars
        $chars += $nChars

        $new = ""

        while (-not $new -or $this.usedMap.ContainsKey($new)) {
            $len = Get-Random -Minimum 7 -Maximum 20
            
            $firstChar = Get-Random -InputObject ($lChars + $uChars)

            $rest = ""
            for ($i = 1; $i -lt $len; $i++) {
                $rest += (Get-Random -InputObject $chars)
            }

            $new = "$firstChar$rest"

            if ($this.builtinNames.ContainsKey($new)) { $new = "" }
        }

        $this.usedMap[$new] = $true
        return $new
    }
}
Class VarsMapper {
    [hashtable]$config
    [AstModel]$astModel
    [VarsNameGenerator]$nameGenerator
    

    VarsMapper (
        [hashtable]$config,
        [AstModel]$astModel
    ) {
        $this.config = $config
        $this.astModel = $AstModel
        $this.nameGenerator = [VarsNameGenerator]::new($this.astModel.BuiltinVars)
    }

    [hashtable]GetMap() {
        Write-Host "        Generating variables map..." -ForegroundColor Green
        $varsMap = @{}
        $this.FillAssignmentsMap($this.astModel.ast, $this.astModel.ast, $varsMap)
        Write-Host "        Variables map generated. Found variable assignments: $($varsMap.Keys.Count)" -ForegroundColor Green
        return $varsMap
    }

    [void]FillAssignmentsMap(
        [ScriptBlockAst]$SbAst,
        [ScriptBlockAst]$RootSbAst,
        [hashtable]$VarsMap
    ) {

        if (-not $SbAst -is [ScriptBlockAst]) { throw "Expected ScriptBlockAst" }
                
        $varsInfo = $this.GetAssignmentsInfo($SbAst, $RootSbAst, $VarsMap)
        $VarsMap[$SbAst] = $varsInfo

        [ScriptBlockAst[]]$childrenSb = $this.astModel.FindAstChildrenByType($SbAst, [ScriptBlockAst], "firstChildren", $null)
            
        foreach ($childSb in $childrenSb) {
            $this.FillAssignmentsMap($childSb, $RootSbAst, $VarsMap)
        }
    }
    
    [hashtable]GetAssignmentsInfo(
        [ScriptBlockAst]$SbAst,
        [ScriptBlockAst]$RootSbAst,
        [hashtable]$VarsMap
    ) {

        if (-not $sbAst -is [ScriptBlockAst]) { throw "Expected ScriptBlockAst" }

        $assignments = @()
        
        if ($sbAst.Parent -is [FunctionDefinitionAst]) {
            $funcAst = $sbAst.Parent
            if ($funcAst.Parameters) { $assignments += $funcAst.Parameters }
        }
                
        $paramAssignments = $sbAst.FindAll({ 
                param($node)
                $node -is [ParameterAst]
            }, $false)

        if ($paramAssignments -and $paramAssignments.Count -gt 0) { $assignments += $paramAssignments }
        
        $statementsAssignments = $sbAst.FindAll({ 
                param($node)
                ($node -is [AssignmentStatementAst]) -or ($node -is [ForEachStatementAst]) -or ($node -is [ForStatementAst])
            }, $false) 
        if ($statementsAssignments -and $statementsAssignments.Count -gt 0) { $assignments += $statementsAssignments }

        $varsInfo = @{}

        foreach ($assignment in $assignments) {
            $varAst = $null
            if ($assignment -is [ParameterAst]) { $varAst = $assignment.Name }
            elseif ($assignment -is [AssignmentStatementAst]) { $varAst = $assignment.Left }
            elseif ($assignment -is [ForEachStatementAst]) { $varAst = $assignment.Variable }
            elseif ($assignment -is [ForStatementAst]) { $varAst = $assignment.Initializer.Left }
            
            if ($varAst -is [ConvertExpressionAst]) { $varAst = $varAst.Child }
            
            if ($varAst -isnot [VariableExpressionAst]) { continue }

            $varInfo = $this.astModel.GetAstVariableInfo($varAst, $SbAst)
            
            if (-not $varInfo -or $varsInfo.ContainsKey($varInfo.FullName)) { continue }
            
            if ($this.config.VarsExclude -contains $varInfo.OriginalName) { continue }
            
            if ($SbAst -ne $RootSbAst -and $varInfo.IsScoped -and ($varInfo.Scope -eq "script" -or $varInfo.Scope -eq "global")) {
                if (-not $VarsMap.ContainsKey($RootSbAst)) { $VarsMap[$RootSbAst] = @{} }
                
                $varInfo.ObfuscatedName = ($this.nameGenerator.GetObfuscatedName($this.config.Mode))
                if (-not $VarsMap[$RootSbAst].ContainsKey($varInfo.FullName)) { 
                    Write-Warning "A $($varInfo.Scope)-scoped variable '$($varInfo.OriginalName)' wat defined inside a function, not in the script root block. It will persist outside the function and may cause side effects. Line: $($varAst.Extent.StartLineNumber), column: $($varAst.Extent.StartColumnNumber)."
                    $VarsMap[$RootSbAst][$varInfo.FullName] = $varInfo 
                }
                continue
            }
            
            if ($varInfo.IsParameter) { $varInfo.ObfuscatedName = $varInfo.OriginalName }
            else { $varInfo.ObfuscatedName = ($this.nameGenerator.GetObfuscatedName($this.config.Mode)) }
        

            $varsInfo[$varInfo.FullName] = $varInfo
        }

        return $varsInfo
    }
}
Class VarReplacer {
    [hashtable]$config
    [AstModel]$astModel

    VarReplacer (
        [hashtable]$Config,
        [AstModel]$AstModel
    ) {
        $this.config = $Config
        $this.astModel = $AstModel
    }

    [System.Collections.ArrayList]GetReplacements() {
        $varsMapper = [VarsMapper]::new($this.config, $this.astModel)
        $varsMap = $varsMapper.GetMap()

        $replacements = [System.Collections.ArrayList]::new()
        Write-Host "        Generating variable replacements..." -ForegroundColor Green
        $this.FillVarReplacements($this.AstModel.ast, $varsMap, $replacements)
        Write-Host "        Variable replacements generated. Total replacements: $($replacements.Count)" -ForegroundColor Green
        return $replacements
    }

    [void]FillVarReplacements(
        [ScriptBlockAst]$SbAst,
        [hashtable]$VarsMap,
        [System.Collections.ArrayList]$Replacements
    ) {

        if (-not $SbAst -is [ScriptBlockAst]) { throw "Expected ScriptBlockAst" }
                
        $this.SetVarReplacementsForSb($VarsMap, $SbAst, $Replacements)

        [ScriptBlockAst[]]$childrenSb = $this.astModel.FindAstChildrenByType($SbAst, [ScriptBlockAst], "firstChildren", $null)
            
        foreach ($childSb in $childrenSb) {
            $this.FillVarReplacements($childSb, $VarsMap, $Replacements)
        }
    }
    
    SetVarReplacementsForSb(
        [hashtable]$VarsMap,
        [ScriptBlockAst]$SbAst,
        [System.Collections.ArrayList]$Replacements
    ) {
        

        $varsAst = $sbAst.FindAll({ 
                param($node)
                $node -is [VariableExpressionAst]
            }, $false)

        foreach ($varAst in $varsAst) {
            $varInfo = $this.astModel.GetAstVariableInfo($varAst, $SbAst)
            if (-not $varInfo) { continue }
        
            [VarInfo]$assignedVarInfo = $this.FindAssignedVarInfo($VarsMap, $varInfo, $SbAst)
            if (-not $assignedVarInfo) { 
                if (-not $varInfo.IsScoped -and -not $varInfo.IsParameter -and -not  $this.astModel.BuiltinVarNames.Contains($varInfo.OriginalName)) {
                    Write-Warning "The '$($varInfo.OriginalName)' is not defined. It may cause side effects. Line: $($varAst.Extent.StartLineNumber), column: $($varAst.Extent.StartColumnNumber)."
                }
                continue 
            }
            
            if ($assignedVarInfo.IsParameter) { continue }

            $obfuscatedName = $assignedVarInfo.ObfuscatedName
            if ($varInfo.IsScoped) { $obfuscatedName = $varInfo.Scope + ":" + $obfuscatedName }

            [void]$Replacements.Add(@{ Start = $varAst.Extent.StartOffset + 1; Length = $varAst.Extent.EndOffset - $varAst.Extent.StartOffset - 1; Replacement = $obfuscatedName })
        }
    }
    
    [VarInfo]FindAssignedVarInfo(
        [hashtable]$VarsMap,
        [VarInfo]$VarInfo,
        [ScriptBlockAst]$SbAst
    ) {
        if (-not $VarInfo -or $VarInfo.IsParameter) { return $null }
        
        $assignVarsInfo = $VarsMap[$SbAst]
        
        if ($assignVarsInfo -and $assignVarsInfo.ContainsKey($VarInfo.FullName)) {
            return  $assignVarsInfo[$VarInfo.FullName]
        }
        
        $parentSb = $this.astModel.GetAstParentScriptBlock($SbAst)
        
        if (-not $parentSb -and $VarsMap.ContainsKey($SbAst)) { 
            $assignVarsInfo = $VarsMap[$SbAst]
            
            if ($VarInfo.Scope -eq "global" -or $VarInfo.Scope -eq "script") { 
                if ($assignVarsInfo.ContainsKey($VarInfo.FullName)) { return $assignVarsInfo[$VarInfo.FullName] }
                return $null
            }            
            elseif (-not $VarInfo.IsScoped -and $VarInfo.Scope -eq "local" ) {
                $scriptName = "script:" + $VarInfo.Name
                if ($assignVarsInfo.ContainsKey($scriptName)) { return $assignVarsInfo[$scriptName] }

                $globalName = "global:" + $VarInfo.Name
                if ($assignVarsInfo.ContainsKey($globalName)) { return $assignVarsInfo[$globalName] }
            }

            return $null 
        }

        return $this.FindAssignedVarInfo($VarsMap, $VarInfo, $parentSb)
    }
}
Class FuncNameGenerator {
    $usedMap = @{}
    $builtinNames = @{}
    $words = @(
        'Id', 'Object', 'Value', 'Table', 'Data', 'Item', 'Row', 'Cell', 'Index', 'Count', 'Filter',
        'Field', 'List', 'Array', 'Node', 'Key', 'Param', 'Entry', 'Type', 'Name', 'Source',
        'Target', 'Range', 'Size', 'Length', 'Result', 'Status', 'Option', 'Group', 'Parent', 'Child',
        'Column', 'Header', 'Record', 'Recordset', 'Buffer', 'Stream', 'Stack', 'Queue', 'Cache', 'Token',
        'Session', 'Context', 'Handle', 'Path', 'File', 'Folder', 'Driver', 'Engine', 'Query', 'Script',
        'Config', 'Method', 'Event', 'Action', 'Command', 'Process', 'Task', 'Thread', 'Lock', 'Flag',
        'Error', 'Message', 'Report', 'Log', 'Trace', 'Level', 'State', 'Mode', 'Format', 'Output',
        'Input', 'Source', 'Destination', 'Time', 'Date', 'Count', 'Limit', 'Offset', 'Filter', 'Pattern',
        'Value', 'Key', 'Index', 'Type', 'Status', 'Version', 'Option', 'Setting', 'Profile', 'Client'
    )

    FuncNameGenerator([hashtable]$builtinNames) {
        $this.builtinNames = $builtinNames
    }

    [string]GetObfuscatedName([string]$Mode) {
        if ($Mode -ieq "Natural") { return $this.GetNaturalName() }
        else { return $this.GetHardName() }
    }

    [string]GetNaturalName() {
        $Prefixes = @("Add", "Clear", "Close", "Copy", "Enter", "Exit", "Find", "Format", "Get", "Hide", "Join", "Lock", "Move", "New", "Open", "Pop", "Push", "Redo", "Remove", "Rename", "Reset", "Resize", "Search", "Select", "Set", "Show", "Skip", "Split", "Step", "Switch", "Undo", "Unlock", "Watch", "Read", "Receive", "Send", "Write", "Compare", "Compress", "Convert", "Group", "Initialize", "Mount", "Save", "Sync", "Update", "Resolve", "Test", "Confirm", "Invoke", "Start", "Stop", "Submit")
        $new = ""

        while (-not $new -or $this.usedMap.ContainsKey($new)) {
            $prefix = Get-Random -InputObject $Prefixes            
            $count = Get-Random -Minimum 3 -Maximum 5
            $chosen = Get-Random -InputObject $this.words -Count $count
            $body = ($chosen -join '')
    
            $new = "$prefix-$body"
                    
            if ($this.builtinNames.ContainsKey($new)) { $new = "" }
        }

        $this.usedMap[$new] = $true
        return $new
    }

    [string]GetHardName() {
        $chars = @()
        $lChars = [char[]]'abcdefghijklmnopqrstuvwxyz'
        $uChars = [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        $nChars = [char[]]'0123456789'
        $chars += $lChars
        $chars += $uChars
        $chars += $nChars

        $new = ""

        while (-not $new -or $this.usedMap.ContainsKey($new)) {
            $len = Get-Random -Minimum 7 -Maximum 20
            
            $firstChar = Get-Random -InputObject $uChars

            $rest = ""
            for ($i = 1; $i -lt $len; $i++) {
                $rest += (Get-Random -InputObject $chars)
            }

            $body = "$firstChar$rest"
            $new = "Use-$body"

            if ($this.builtinNames.ContainsKey($new)) { $new = "" }
        }

        $this.usedMap[$new] = $true
        return $new
    }
}
Class FuncMapper {
    [hashtable]$config
    [AstModel]$astModel
    [FuncNameGenerator]$nameGenerator

    FuncMapper (
        [hashtable]$config,
        [AstModel]$astModel
    ) {
        $this.config = $config
        $this.astModel = $AstModel
        $this.nameGenerator = [FuncNameGenerator]::new($this.astModel.BuiltinVars)
    }
    
    [hashtable]GetMap() {
        Write-Host "        Generating functions map..." -ForegroundColor Green
        $funcsMap = @{}
        $this.FillAssignmentsMap($this.astModel.ast, $funcsMap)
        Write-Host "        Functions map generated. Found function definitions: $($funcsMap.Keys.Count)" -ForegroundColor Green
        return  $funcsMap
    }

    [void]FillAssignmentsMap(
        [ScriptBlockAst]$Ast,
        [hashtable]$FuncsMap
    ) {
        $exclude = $null
        if ($this.config.FuncsExclude.Count) { $exclude = $this.config.FuncsExclude }

        $funcAsts = $Ast.FindAll({ 
                param($n)                 
                $n -is [FunctionDefinitionAst] -and -not ($n.parent -is [FunctionMemberAst])
            }, $true)
        

        $funcNames = @($funcAsts | ForEach-Object { $_.Name } | Where-Object { $_ -and ($_ -notin $exclude) } | Sort-Object -Unique)

        if (-not $funcNames -or $funcNames.Count -eq 0) { return }

        $this.FillObfuscatedMap($funcNames, $FuncsMap)
    }

    [void]FillObfuscatedMap([string[]]$funcNames, [hashtable]$FuncsMap) {
        foreach ($name in $funcNames) {
            $new = $this.nameGenerator.GetObfuscatedName($this.config.Mode)
            $funcsMap[$name] = $new
        }
    }
}
Class FuncReplacer {
    [hashtable]$config
    [AstModel]$astModel

    FuncReplacer (
        [hashtable]$Config,
        [AstModel]$AstModel
    ) {
        $this.config = $Config
        $this.astModel = $AstModel
    }

    [System.Collections.ArrayList]GetReplacements() {
        $funcMapper = [FuncMapper]::new($this.config, $this.astModel)
        $funcMap = $funcMapper.GetMap()

        $replacements = [System.Collections.ArrayList]::new()
        Write-Host "        Generating function replacements..." -ForegroundColor Green
        $this.FillReplacements($funcMap, $replacements)
        Write-Host "        Function replacements generated. Total replacements: $($replacements.Count)" -ForegroundColor Green
        return $replacements
    }


    FillReplacements(
        [hashtable]$FuncsMap,
        [System.Collections.ArrayList]$Replacements
    ) {
        $ast =$this.astModel.ast

        $funcsAst = $ast.FindAll({ 
                param($node)
                ($node -is [CommandAst]) -or ($node -is [FunctionDefinitionAst])
            }, $true)

        foreach ($funcAst in $funcsAst) {
            $element = $null
            $funcName = ""
            $start = 0
            $length = 0            
            if ($funcAst -is [CommandAst]) { 
                $element = $funcAst.CommandElements[0]

                if (-not ($element -is [StringConstantExpressionAst]) -or $element.StringConstantType -ne 'BareWord') { continue }
                $funcName = $element.Value

                if ($funcName -eq "Get-Command") { 
                    $extent = $this.GetSpecialFunctionParameterExtent($funcAst)
                    if (-not $extent) { continue }
                    $funcName = $extent.Value
                    $start = $extent.Start
                    $length = $extent.Length                

                }
                else {
                    $start = $element.Extent.StartOffset
                    $length = $element.Extent.EndOffset - $start
                }
            }            
            elseif ($funcAst -is [FunctionDefinitionAst]) {
                $extent = $this.GetFunctionNameExtent($funcAst)
                if (-not $extent) { continue }
                $funcName = $extent.Value
                $start = $extent.Start
                $length = $extent.Length
            }

            if (-not $funcName) { continue }

            $obfuscatedName = ""
            if ($FuncsMap.ContainsKey($funcName)) { $obfuscatedName = $FuncsMap[$funcName] }
            else { continue }

            [void]$Replacements.Add(@{ Start = $start; Length = $length; Replacement = $obfuscatedName })
        }
    }

    
    [PSCustomObject]GetFunctionNameExtent([FunctionDefinitionAst]$funcAst) {
        $name = $funcAst.Name
        $extent = $funcAst.Extent
        $text = $extent.Text
        $localOffset = $text.IndexOf($name)

        if ($localOffset -lt 0) { return $null }

        $start = $extent.StartOffset + $localOffset
        $length = $name.Length

        return [PSCustomObject]@{
            Value  = $name
            Start  = $start
            Length = $length
        }
    }
    
    [PSCustomObject]GetSpecialFunctionParameterExtent([CommandAst]$funcAst) {
        $elements = $funcAst.CommandElements

        if (-not $elements -or $elements.Count -lt 2) { return $null }
        
        $paramNameFound = $true

        for ($i = 1; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            if ($paramNameFound -and $element -is [StringConstantExpressionAst]) {
                return [PSCustomObject]@{
                    Value  = $element.Value
                    Start  = $element.Extent.StartOffset
                    Length = $element.Extent.EndOffset - $element.Extent.StartOffset
                }
            }

            $paramNameFound = $false
            if ($element -is [CommandParameterAst] -and $element.ParameterName -eq "Name") {
                $paramNameFound = $true
                continue
            }
        }
        return $null
    }
}
class PsObfuscator { 
    [hashtable]$config = @{}

    PsObfuscator ([string]$Path,
        [string]$OutPath,
        [string[]]$VarsExclude = @(),
        [string[]]$FuncsExclude = @(),        
        [string]$Mode = "Natural" 
    ) {
        $this.config = @{
            Path         = $Path
            OutPath      = $OutPath
            VarsExclude  = $VarsExclude
            FuncsExclude = $FuncsExclude
            Mode         = $Mode
        }
    }

    [void] Start() {
        Write-Host "Starting obfuscation for file: $($this.config.Path)" -ForegroundColor Green
        $astModel = [AstModel]::new($this.config.Path)

        $replacements = [System.Collections.ArrayList]::new()
        $varReplacer = [VarReplacer]::new($this.config, $astModel)
        Write-Host "    Variables obfuscation..." -ForegroundColor Green
        $varReplacements = $varReplacer.GetReplacements()
        if ($varReplacements) { $replacements.AddRange($varReplacements) }

        $funcReplacer = [FuncReplacer]::new($this.config, $astModel)
        Write-Host "    Functions obfuscation..." -ForegroundColor Green
        $funcReplacements = $funcReplacer.GetReplacements()
        if ($funcReplacements) { $replacements.AddRange($funcReplacements) }

        Write-Host "    Making replacements in script..." -ForegroundColor Green
        $obfuscatedScript = $this.MakeScriptReplacements($astModel.ast.Extent.Text, $replacements)
        Write-Host "    Replacements done. Total replacements: $($replacements.Count)" -ForegroundColor Green
        
        $outPath = $this.config.OutPath
        if (-not $outPath) {
            $base = [System.IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $this.config.Path).Path)
            $name = [System.IO.Path]::GetFileNameWithoutExtension($this.config.Path)
            $ext = [System.IO.Path]::GetExtension($this.config.Path)
            $outPath = Join-Path $base ("$name.obf$ext")
        }

        [System.IO.File]::WriteAllText($outPath, $obfuscatedScript, [System.Text.Encoding]::UTF8) 

        Write-Host "Obfuscated script saved to: $outPath" -ForegroundColor Green
    }

    [string]MakeScriptReplacements([string]$Script, [System.Collections.ArrayList]$Replacements) {
        if ($Replacements.Count -eq 0) {
            Write-Verbose "No replacements found."
            return ""
        }

        $sb = [System.Text.StringBuilder]::new($Script)
        $replacementsSorted = $Replacements | Sort-Object { $_['Start'] } -Descending
        foreach ($r in $replacementsSorted) {
            $sb.Remove($r.Start, $r.Length) | Out-Null
            $sb.Insert($r.Start, $r.Replacement) | Out-Null
        }
        return $sb.ToString()
    }
}

### FILE: D:\projects\repo\packages\powerShell\PSBundler\src\main.ps1 ###

class PsBundler { 
    [object]$_config

    PsBundler () {
        $this.Start()
    }

    [void]Start () {
        Write-Host "Building..."

        $this._config = [BundlerConfig]::new()

        if (-not $this._config.entryPoints) {
            Write-Error "No entry points found in config"
            exit
        }

        foreach ($entryPoint in $this._config.entryPoints.Keys) {
            $bundleName = $this._config.entryPoints[$entryPoint]
            Write-Verbose "  Starting bundle: $entryPoint => $bundleName"
            $psBundler = [BundleScript]::new($entryPoint, $bundleName, $this._config)
            $resultPath = $psBundler.Start()
            Write-Verbose "  End bundle: $resultPath"
            
            if ($this._config.obfuscate) {
                Write-Verbose "  Start obfuscation: $resultPath"
                $psObfuscator = [PsObfuscator]::new($resultPath, $null, @(), @(), $this._config.obfuscate)
                $psObfuscator.Start()
                Write-Verbose "  End obfuscation: $resultPath"
            }
        }

        Write-Host "Build completed at: $($this._config.outDir)"
    }
}

$null = New-Object PsBundler
