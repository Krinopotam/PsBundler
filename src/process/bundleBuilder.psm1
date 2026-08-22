using module ..\models\bundlerConfig.psm1
using module ..\models\fileInfo.psm1

class BundleBuilder {
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
            throw "HANDLED: Error creating bundle: $($_.Exception.Message)"
        }
    }

    [string]getHeaders ([hashtable]$replacementsInfo) {
        $result = ""
        if ($replacementsInfo.headerComments) { $result += ( $replacementsInfo.headerComments + [Environment]::NewLine * 2) }

        $assemblies = $this.getNamespacesString($replacementsInfo.assemblies)
        if ($assemblies) { $result += ($assemblies + [Environment]::NewLine * 2) }

        $namespaces = $this.getNamespacesString($replacementsInfo.namespaces)
        if ($namespaces) { $result += ($namespaces + [Environment]::NewLine * 2) }

        if ($replacementsInfo.paramBlock) { $result += ($replacementsInfo.paramBlock + [Environment]::NewLine * 2) }

        # Safe Add-Type commands must execute immediately before deferred class
        # source is passed to Invoke-Expression. In the regular class mode this
        # collection is empty and Add-Type remains at its original location.
        $addTypes = $this.getAddTypesString($replacementsInfo.addTypes)
        if ($addTypes) { $result += ($addTypes + [Environment]::NewLine * 2) }

        $classes = $this.getClassesString($replacementsInfo.classes)
        if ($classes) { $result += ($classes + [Environment]::NewLine * 2) }

        return $result
    }

    [string]getAssembliesString ([System.Collections.Specialized.OrderedDictionary]$assemblies) {
        return $assemblies.Values -join [Environment]::NewLine
    }

    [string]getNamespacesString ([System.Collections.Specialized.OrderedDictionary]$namespaces) {
        return $namespaces.Values -join [Environment]::NewLine
    }

    [string]getAddTypesString ([System.Collections.ArrayList]$addTypes) {
        return $addTypes -join [Environment]::NewLine
    }

    [string]getClassesString ([System.Collections.Specialized.OrderedDictionary]$classes) {
        if ($classes.Count -eq 0) { return "" }
        $classesStr = $classes.Values -join ([Environment]::NewLine + [Environment]::NewLine)

        if (-not $this._config.deferClassesCompilation) { return $classesStr }
               
        if (-not $this._config.embedClassesAsBase64) {
            return "`$__PS_BUNDLER_CLASSES_SOURCE = @'" + [Environment]::NewLine `
                + $classesStr + [Environment]::NewLine `
                + "'@" + [Environment]::NewLine `
                + "Invoke-Expression `$__PS_BUNDLER_CLASSES_SOURCE" + [Environment]::NewLine `
                + "`$__PS_BUNDLER_CLASSES_SOURCE = `$null"
        }

        $bytes = [Text.Encoding]::UTF8.GetBytes($classesStr)
        $classesStr = [Convert]::ToBase64String($bytes)
        
        return "`$__PS_BUNDLER_CLASSES_B64 = '$classesStr'" + [Environment]::NewLine `
            + "`$__PS_BUNDLER_CLASSES_BYTES = [System.Convert]::FromBase64String(`$__PS_BUNDLER_CLASSES_B64)" + [Environment]::NewLine `
            + "`$__PS_BUNDLER_CLASSES_SOURCE = [System.Text.Encoding]::UTF8.GetString(`$__PS_BUNDLER_CLASSES_BYTES)" + [Environment]::NewLine `
            + "Invoke-Expression `$__PS_BUNDLER_CLASSES_SOURCE" + [Environment]::NewLine `
            + "`$__PS_BUNDLER_CLASSES_BYTES = `$null" + [Environment]::NewLine `
            + "`$__PS_BUNDLER_CLASSES_SOURCE = `$null" + [Environment]::NewLine `
            + "`$__PS_BUNDLER_CLASSES_B64 = `$null"
    }

    [FileInfo]getEntryFile ([hashtable]$importsMap) {
        foreach ($file in $importsMap.Values) {
            if ($file.isEntry) { return $file }
        }
        
        throw "Entry file is not found in imports map"
    }

    [hashtable[]]normalizeReplacements([hashtable[]] $replacements) {
        # WORKAROUND: System.Collections.ArrayList may unfold hashtables when sorting. So we must use [hashtable[]]
        [hashtable[]]$sorted = $replacements | Sort-Object { $_['Start'] }
        $normalized = @()
        if (-not $sorted -or $sorted.Count -eq 0) { return $normalized }

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
        return $sb.ToString().Trim()
    }

    [string]getModulesContent([FileInfo]$entryFile, [hashtable]$replacementsInfo) {
        $contentList = [System.Collections.ArrayList]::new()
        $contentList.Add($this.getModuleRuntimeContent() + [Environment]::NewLine)

        $this.fillModulesContentList($entryFile, $replacementsInfo, $contentList, "", @{})

        if ($contentList.Count -eq 1) { return "" }
        return $contentList -join [Environment]::NewLine * 2
    }

    [string]getModuleRuntimeContent() {
        $sourceMapName = $this._config.modulesSourceMapVarName
        $loaderMapKey = $this._config.moduleLoaderMapKey
        $runtimeContextName = $this._config.moduleRuntimeContextVarName
        $newLine = [Environment]::NewLine

        $lines = @()
        $lines += '$global:' + $sourceMapName + ' = @{}'
        $lines += '$global:' + $sourceMapName + '["' + $loaderMapKey + '"] = {'
        $lines += '    param([string]$ModuleId, [string]$ModuleName, [bool]$Reload = $false)'
        $lines += ''
        $lines += '    $runtimeContext = $ExecutionContext.SessionState.PSVariable.GetValue("' + $runtimeContextName + '")'
        $lines += '    if ($runtimeContext -isnot [hashtable] -or -not [object]::ReferenceEquals($runtimeContext["SourceMap"], $global:' + $sourceMapName + ')) {'
        $lines += '        $runtimeContext = @{'
        $lines += '            SourceMap = $global:' + $sourceMapName
        $lines += '            Cache = @{}'
        $lines += '            Loading = @{}'
        $lines += '        }'
        $lines += '        $global:' + $runtimeContextName + ' = $runtimeContext'
        $lines += '    }'
        $lines += ''
        $lines += '    $cache = $runtimeContext["Cache"]'
        $lines += '    $loading = $runtimeContext["Loading"]'
        $lines += '    if (-not $Reload -and $cache.ContainsKey($ModuleId)) {'
        $lines += '        return $cache[$ModuleId]'
        $lines += '    }'
        $lines += ''
        $lines += '    if ($loading.ContainsKey($ModuleId)) {'
        $lines += '        throw "Cyclic module initialization detected: $ModuleId"'
        $lines += '    }'
        $lines += '    if (-not $global:' + $sourceMapName + '.ContainsKey($ModuleId)) {'
        $lines += '        throw "Bundled module source is not registered: $ModuleId"'
        $lines += '    }'
        $lines += ''
        $lines += '    $loading[$ModuleId] = $true'
        $lines += '    try {'
        $lines += '        $module = New-Module -Name $ModuleName -ScriptBlock $global:' + $sourceMapName + '[$ModuleId]'
        $lines += '        if (-not $module) { throw "Bundled module initialization returned no module: $ModuleId" }'
        $lines += '        $cache[$ModuleId] = $module'
        $lines += '        return $module'
        $lines += '    }'
        $lines += '    finally {'
        $lines += '        [void]$loading.Remove($ModuleId)'
        $lines += '    }'
        $lines += '}'

        return $lines -join $newLine
    }

    [void]fillModulesContentList([FileInfo]$file, [hashtable]$replacementsInfo, [System.Collections.ArrayList]$contentList, [string]$importType, [hashtable]$processed = @{}) {
        if ($file.imports.Values.Count -and $file.imports.Values.Count -gt 0) {
            foreach ($importInfo in $file.imports.Values) {
                $importFile = $importInfo.file
                if ($processed[$importFile.path]) { continue }
                $this.fillModulesContentList($importFile, $replacementsInfo, $contentList, $importInfo.Type, $processed)
            }
        }

        $processed[$file.path] = $true
                
        if ($file.typesOnly) { Write-Host "        File '$($file.path)' processed." -ForegroundColor Green; return }
        $source = $this.PrepareSource($file, $replacementsInfo.replacementsMap[$file.id])

        # An imported file may become empty after all of its static Add-Type
        # commands are hoisted before deferred class compilation. Imports pointing
        # to that file are still present, so its registry key must exist. Register
        # an empty script block for non-entry files instead of leaving a dangling
        # $global:__PS_BUNDLER_MODULES["..."] reference.
        if (-not $source -and $file.isEntry) { Write-Host "        File '$($file.path)' processed." -ForegroundColor Green; return }
        
        if (-not $file.isEntry) {
            $source = '$global:' + $this._config.modulesSourceMapVarName + '["' + $file.id + '"] = ' + $this.bracketWrap($source)
        }

        $contentList.Add($source)
        Write-Host "        File '$($file.path)' processed." -ForegroundColor Green
        return
    }

    # Wraps source without reindenting it, preserving here-string contents and terminators
    [string]bracketWrap([string]$str) {
        return "{" + [Environment]::NewLine + $str + [Environment]::NewLine + "}"
    }

    [void]addContentToFile([string]$path, [string]$content) {
        # Windows PowerShell writes -Encoding UTF8 with a BOM, while modern
        # PowerShell writes UTF-8 without one. PowerShell 2 treats a BOM-less
        # script as ANSI, which can corrupt non-ASCII source and even its syntax.
        # Use an explicit encoding so bundles are identical across host versions.
        $encoding = [System.Text.UTF8Encoding]::new($true)
        [System.IO.File]::AppendAllText($path, $content + [Environment]::NewLine, $encoding)
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
