using namespace System.Management.Automation.Language
Class AstHelpers {
    # Returns named parameters and their values as string from a CommandAst
    [System.Collections.Specialized.OrderedDictionary]GetCommandAstNamedParams([CommandAst]$commandAst) {
        $result = [ordered]@{}

        $elements = $commandAst.CommandElements
        # start from 1 to skip command name
        for ($i = 1; $i -lt $elements.Count; $i++) {
            $el = $elements[$i]

            if ($el -is [CommandParameterAst]) {
                $parName = $el.ParameterName
                $parValue = $null
                if ($i + 1 -lt $elements.Count -and $elements[$i + 1] -isnot [CommandParameterAst]) {
                    $parValue = $elements[$i + 1].Extent.Text
                    $i++
                }

                $result[$parName] = $parValue
                continue

            }
            
        }
        return $result
    }
}


function Test-CommandParsing {
    param( [string] $CommandLine )

    $astHelper = [AstHelpers]::new()

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($CommandLine, [ref]$null, [ref]$null)
    $cmdAsts = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)

    foreach ($cmd in $cmdAsts) {
        $params = $astHelper.GetCommandAstNamedParams($cmd)
    }
}

Test-CommandParsing "import-module 'fdfdfdfdf' -name 'C:\module1.psm1' -Force -DisableNameChecking"