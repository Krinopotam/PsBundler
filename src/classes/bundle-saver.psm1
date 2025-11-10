using module .\bundler-config.psm1
using module .\file-info.psm1

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