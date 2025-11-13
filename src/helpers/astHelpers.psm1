using namespace System.Management.Automation.Language
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