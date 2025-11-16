using module ..\models\bundlerConfig.psm1
using module ..\models\fileInfo.psm1

Class BundleBuilder {
    [BundlerConfig]$_config

    BundleBuilder ([BundlerConfig]$config) {
        $this._config = $config
    }

    [string]build([hashtable]$importsMap, [hashtable]$replacementsInfo, [string]$bundleName) {
        try {
            $entryFile = $this.GetEntryFile($importsMap)
            $bundleName = $this.GetBundleName($bundleName, $entryFile)
            $outputPath = Join-Path $this._config.outDir $bundleName

            if ((Test-Path $outputPath)) { Remove-Item -Path $outputPath -Force }
            New-Item -ItemType Directory -Force -Path (Split-Path $outputPath) | Out-Null

            $headerContent = $this.getHeaders($replacementsInfo)
            $modulesContent = $this.getModulesContent($entryFile, $replacementsInfo)

            $this.addContentToFile($outputPath, $headerContent)
            $this.addContentToFile($outputPath, $modulesContent)
            return $outputPath
        }
        catch {
            Write-Host "Error creating bundle: $($_.Exception.Message)" -ForegroundColor Red
            exit
        }
    }

    [string]getHeaders ([hashtable]$replacementsInfo) {
        $result = ""
        if ($replacementsInfo.headerComments) { $result += ( $replacementsInfo.headerComments + [Environment]::NewLine * 2) }

        $namespaces = $this.getNamespacesString($replacementsInfo.namespaces)
        if ($namespaces) { $result += ($namespaces + [Environment]::NewLine * 2) }

        if ($replacementsInfo.paramBlock) { $result += ($replacementsInfo.paramBlock + [Environment]::NewLine * 2) }

        $addTypes = $this.getAddTypesString($replacementsInfo.addTypes)
        if ($addTypes -and $result) { $result += ( $addTypes + [Environment]::NewLine * 2) }

        $classes = $this.getClassesString($replacementsInfo.classes)
        if ($classes) { $result += ($classes + [Environment]::NewLine * 2) }

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
        # WORKAROUND: System.Collections.ArrayList may unfold hashtables when sorting. So we must use [hashtable[]]
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

            if ($rStart -lt $currEnd) {
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
        #$replacements = $replacements | Sort-Object { $_['Start'] } -Descending
        foreach ($r in $replacements) {
            $sb.Remove($r.Start, $r.Length)
            $sb.Insert($r.Start, $r.Value)
        }
        return $sb.ToString()
    }

    [string]getModulesContent([FileInfo]$entryFile, [hashtable]$replacementsInfo) {
        $contentList = [System.Collections.ArrayList]::new()
        $contentList.Add('$script:' + $this._config.modulesSourceMapVarName + ' = @{}' + [Environment]::NewLine)

        $this.fillModulesContentList($entryFile, $replacementsInfo, $contentList, "", @{})

        if ($contentList.Count -eq 1) { return "" }
        return $contentList -join [Environment]::NewLine * 2
    }

    [void]fillModulesContentList([FileInfo]$file, [hashtable]$replacementsInfo, [System.Collections.ArrayList]$contentList, [string]$importType, [hashtable]$processed = @{}) {
        if ($file.imports.Values.Count -gt 0) {
            foreach ($importInfo in $file.imports.Values) {
                $importFile = $importInfo.file
                if ($processed[$importFile.path]) { continue }
                $this.fillModulesContentList($importFile, $replacementsInfo, $contentList, $importInfo.Type, $processed)
            }
        }

        if ($file.typesOnly) { Write-Host "        File '$($file.path)' processed." -ForegroundColor Green; return }
        $source = $this.PrepareSource($file, $replacementsInfo.replacementsMap[$file.id])
        if (-not $file.isEntry) {
            if ($importType -eq "Using" -or $importType -eq "Module") { 
                # add parameter for modules variable
                $source = 'param($' + $this._config.modulesSourceMapVarName + ')' + [Environment]::NewLine + $source
            }
            $source = '$script:' + $this._config.modulesSourceMapVarName + '["' + $file.id + '"] = ' + $this.bracketWrap($source, "    ")
        }

        $processed[$file.path] = $true
        $contentList.Add($source)
        Write-Host "        File '$($file.path)' processed." -ForegroundColor Green
        return
    }

    # Wraps string in { ... } and make indents
    [string]bracketWrap([string]$str, [string]$indent = "    ") {
        return "{" + [Environment]::NewLine + (($str -split "\r?\n" | ForEach-Object { "$indent$_" }) -join [Environment]::NewLine) + [Environment]::NewLine + "}"
    }

    [void]addContentToFile([string]$path, [string]$content) {
        Add-Content -Path $path -Value $content -Encoding UTF8 | Out-Null
    }   

    [string]GetBundleName ($bundleName, [FileInfo]$entryFile) { 
        $version = $this.ParseVersion($entryFile)
        if (-not $version) { return $bundleName }

        Write-Verbose "    Bundle version detected: $version"

        $name = [System.IO.Path]::GetFileNameWithoutExtension($bundleName)
        $ext = [System.IO.Path]::GetExtension($bundleName)

        return "$name-$version$ext"
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
}