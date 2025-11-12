using module ..\models\fileInfo.psm1

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