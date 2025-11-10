using namespace System.Management.Automation.Language


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
