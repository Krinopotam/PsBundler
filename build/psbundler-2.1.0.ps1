using namespace System.Management.Automation.Language

Class PsBundler { 
    [object]$_config

    PsBundler ([string]$configPath) {
        $this.Start($configPath)
    }

    [void]Start ([string]$configPath) {
        try {
            Write-Host "Building..."

            $this._config = [BundlerConfig]::new($configPath)

            if (-not $this._config.entryPoints) { Throw "HANDLED: No entry points found in config" }

            foreach ($entryPoint in $this._config.entryPoints.Keys) {
                $bundleName = $this._config.entryPoints[$entryPoint]
                Write-Verbose "  Starting bundle: $entryPoint => $bundleName"
                $scriptBundler = [ScriptBundler]::new($entryPoint, $bundleName, $this._config)
                $resultPath = $scriptBundler.Start()
                if (-not $resultPath) { Throw "HANDLED: Build failed" }

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
        catch {
            if ($_.Exception.Message -like "HANDLED:*") { Write-Host ($_.Exception.Message -replace "^HANDLED:\s*", "") -ForegroundColor Red }
            else { Write-Error -ErrorRecord $_ }
        }
    }
}

Class ScriptBundler {
    [string]$_entryPath
    [string]$_bundleName
    [BundlerConfig]$_config

    ScriptBundler ([string]$entryPath, [string]$bundleName, [BundlerConfig]$config) {
        $this._entryPath = $entryPath
        $this._bundleName = $bundleName
        $this._config = $config
    }

    [string]Start () {
        if (-not (Test-Path $this._entryPath)) { Throw "HANDLED: Entry point not found: $($this._entryPath)" }

        Write-Verbose "    Prepare import map"
        $importsMapper = [ImportsMapper]::new($this._config)
        $importsMap = $importsMapper.GetImportsMap($this._entryPath)
        if (-not $importsMap) { Throw "HANDLED: Can't build bundle: no modules map created" }

        $entryFile = $importsMapper.GetEntryFile($importsMap)
        if (-not $entryFile) { Throw "HANDLED: Entry file is not found in imports map" }

        $replacer = [Replacer]::new($this._config)
        $replacementsInfo = $replacer.GetReplacements($importsMap)

        $bundleBuilder = [BundleBuilder]::new($this._config)
        $outputPath = $bundleBuilder.Build($importsMap, $replacementsInfo, $this._bundleName)
        return $outputPath
    }

    
    
}

Class BundlerConfig {
    # project folder root path
    [string]$projectRoot = ".\"
    # output folder path in project folder
    [string]$outDir = "build"
    # map of entry points path
    [hashtable]$entryPoints = @{}
    # add comment with source file names to bundle
    [bool]$addSourceFileNames = $true
    # strip comments in bundle
    [bool]$stripComments = $true
    # keep comments at the top of entry file
    [bool]$keepHeaderComments = $true     
    # whether to obfuscate the output bundle (Natural/Hard)
    [string]$obfuscate = ""

    [ObjectHelpers]$_objectHelpers
    [PathHelpers]$_pathHelpers

    BundlerConfig ([string]$configPath="") {
        $this._objectHelpers = [ObjectHelpers]::New()
        $this._pathHelpers = [PathHelpers]::New()
        $this.Load($configPath)
    }

    [void]Load([string]$configPath="") {
        # -- Default config
        $config = @{
            projectRoot        = ".\"          # project folder root path
            outDir             = "build"       # output folder path in project folder
            entryPoints        = @{}           # list of entry points path
            addSourceFileNames = $true         # add comment with source file names to bundle
            stripComments      = $true        # strip comments in bundle
            keepHeaderComments = $true         # keep comments at the top of entry file
            obfuscate          = ""            # whether to obfuscate the output bundle (Natural/Hard)
        }

        $userConfig = $this.GetConfigFromFile($configPath)

        foreach ($key in $userConfig.Keys) { $config[$key] = $userConfig[$key] }

        # -- Prepare project root path 
        $root = [System.IO.Path]::GetFullPath($config.projectRoot)
        $this.projectRoot = $root
    
        # -- Prepare outDir path 
        if (-not $config.outDir) { $config.outDir = "" }
        if (-not ([System.IO.Path]::IsPathRooted($config.outDir))) { $config.outDir = Join-Path $root $config.outDir }
        $this.outDir = [System.IO.Path]::GetFullPath($config.outDir)

        # -- Prepare entries paths
        if (-not $userConfig.entryPoints -or $userConfig.entryPoints.Count -eq 0) { throw "No entry points found in config" }

        $this.entryPoints = @{}
        foreach ($entryPath in $config.entryPoints.Keys) {
            $bundleName = $config.entryPoints[$entryPath]
            if (-not ($this._pathHelpers.IsValidPath($bundleName))) { throw "Invalid bundle name: $bundleName" }

            $entryAbsPath = [System.IO.Path]::GetFullPath( (Join-Path $root $entryPath))
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

    [PSCustomObject]GetConfigFromFile ([string]$configPath = "") {
        if (-not $configPath) { 
            $scriptLaunchPath = Get-Location # current PS active path
            $configPath = Join-Path -Path $scriptLaunchPath -ChildPath 'psbundler.config.json'
        }

        if ((Test-Path $configPath)) {
            try {
                $config = Get-Content $configPath -Raw | ConvertFrom-Json
                $configHashTable = $this._objectHelpers.ConvertToHashtable($config)
                Write-Host "Using config: $(Resolve-Path $configPath)"
                return $configHashTable
            }
            catch {
                Write-Host "Error reading config file: $($_.Exception.Message)" -ForegroundColor Red
                exit 1
            }
        }
    
        Write-Host "Config file not found: $configPath" -ForegroundColor Red
        exit 1
    }
}

class ObjectHelpers {

    # --------- Convert object to hashtable----------
    [object]ConvertToHashtable([object]$inputObject) {
        if ($null -eq $inputObject) { return $null }

        # If it's a dictionary, process it as a hashtable
        if ($inputObject -is [System.Collections.IDictionary]) {
            $output = @{}
            foreach ($key in $inputObject.Keys) {
                $output[$key] = $this.ConvertToHashtable($inputObject[$key])
            }
            return $output
        }

        # If it's an array or collection (BUT NOT a string)
        if ($inputObject -is [System.Collections.IEnumerable] -and -not ($inputObject -is [string])) { return $inputObject }

        #If it's a PSObject or PSCustomObject - convert it to a hashtable
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

        # Otherwise, return the object as-is
        return $inputObject
    }
}

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

Class ImportsMapper {
    [BundlerConfig]$_config
    [ImportParser]$_importParser

    ImportsMapper ([BundlerConfig]$config) {
        $this._config = $config
        $this._importParser = [ImportParser]::new($config)
    }

    [System.Collections.Specialized.OrderedDictionary]GetImportsMap ([string]$entryPath) {
        $importMap = $this.GenerateMap($entryPath, $true, $null, [ordered]@{})
        $cyclesDetector = [CyclesDetector]::new()
        $hasCycles = $cyclesDetector.Check($importMap)
        if ($hasCycles) { return  $null }
        Write-Verbose "    Check cycles complete"
        return $importMap
    }

    [System.Collections.Specialized.OrderedDictionary]GenerateMap (       
        [string]$filePath,
        [bool]$isEntry,
        [hashtable]$consumerInfo,
        [System.Collections.Specialized.OrderedDictionary]$importMap) {

        if ($importMap.Contains($filePath)) {
            $file = $importMap[$filePath]
            $file.LinkToConsumer($consumerInfo)
            return $importMap
        }

        Write-Verbose "      Add file to map: $filePath"

        $file = [FileInfo]::new($filePath, $this._config, $isEntry, $consumerInfo)
        $importMap[$file.path] = $file

        $importsInfo = $this._importParser.ParseFile($file)

        foreach ($importInfo in $importsInfo) {
            $consumerInfo = @{
                File      = $file
                PathAst   = $importInfo.PathAst
                ImportAst = $importInfo.ImportAst
                Type      = $importInfo.Type
            }
            $this.GenerateMap( $importInfo.Path, $false, $consumerInfo, $importMap)
        }
       
        return $importMap
    }

    # Get entry file
    [FileInfo]getEntryFile([System.Collections.Specialized.OrderedDictionary]$importsMap) {
        foreach ($file in $importsMap.Values) {
            if ($file.isEntry) { return $file }
        }
        return $null
    }
}

Class CyclesDetector {

    [boolean]Check([System.Collections.Specialized.OrderedDictionary]$importsMap) {
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

        # If the node is already in the current recursion stack, a cycle is found
        if ($stack.ContainsKey($path)) {
            # Find the starting index of the repeated path
            $startIndex = $pathList.IndexOf($path)
            if ($startIndex -ge 0) {
                # Return the sublist representing the cycle (including the repeated node)
                return $pathList[$startIndex..($pathList.Count - 1)]
            }
        }

        # Skip if the node has been fully visited already
        if ($visited.ContainsKey($path)) { return $null }

        # Mark the node as active (in the recursion stack)
        $stack[$path] = $true
        $pathList.Add($path)

        # Recursively check all imported files (dependencies)
        foreach ($importInfo in $file.imports.Values) {
            $importFile = $importInfo.file
            $result = $this.FindCycle( $importFile, $visited, $stack, $pathList)
            if ($result) { return $result }
        }

        # Remove the node from the stack after processing all dependencies
        $stack.Remove($path)
        $visited[$path] = $true
        [void]$pathList.RemoveAt($pathList.Count - 1)

        # No cycle found in this path
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

Class AstHelpers {
    # Returns CommandAst parameters names and values as Ast
    [hashtable[]]GetCommandAstParamsAst([CommandAst]$commandAst) {
        $result = @()
        $elements = $commandAst.CommandElements
        
        if ($elements.Count -lt 2) { return $result } # no parameters (first element is command name)

        # start from 1 to skip command name
        for ($i = 1; $i -lt $elements.Count; $i++) {
            $el = $elements[$i]

            if ($el -isnot [CommandParameterAst]) {
                $result += @{
                    name  = ""
                    value = $el
                }
                continue
            }

            $parName = $el.ParameterName
            $parValue = $null
            if ($i + 1 -lt $elements.Count -and $elements[$i + 1] -isnot [CommandParameterAst]) {
                $parValue = $elements[$i + 1]
                $i++
            }

            $result += @{
                name  = $parName
                value = $parValue
            }
        }
        return $result
    }

    # Returns CommandAst parameters names and values map
    [System.Collections.Specialized.OrderedDictionary]GetNamedParametersMap([CommandAst]$commandAst) {
        $paramsList = $this.GetCommandAstParamsAst($commandAst)
        $result = [System.Collections.Specialized.OrderedDictionary]::new()
        foreach ($par in $paramsList) {
            if ($par.name) {
                $result[$par.name] = $par.value
            }
        }

        return $result
    }

    # Converts parameters map to string
    [string]ConvertParamsAstMapToString([System.Collections.Specialized.OrderedDictionary]$paramsMap) {
        $paramsStr = ""
        foreach ($key in $paramsMap.Keys) {
            $value = $paramsMap[$key]
            if ($value) { $paramsStr += " -$key " + $value.Extent.Text }
            else { $paramsStr += " -$key" }
        }
        return $paramsStr
    }
}

Class Replacer {
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

            if ($this.isEntry) { 
                $headerComments = $this.fillHeaderCommentsReplacements($file, $replacements) 
                $paramBlock = $this.fillRootParamsReplacements($file, $replacements)
            }

            # Fill import replacements
            $this.fillImportReplacements($file, $replacements)

            # Fill comments replacements
            $this.fillCommentsReplacements($file, $replacements)
            
            # Namespaces replacements
            $this.fillNamespacesReplacements($file, $namespaces, $replacements)

            # Add-Types replacements
            $this.fillAddTypesReplacements($file, $addTypes, $replacements)

            # Classes replacements
            $this.fillClassesReplacements($file, $classes, $replacements)
        }

        return @{
            headerComments = $headerComments
            namespaces     = $namespaces
            paramBlock     = $paramBlock
            addTypes       = $addTypes
            classes        = $classes
            replacementsMap   = $replacementsMap
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
                Length = $importInfo.ImportAst.Extent.EndOffset - $importInfo.PathAst.Extent.StartOffset
                # replace whole dot-import statement
                Value  = $value
            }

            $replacements.Add($replacement)

            # Not import types (Classes, interfaces, structs, enums)
            if ($importFile.typesOnly) { continue }

            if ($importInfo.type -eq 'dot') {
                $replacement.Value = 'Invoke-Expression ($ExecutionContext.SessionState.PSVariable.GetValue("__PSBUNDLE_MODULES__"))[' + $importId + '].toString()' 
            }
            elseif ($importInfo.type -eq 'ampersand') {
                $replacement.Value = '(($ExecutionContext.SessionState.PSVariable.GetValue("__PSBUNDLE_MODULES__"))[' + $importId + ']).Invoke()' 
            }
            elseif ($importInfo.type -eq 'using') {
                $replacement.Value = 'Import-Module (New-Module -ScriptBlock ($ExecutionContext.SessionState.PSVariable.GetValue("__PSBUNDLE_MODULES__"))[' + $importId + ']) -Force -DisableNameChecking' 
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
                    $replacement.Value += [Environment]::NewLine + $value
                }
                else {
                    $replacement.Value = $value
                }
            } 
        }
    }

    # Fill replacements for comments
    [void]fillCommentsReplacements([FileInfo]$file, [System.Collections.ArrayList]$replacements) {
        if (-not $this._config.stripComments) { return }

        $tokenKind = [System.Management.Automation.Language.TokenKind]

        for ($i = 0; $i -lt $file.tokens.Count; $i++) {
            $token = $file.tokens[$i]
            if ($token.Kind -ne $tokenKind::Comment) { continue }

            $replacements.Add(@{start = $token.Extent.StartOffset; Length = $token.Extent.EndOffset - $token.Extent.StartOffset; value = "" })
   
            if (($i - 1) -gt 0 -and $file.tokens[$i - 1].Kind -eq $tokenKind::NewLine) {
                $replacements.Add(@{start = $file.tokens[$i - 1].Extent.StartOffset; Length = $file.tokens[$i - 1].Extent.EndOffset - $file.tokens[$i - 1].Extent.StartOffset; value = "" })
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
        if (-not $this.isEntry -or -not $this._config.keepHeaderComments) { return "" }
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
        if (-not $this.isEntry -or -not $file.Ast.ParamBlock) { return "" }
        $fileAst = $this.ast
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

Class BundleBuilder {
    [BundlerConfig]$_config

    BundleBuilder ([BundlerConfig]$config) {
        $this._config = $config
    }

    [string]build([hashtable]$importsMap, [hashtable]$replacementsInfo, [string]$bundleName) {
        try {
            $entryFile = $this.GetEntryFile($importsMap)
            $bundleName = $this.PrepareBundleName($bundleName, $entryFile)
            $outputPath = Join-Path $this._config.outDir $bundleName
            Write-Host "    Start save bundle at: $outputPath"

            if ((Test-Path $outputPath)) { Remove-Item -Path $outputPath -Force }
            New-Item -ItemType Directory -Force -Path (Split-Path $outputPath) | Out-Null

            $headerContent = $this.getHeaders($replacementsInfo)
            $modulesMapContent = $this.getModulesMapContent($importsMap, $replacementsInfo)

            $this.addContentToFile($outputPath, $headerContent)
            $this.addContentToFile($outputPath, $modulesMapContent)
            #$this.saveSource($entryFile, $outputPath, @{})
            Write-Verbose "    Bundle saved at: $outputPath"
            return $outputPath
        }
        catch {
            Write-Host "Error creating bundle: $($_.Exception.Message)" -ForegroundColor Red
            exit
        }
    }

    [string]getHeaders ([hashtable]$replacementsInfo) {
        $result = ""
        if ($replacementsInfo.headerComments) { $result += ( $replacementsInfo.headerComments + [Environment]::NewLine) }

        $namespaces = $this.getNamespacesString($replacementsInfo.namespaces)
        if ($namespaces) { $result += ($namespaces + [Environment]::NewLine*2) }

        if ($replacementsInfo.paramBlock) { $result += ($replacementsInfo.paramBlock + [Environment]::NewLine*2) }

        $addTypes = $this.getAddTypesString($replacementsInfo.addTypes)
        if ($addTypes -and $result) { $result += ( $addTypes + [Environment]::NewLine*2) }

        $classes = $this.getClassesString($replacementsInfo.classes)
        if ($classes) { $result += ($classes + [Environment]::NewLine*2) }

        return $result
    }

    [string]getNamespacesString ([System.Collections.Specialized.OrderedDictionary]$namespaces) {
        return $namespaces.Values -join [Environment]::NewLine
    }

    [string]getAddTypesString ([System.Collections.Specialized.OrderedDictionary]$addTypes) {
        return $addTypes.Values -join [Environment]::NewLine
    }

    [string]getClassesString ([System.Collections.Specialized.OrderedDictionary]$classes) {
        return $classes.Values -join ([Environment]::NewLine + [Environment]::NewLine)
    }

    [FileInfo]getEntryFile ([hashtable]$importsMap) {
        foreach ($file in $importsMap.Values) {
            if ($file.isEntry) { return $file }
        }
        
        Throw "Entry file is not found in imports map"
    }

    [hashtable[]]normalizeReplacements([hashtable[]] $replacements) {
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
                # Merge overlapping
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
                # Commit current and move on
                $normalized += $current
                $current = $r
            }
        }

        # Add the final one
        $normalized += $current

        [hashtable[]]$sortedNormalized = $normalized | Sort-Object { $_['Start'] } -Descending
        return $sortedNormalized
    }

    [string]PrepareSource ([FileInfo]$file, [System.Collections.ArrayList]$replacements) {
        $source = $file.ast.Extent.Text
        $sb = [System.Text.StringBuilder]::new($source)
        $replacements = $this.NormalizeReplacements($replacements)
        foreach ($r in $replacements) {
            $sb.Remove($r.Start, $r.Length) | Out-Null
            $sb.Insert($r.Start, $r.Replacement) | Out-Null
        }
        return $sb.ToString()
    }

    [string]getModulesMapContent([hashtable]$importsMap, [hashtable]$replacementsInfo) {
        $modules = [System.Collections.ArrayList]::new()
        $modules.Add('$script:__PSBUNDLE_HEADER__ = @{}' + [Environment]::NewLine)
        foreach ($file in $importsMap.Values) {
            if ($file.typesOnly) { continue }
            $modules.Add('$script:__PSBUNDLE_MODULES__[' + $file.id + '] = {' + [Environment]::NewLine + $this.PrepareSource($file, $replacementsInfo.replacementsMap[$file.id]) + [Environment]::NewLine + '}')
        }

        return $modules -join [Environment]::NewLine *2
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

    [void]addContentToFile([string]$path, [string]$content) {
        Add-Content -Path $path -Value $content -Encoding UTF8 | Out-Null
    }   

    [string]ParseVersion([FileInfo]$file) {
        $tokens = $file.tokens

        # English comment: regex for "#version: 1.2.3" (accepts 1 or 2 dots)
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


$script:__PSBUNDLE_HEADER__ = @{}


$script:__PSBUNDLE_MODULES__[8ac1969c-e40f-43a1-92bb-4cba56a6503a] = {
tBundler.psm1
erConfig.psm1
fuscator.psm1



function Invoke-PSBundler {
    [CmdletBinding()]
    param(
        [string]$configPath = ""
    )
    $null = [PsBundler]::new($configPath) 
}

}

$script:__PSBUNDLE_MODULES__[cad43485-8f6a-4ff5-974a-b4e6dbb15b92] = {


Remove-Module PsBundler -ErrorAction SilentlyContinue
r.psm1" -Force
Invoke-PsBundler -verbose
}
