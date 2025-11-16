. "$PSScriptRoot/zip.ps1"
. "$PSScriptRoot/../helpers/strings.ps1"
. "$PSScriptRoot/../helpers/files.ps1"
. "$PSScriptRoot/../core/searchRegex.ps1"

# ---------- Check if file is xlsx Excel document---------------
function Test-IsExcel {
    param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$file
    )

    $ext = $file.Extension.ToLower()
    return ($ext -eq ".xlsx" -or $ext -eq ".xlsm" -or $ext -eq ".xls")
}

#region ###################### Search in excel using zip/xml parsing ######################
# ---------- Get excel sheets info ------------------------------
function Get-ExcelSheetsFromZip {
    param ([System.IO.Compression.ZipArchive]$zip)

    #$entry = $zip.Entries | Where-Object { $_.FullName -eq "xl/workbook.xml" }
    
    $entry = $null
    foreach ($e in $zip.Entries) {
        if ($e.FullName -eq "xl/workbook.xml") {
            $entry = $e
            break
        }
    }
    
    if (-not $entry) { return ,@() }
    
    $stream = $null

    try {
        $stream = $entry.Open()
        $xml = New-Object System.Xml.XmlDocument
        $xml.Load($stream)
    }
    catch {
        Write-DebugErrorLog $_
        return [PSCustomObject]@{}
    }
    finally {
        if ($stream) { $stream.Close() }
    }

    $nsmgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $nsmgr.AddNamespace("s", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")

    $sheets = $xml.SelectNodes("//s:sheet", $nsmgr)
    $result = @{}
    for ($i = 0; $i -lt $sheets.Count; $i++) {
        $result[($i + 1)] = $sheets[$i].name
    }
    return $result
}


# ---------- Get exel shared strings collection ----------------
function Get-SharedStringsFromZip {
    param ([System.IO.Compression.ZipArchive]$zip)

    #$entry = $zip.Entries | Where-Object { $_.FullName -eq "xl/sharedStrings.xml" }
    $entry = $null
    foreach ($e in $zip.Entries) {
        if ($e.FullName -eq "xl/sharedStrings.xml") {
            $entry = $e
            break
        }
    }

    if (-not $entry) { return ,@() }

    $stream = $null

    try {
        $stream = $entry.Open()
        $xml = New-Object System.Xml.XmlDocument
        $xml.Load($stream)

        # in this case is more perfomant to use $xml.GetElementsByTagName than $xml.SelectNodes
        $nodes = $xml.GetElementsByTagName("t", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
        $texts = New-Object System.Collections.ArrayList
        foreach ($node in $nodes) {
            $null = $texts.Add($node.InnerText)
        }

        return $texts.ToArray()  

    }
    catch {
        Write-DebugErrorLog $_
        return ,@()
    }
    finally {
        if ($stream) { $stream.Close() }
    }
}

# ---------- Get data from excel sheet -------------------------
<#
Cells can be with shared string index:
    <c r="A1" t="s">
    <v>42</v>
    </c>

or  with inline value:
    <c r="B1" t="inlineStr">
    <is>
        <t>Hello</t>
    </is>
    </c>
#>

# function is complex to keep perfomance
function Get-ExcelSheetDataFromZip {
    param (
        [hashtable]$searchParams,
        [System.IO.Compression.ZipArchive]$zip,
        [int]$sheetIndex,
        [string[]]$sharedStrings
    )

    $sheetPath = "xl/worksheets/sheet$sheetIndex.xml"
    #$entry = $zip.Entries | Where-Object { $_.FullName -eq $sheetPath }

    $entry = $null
    foreach ($e in $zip.Entries) {
        if ($e.FullName -eq $sheetPath) {
            $entry = $e
            break
        }
    }

    if (-not $entry) { return "" }

    $stream = $null

    try {
        $stream = $entry.Open()
        $xml = New-Object System.Xml.XmlDocument
        $xml.Load($stream)

        $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsMgr.AddNamespace("s", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")

        # in this case is more perfomant to use $xml.SelectNodes than $xml.GetElementsByTagName
        $rows = $xml.SelectNodes("//s:sheetData/s:row", $nsMgr)
        $lines = New-Object System.Collections.Generic.List[string]

        foreach ($row in $rows) {
            if ($searchParams.appContext.state -ne "running") { return }

            $cellsText = @()
            $cells = $row.SelectNodes("s:c", $nsMgr)
            foreach ($cell in $cells) {
                if ($searchParams.appContext.state -ne "running") { return }

                $type = $cell.GetAttribute("t")
                $valNode = $cell.SelectSingleNode("s:v", $nsMgr)
                $val = if ($valNode) { $valNode.InnerText } else { "" }

                if ($type -ne "s" -or $val -eq "") { continue }

                $index = 0
                if ([int]::TryParse($val, [ref]$index)) {
                    if ($index -ge 0 -and $index -lt $sharedStrings.Length) {
                        $val = $sharedStrings[$index]
                    }
                    else {
                        $val = ""
                    }
                }
                else {
                    $val = ""
                }

                $cellsText += $val
            }
            $line = ($cellsText -join ' ').Trim()
            $lines.Add($line)
        }

        $res = $lines -join "`n"

        return $res
    }
    finally {
        $stream.Close()
    }
}

# ---------- Search in MS Excel xlsx file for patterns ---------
function Search-InXlsByXmlParsing {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file,
        [hashtable]$deduplicatedMatches = @{}
    )

    if (-not $searchParams.appContext.features.zip) { return $false }

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
    

        $sharedStrings = Get-SharedStringsFromZip -zip $zip
        $sheets = Get-ExcelSheetsFromZip -zip $zip

        foreach ($sheetIndex in $sheets.Keys) {
            $sheetName = $sheets[$sheetIndex]
            if ($searchParams.appContext.state -ne "running") { return }
            
            $content = Get-ExcelSheetDataFromZip -searchParams $searchParams -zip $zip -sheetIndex $sheetIndex -sharedStrings $sharedStrings
            $null = Test-ContentForPatterns -searchParams $searchParams `
                -content $content `
                -filePath $file.FullName `
                -fileName $file.Name `
                -fileSize $file.Length `
                -fileDate $file.LastWriteTime `
                -deduplicatedMatches $deduplicatedMatches `
                -prefix "$($sheetName): "
        }

        return $true
    }
    catch {
        Write-DebugErrorLog $_
        return $false
    }
    finally {
        $zip.Dispose()
        $fs.Close()
    }
}
#endregion

#region ############## Search in excel using MS Excel com object #########################
function Initialize-ExcelInstance {
    try {

        #$excel = New-Object -ComObject Excel.Application

        $excel = [System.Activator]::CreateInstance(
            [System.Type]::GetTypeFromProgID("Excel.Application", $null)
        )

        #$excel.DisplayAlerts = $false
        #$excel.EnableEvents = $false
        #$excel.Interactive = $false 
        return $excel
    }
    catch {
        return $false
    }
}

function Close-ExcelInstance {
    param (
        [System.Collections.IDictionary]$appContext
    )

    try {
        if ($appContext.features.excel) {
            $appContext.features.excel.Quit()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($appContext.features.excel) | Out-Null
            $appContext.features.excel = $null
        }
    }
    catch {}
} 


function Get-ExcelSheetContentByComObject {
    param (
        $sheet
    )

    $usedRange = $sheet.UsedRange
    $values = $usedRange.Value2
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($usedRange) | Out-Null
    $usedRange = $null

    $lines = @()

    if ($values -isnot [System.Array]) {
        if ($values) { $lines += $values.ToString() }
    }
    else {
        $rowCount = $values.GetLength(0)
        $colCount = $values.GetLength(1)

        for ($row = 1; $row -le $rowCount; $row++) {
            $lineArray = for ($col = 1; $col -le $colCount; $col++) {
                $val = $values[$row, $col]
                if ($val) { $val.ToString() }
            }
            if ($lineArray.Count -gt 0) {
                $lines += ($lineArray -join ' ')
            }
        }
    }

    return $lines -join "`n"
}


function Search-InXlsByComObject {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file,
        [hashtable]$deduplicatedMatches = @{}
    )

    $excel = $searchParams.appContext.features.excel

    $missing = [System.Type]::Missing
    $workbook = $null
    try {
        $workbook = $excel.Workbooks.Open(
            $file.FullName,  # 1 file path
            $false,          # 2 update links
            $true,           # 3 read only
            $missing,        # 4 format
            "'"              # 5 password
        )

        foreach ($sheet in $workbook.Worksheets) {
            if ($searchParams.appContext.state -ne "running") { return }
            try {
                $content = Get-ExcelSheetContentByComObject -sheet $sheet
                $null = Test-ContentForPatterns -searchParams $searchParams `
                    -content $content `
                    -filePath $file.FullName `
                    -fileName $file.Name `
                    -fileSize $file.Length `
                    -fileDate $file.LastWriteTime `
                    -deduplicatedMatches $deduplicatedMatches `
                    -prefix "$($sheet.Name): "
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sheet) | Out-Null
            }

        }

        return $true
    }
    catch {
        $errorCode = Get-ComErrorCode $_
        if ($errorCode -eq -2146827284) {
            $values = New-Object System.Collections.Specialized.OrderedDictionary
            $values.Add("#", 0)
            $values.Add("FilePath", $file.FullName)
            $values.Add("FileSize", $file.Length)
            $values.Add("FileDate", $file.LastWriteTime)
            $values.Add("Content", "[Password protected]")
            $values.Add("RuleDesc", "")
            &$searchParams.addToResult -searchParams $searchParams -values $values | Out-Null
            return $true
        }
        Write-DebugErrorLog $_
        return $false
    }

    finally {
        $workbook.Close([ref]$false)
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) | Out-Null
    }

    return $false
}
#endregion

function Search-InExcel {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file,
        [hashtable]$deduplicatedMatches = @{}
    )

    # try to use MS Excel com object because it is faster
    if ($searchParams.appContext.features.excel) { 
        $completed = Search-InXlsByComObject -searchParams $searchParams -file $file -deduplicatedMatches $deduplicatedMatches
        if ($completed) { return $true }
    }

    # try to use simple zip xml parser to seacrh in xlsx
    if ($searchParams.appContext.features.zip -and (Test-ZipHeader -file $file)) {
        return  Search-InXlsByXmlParsing -searchParams $searchParams -file $file -deduplicatedMatches $deduplicatedMatches
    }  
}