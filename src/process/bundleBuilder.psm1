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