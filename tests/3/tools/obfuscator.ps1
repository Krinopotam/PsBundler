function Obfuscate-PS1File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,

        [Parameter(Mandatory=$false)]
        [string]$OutPath,

        [Parameter(Mandatory=$false)]
        [string[]]$Exclude = @(),

        [Parameter(Mandatory=$false)]
        [string]$Prefix = 'Use',          # префикс перед дефисом

        [Parameter(Mandatory=$false)]
        [int]$NameLength = 7,             # длина части после дефиса (>=1)

        [Parameter(Mandatory=$false)]
        [int]$RandomBytes = 6,            # оставлено для совместимости

        [Parameter(Mandatory=$false)]
        [switch]$ForceRegexFallback
    )

    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }

    if ($NameLength -lt 1) { throw "NameLength must be >= 1" }

    # --- Вспомогательная функция: генератор требуемых имён ---
    function New-ObfuscatedName {
        param(
            [int]$length = 7,
            [string]$prefix = 'Use',
            [hashtable]$used = $null
        )

        $letters = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()
        $rand = New-Object System.Random

        for ($attempt = 0; $attempt -lt 1000; $attempt++) {
            # первая буква — заглавная
            $firstIndex = $rand.Next(0, $letters.Length)
            $name = $letters[$firstIndex].ToString().ToUpper()

            # добавляем оставшиеся строчные
            for ($i = 1; $i -lt $length; $i++) {
                $idx = $rand.Next(0, $letters.Length)
                $name += $letters[$idx]
            }

            $full = "$prefix-$name"

            # безопасная проверка наличия в used: Values это коллекция, используем -contains
            if ($used -eq $null -or -not ($used.Values -contains $full)) {
                return $full
            }
            # иначе пробуем снова
        }

        throw "Не удалось сгенерировать уникальное имя после 1000 попыток."
    }

    $script = Get-Content -Raw -LiteralPath $Path

    # Подготовка refs для парсера
    $tokens = [System.Management.Automation.Language.Token[]]@()
    $errors = $null
    $tokensRef = [ref]$tokens
    $errorsRef = [ref]$errors

    $ast = $null
    $parseOk = $false

    if (-not $ForceRegexFallback) {
        try {
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($script, $tokensRef, $errorsRef)
            if ($tokensRef.Value -is [System.Management.Automation.Language.Token[]]) {
                $tokens = $tokensRef.Value
                $parseOk = $true
            }
        } catch {
            Write-Verbose "ParseInput threw: $_"
            $parseOk = $false
        }
    }

    # Собираем имена функций (опираемся на AST, иначе regex)
    $funcNames = @()
    if ($parseOk -and $ast) {
        $funcAsts = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        $funcNames = $funcAsts | ForEach-Object { $_.Name } | Where-Object { $_ -and ($_ -notin $Exclude) } | Sort-Object -Unique
    } else {
        Write-Warning "AST parser недоступен — используем regex fallback. Результат может быть менее точным."
        $fnRe = '(?mi)^\s*function\s+([a-zA-Z_][\w\-]*)\b'
        $matches = [regex]::Matches($script, $fnRe)
        foreach ($m in $matches) {
            $val = $m.Groups[1].Value
            if ($val -and ($val -notin $Exclude)) { $funcNames += $val }
        }
        $funcNames = $funcNames | Sort-Object -Unique
    }

    if (-not $funcNames -or $funcNames.Count -eq 0) {
        Write-Verbose "Функций не найдено. Ничего не делаю."
        return
    }

    # Генерация маппинга: ориг.имя -> новое имя (Use-<Capital><lower...>)
    $map = @{}
    foreach ($n in $funcNames) {
        $new = New-ObfuscatedName -length $NameLength -prefix $Prefix -used $map
        # убеждаемся, что не совпадает со старым именем и уникально
        while ($new -eq $n -or $map.Values -contains $new) {
            $new = New-ObfuscatedName -length $NameLength -prefix $Prefix -used $map
        }
        $map[$n] = $new
    }

    # --- Замены по токенам (без строк и комментов) ---
    if ($parseOk -and $tokens) {
        $replacements = New-Object System.Collections.ArrayList

        foreach ($tk in $tokens) {
            $kindName = $null
            try { $kindName = $tk.Kind.ToString() } catch { $kindName = '' }

            # пропускаем строки/комментарии
            if ($kindName -in @('StringLiteral','HereString','HereStringLiteral','HereStringDelimiter','Comment')) {
                continue
            }

            $text = $tk.Text
            if ($null -ne $text -and $map.ContainsKey($text)) {
                $start = $tk.Extent.StartOffset
                $end = $tk.Extent.EndOffset
                $len = $end - $start
                $replacements.Add([PSCustomObject]@{Start=$start; Length=$len; Replacement=$map[$text]}) | Out-Null
            }
        }

        if ($replacements.Count -gt 0) {
            $sb = [System.Text.StringBuilder]::new($script)
            $replacementsSorted = $replacements | Sort-Object -Property Start -Descending
            foreach ($r in $replacementsSorted) {
                $sb.Remove($r.Start, $r.Length) | Out-Null
                $sb.Insert($r.Start, $r.Replacement) | Out-Null
            }
            $script = $sb.ToString()
        } else {
            Write-Verbose "Совпадений по токенам не найдено."
        }
    }

    # --- Безопасная обработка функций внутри $() в строках ---
    $script = [regex]::Replace($script, '\$\(([^()]*(?:\([^()]*\)[^()]*)*)\)', {
        param($m)
        $inner = $m.Groups[1].Value
        foreach ($orig in $map.Keys) {
            $pattern = "\b$([Regex]::Escape($orig))\b"
            $inner = [regex]::Replace($inner, $pattern, $map[$orig])
        }
        return '$(' + $inner + ')'
    })

    # --- Regex fallback: на всякий случай (если парсер не использовался) ---
    if (-not $parseOk) {
        foreach ($orig in $map.Keys) {
            $pattern = "\b$([Regex]::Escape($orig))\b"
            $script = [regex]::Replace($script, $pattern, $map[$orig])
        }
    }

    if (-not $OutPath) {
        $base = [System.IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $Path).Path)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $ext = [System.IO.Path]::GetExtension($Path)
        $OutPath = Join-Path $base ("$name.obf$ext")
    }

    [System.IO.File]::WriteAllText($OutPath, $script, [System.Text.Encoding]::UTF8)

    return [PSCustomObject]@{
        Source = (Resolve-Path -LiteralPath $Path).Path
        Output = (Resolve-Path -LiteralPath $OutPath).Path
        RenamedCount = $map.Count
        Mapping = $map
        ParserUsed = $parseOk
    }
}






<#
Пример использования:
    $info = Obfuscate-PS1File -Path 'C:\scripts\myscript.ps1' -OutPath 'C:\scripts\myscript.obf.ps1'
    $info.Mapping | Format-Table

Ограничения и замечания:
- Функция использует токены парсера, поэтому замены не произойдут внутри строк/докстрингов и комментариев.
- Скрипт заменяет только имена, которые **объявлены** как функции в том же файле (т.е. найденные AST FunctionDefinitionAst). Это снижает риск переименования встроенных cmdlet'ов.
- Не обрабатываются динамические вызовы (Invoke-Expression с конкатенацией, вызов через & ("name"+...), вызовы через переменную $fn = 'Имя'; & $fn). Такие места остаются без изменений.
- При использовании модулей, dot-sourcing, переносе имён между файлами — учтите, что вызовы из других файлов не будут автоматически переименованы.
- Всегда тестируйте результат в безопасной среде (sandbox) перед запуском на production.
#>


Obfuscate-PS1File -Path 'd:\projects\repo\packages\powerShell\regexpSearch\build\test.ps1' -OutPath 'd:\projects\repo\packages\powerShell\regexpSearch\build\test.obf.ps1'