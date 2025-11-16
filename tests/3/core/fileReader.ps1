. "$PSScriptRoot/../core/searchRegex.ps1"
. "$PSScriptRoot/../helpers/files.ps1"

#region ###################### Simple read and search whole file at once with default (win-1251) encoding ######################
function Read-FileSimpleMethod {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file
    )

    if ($searchParams.appContext.state -ne "running") { return }

    try {
        $content = Get-Content $file.FullName -Raw -ErrorAction Stop
        $deduplicatedMatches = @{}
        $null = Test-ContentForPatterns -searchParams $searchParams `
            -content $content `
            -filePath $file.FullName `
            -fileName $file.Name `
            -fileSize $file.Length `
            -fileDate $file.LastWriteTime `
            -deduplicatedMatches $deduplicatedMatches
    }
    catch {
        Write-DebugErrorLog $_
    }
}

#region ###################### Read and search whole file content at once ######################
function Read-FileAtOnce {
    param (
        [hashtable]$searchParams,
        [System.IO.FileInfo]$file, 
        [hashtable]$deduplicatedMatches = @{}
    )
    
    $stream = $null
    
    try {
        $stream = New-Object System.IO.FileStream (
            $file.FullName,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
    
        Read-StreamContent -stream $stream -searchParams $searchParams -filePath $file.FullName -fileName $file.Name -fileSize $file.Length -fileDate $file.LastWriteTime -deduplicatedMatches $deduplicatedMatches | Out-Null
    }
    catch {
        Write-DebugErrorLog $_
    }
    finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Read-StreamContent {
    param(
        [System.IO.Stream]$stream,
        [hashtable]$searchParams,
        [string]$filePath,
        [string]$fileName,
        [long]$fileSize,
        [datetime]$fileDate,
        [string]$prefix = "",
        [string]$postfix = "",
        [hashtable]$deduplicatedMatches = @{}
    )

    # Be aware, $filePath and $fileName may belong to different files in case of nested zip. $filePath is zip-file path (to show in result grid), but $fileName is file name in zip

    try {
        $buffer = New-Object byte[] $stream.Length
        $stream.Read($buffer, 0, $buffer.Length) | Out-Null
    
        $encoding = Get-EncodingsByBomDetection -Buffer $buffer
        if ($encoding) {
            $content = $encoding.GetString($buffer)
            $null = Test-ContentForPatterns -searchParams $searchParams `
                -content $content `
                -filePath $filePath `
                -fileName $fileName `
                -fileSize $fileSize `
                -fileDate $fileDate `
                -deduplicatedMatches $deduplicatedMatches `
                -prefix $prefix `
                -postfix $postfix
            return 
        }

        foreach ($name in $searchParams.encodings) {
            try {
                $encoding = [System.Text.Encoding]::GetEncoding($name)
                $content = $encoding.GetString($buffer)
                $null = Test-ContentForPatterns -searchParams $searchParams `
                    -content $content `
                    -filePath $filePath `
                    -fileName $fileName `
                    -fileSize $fileSize `
                    -fileDate $fileDate `
                    -deduplicatedMatches $deduplicatedMatches `
                    -prefix $prefix `
                    -postfix $postfix
            }
            catch {
                continue
            }
        }
    }
    catch {
        Write-DebugErrorLog $_
    }
}
#endregion

