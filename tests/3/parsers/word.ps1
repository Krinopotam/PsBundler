. "$PSScriptRoot/zip.ps1"
. "$PSScriptRoot/../core/searchRegex.ps1"
. "$PSScriptRoot/../helpers/strings.ps1"
. "$PSScriptRoot/../helpers/files.ps1"

# ---------- Check if file is Word document ---------------
function Test-IsWordDoc {
    param (
        [System.IO.FileInfo]$file
    )

    $ext = $file.Extension.ToLower()

    return ($ext -eq ".doc" -or $ext -eq ".docx" -or $ext -eq ".docm" -or $ext -eq ".rtf" -or $ext -eq ".odt" -or $ext -eq ".pdf") # word can read pdf text layer
}

function Initialize-WordInstance {
    try {

        $word = [System.Activator]::CreateInstance(
            [System.Type]::GetTypeFromProgID("Word.Application", $null)
        )

        #$word = New-Object -ComObject Word.Application
        $word.Visible = $false
        $word.DisplayAlerts = 0
        $word.Options.UpdateLinksAtOpen = $false
        
        return $word
    }
    catch {
        return $false
    }
}

function Close-WordInstance {
    param (
        [System.Collections.IDictionary]$appContext
    )

    try {
        if ($appContext.features.word) {
            $appContext.features.word.Quit()
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($appContext.features.word) | Out-Null
            $appContext.features.word = $null
        }
    }
    catch {}
}   

# ---------- Get MsWord docx content using simple zip xml parser ----------------------
function Get-DocContentByXmlParsing {
    param (
        [System.IO.FileInfo]$file,
        [hashtable]$searchParams
    )
    $zip = $null
    $fs = $null
    
    try {
        $fs = New-Object System.IO.FileStream (
            $file.FullName,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )

        $zip = New-Object System.IO.Compression.ZipArchive (
            $fs,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $false
        )


        $docEntry = $null
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -eq "word/document.xml") {
                $docEntry = $entry
                break
            }
        }

        if (-not $docEntry) { 
            $zip.Dispose()
            return $null 
        }

        # In some cases .docx file can be small, but it contains a big zipped document.xml file with repeated content. So we skip document.xml if it three times bigger than .docx
        if ($null -ne $searchParams.maxFileSize -and $docEntry.Length -gt $searchParams.maxFileSize * 3) {
            $zip.Dispose()
            return ""
        }

        $stream = $docEntry.Open()
        $xml = [xml](New-Object System.IO.StreamReader($stream)).ReadToEnd()
        $stream.Close()

        $nsmgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsmgr.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")

        # Parse paragraphs <w:p> tsg content
        $paragraphs = $xml.SelectNodes("//w:p", $nsmgr)

        $lines = @()
        foreach ($p in $paragraphs) {
            $texts = @()
            $nodes = $p.SelectNodes(".//w:t", $nsmgr)
            foreach ($node in $nodes) {
                $texts += $node.InnerText
            }
            $lines += ($texts -join "")
        }

        return ($lines -join "`n")
    }
    catch {
        Write-DebugErrorLog $_
        return $null
    }
    finally {
        $zip.Dispose()
        $fs.Close()
    }
}

# ---------- Get MsWord doc file content using MS Word com object ----------------------
function Get-DocContentByComObject {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file
    )

    $word = $searchParams.appContext.features.word
    $doc = $null
    $missing = [System.Reflection.Missing]::Value
    try {
        $doc = $word.Documents.Open(
            $file.FullName, # 1 Full name
            $false,         # 2 ConfirmConversions
            $true,          # 3 ReadOnly
            $false,         # 4 AddToRecentFiles
            "'",            # 5 Open password
            "'",            # 6 Temnplate password
            $false,         # 7 Revert (reread if already open)
            $missing,       # 8 WritePasswordDocument
            $missing,       # 9 WritePasswordTemplate
            $missing,       # 10 Format
            $missing,       # 11 Encoding
            $false,         # 12 Visible
            $false,         # 13 OpenConflictDocument
            $false          # 14 OpenAndRepair
        )

        $pageCount = $doc.ComputeStatistics([Microsoft.Office.Interop.Word.WdStatistic]::wdStatisticPages)
        if ($pageCount -gt 1000) { 
            # Skip files with more than 1000 pages (there are some small trap-files with well zipped repeated content)
            return "" 
        }
        return [string]$doc.Content.Text
    }
    catch {
        $errorCode = Get-ComErrorCode $_
        if ($errorCode -eq -2146822880) {
            $values = New-Object System.Collections.Specialized.OrderedDictionary
            $values.Add("#", 0)
            $values.Add("FilePath", $file.FullName)
            $values.Add("FileSize", $file.Length)
            $values.Add("FileDate", $file.LastWriteTime)
            $values.Add("Content", "[Password protected]")
            $values.Add("RuleDesc", "")
            &$searchParams.addToResult -searchParams $searchParams -filePath -values $values | Out-Null
            return $true
        }
        Write-DebugErrorLog $_
        return $null
    }
    finally {
        if ($doc) {
            $doc.Close([ref]$false) | Out-Null
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($doc) | Out-Null
            $doc = $null
        }
    }
}

# ---------- Search in MS Word docx file for patterns ----------
function Search-InWordDoc {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file,
        [hashtable]$deduplicatedMatches = @{}
    )

    $content = $null
    # try to use zip xml parser to get docx content (it is much faster then use MS Word com object)
    if ($searchParams.appContext.features.zip) {
        if (Test-ZipHeader -file $file) {
            $content = Get-DocContentByXmlParsing -file $file -searchParams $searchParams
        }
    }

    # try to use MS Word com object
    if ($null -eq $content -and $searchParams.appContext.features.word) {
        $content = Get-DocContentByComObject -searchParams $searchParams -file $file
    }

    if ($null -eq $content) { return $false }
    if ($content -is [bool] -and $content -eq $true) { return $true }

    $null = Test-ContentForPatterns -searchParams $searchParams `
        -content $content `
        -filePath $file.FullName `
        -fileName $file.Name `
        -fileSize $file.Length `
        -fileDate $file.LastWriteTime `
        -deduplicatedMatches $deduplicatedMatches
    return $true
}