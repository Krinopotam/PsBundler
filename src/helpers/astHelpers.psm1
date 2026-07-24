using namespace System.Management.Automation.Language
Class AstHelpers {
    # Returns true only for a standalone, static Add-Type command that can be
    # executed before deferred PowerShell classes are compiled.
    #
    # This is intentionally conservative:
    # - nested commands keep their if/try/function execution context;
    # - commands participating in a larger pipeline stay with that pipeline;
    # - assignments, redirections, -PassThru and dynamic arguments stay in place.
    #
    # The same predicate is used by Replacer and FileInfo so a command cannot be
    # removed as "hoisted" by one component but counted as runtime code by another.
    [bool]IsHoistableAddType([CommandAst]$commandAst, [ScriptBlockAst]$rootAst, [bool]$deferClassesCompilation) {
        if (-not $deferClassesCompilation -or -not $commandAst -or -not $rootAst) { return $false }
        if ($commandAst.GetCommandName() -ne "Add-Type") { return $false }
        if ($commandAst.InvocationOperator -ne [TokenKind]::Unknown) { return $false }

        $pipeline = $commandAst.Parent

        # Removing only CommandAst from "Add-Type ... | Out-Null" would leave an
        # invalid "| Out-Null" fragment. We hoist the containing pipeline, but only
        # when Add-Type is its sole element.
        if ($pipeline -isnot [PipelineAst] -or $pipeline.PipelineElements.Count -ne 1) { return $false }

        # A direct file-level command has the following parents:
        # CommandAst -> PipelineAst -> NamedBlockAst -> root ScriptBlockAst.
        # Any if, try, loop, function or assignment inserts another AST node and
        # therefore prevents hoisting.
        if ($pipeline.Parent -isnot [NamedBlockAst] `
                -or -not [object]::ReferenceEquals($pipeline.Parent.Parent, $rootAst)) { return $false }

        if ($commandAst.Redirections.Count -gt 0) { return $false }

        for ($i = 1; $i -lt $commandAst.CommandElements.Count; $i++) {
            $element = $commandAst.CommandElements[$i]

            if ($element -is [CommandParameterAst]) {
                # -PassThru makes command output observable at its original
                # position. Parameter abbreviations such as -Pass are rejected too.
                if ("PassThru".StartsWith($element.ParameterName, [StringComparison]::OrdinalIgnoreCase)) { return $false }
                if ($element.Argument -and -not $this.IsStaticExpression($element.Argument)) { return $false }
                continue
            }

            if (-not $this.IsStaticExpression($element)) { return $false }
        }

        return $true
    }

    # Static arguments can be moved without also moving variable assignments,
    # command substitutions or other prerequisite code. Expandable strings are
    # accepted only when they contain no nested expressions.
    [bool]IsStaticExpression([Ast]$ast) {
        if ($ast -is [StringConstantExpressionAst] -or $ast -is [ConstantExpressionAst]) { return $true }

        if ($ast -is [ExpandableStringExpressionAst]) {
            return -not $ast.NestedExpressions -or $ast.NestedExpressions.Count -eq 0
        }

        if ($ast -is [ArrayLiteralAst]) {
            foreach ($element in $ast.Elements) {
                if (-not $this.IsStaticExpression($element)) { return $false }
            }
            return $true
        }

        return $false
    }

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




<# function Test-CommandParsing {
    param( [string] $CommandLine )

    $astHelper = [AstHelpers]::new()

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($CommandLine, [ref]$null, [ref]$null)
    $cmdAsts = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)

    foreach ($cmd in $cmdAsts) {
        $params = $astHelper.ParseImportModuleCommandAst($cmd)
    }
}

Test-CommandParsing "import-module -name 'C:\module1.psm1' -Force -DisableNameChecking" #>
