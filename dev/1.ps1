$ITERATIONS = 10000
$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($n = 0; $n -lt $ITERATIONS; $n++) {
    # Inline code copied directly here
    $sum = 0
    for ($i = 0; $i -lt 50; $i++) {
        $sum += [math]::Sqrt($i * 123.45)
    }
    $values = 1..5 | ForEach-Object { $_ * 3 }
    $text = ($values | ForEach-Object { "Num=$_" }) -join ", "
    if ($sum -gt 500) {
        $msg = "High sum"
    }
    elseif ($sum -gt 100) {
        $msg = "Medium sum"
    }
    else {
        $msg = "Low sum"
    }
    $rand = Get-Random -Minimum 10 -Maximum 99
    $result = "$msg : $sum ($text) rand=$rand"
    $result = $result.ToUpper()
    $result | Out-Null
}
$sw.Stop()
$t1 = $sw.Elapsed

# --- Variant 2: ScriptBlock.Invoke() ---
$sb = {
    # Inline code copied directly here
    $sum = 0
    for ($i = 0; $i -lt 50; $i++) {
        $sum += [math]::Sqrt($i * 123.45)
    }
    $values = 1..5 | ForEach-Object { $_ * 3 }
    $text = ($values | ForEach-Object { "Num=$_" }) -join ", "
    if ($sum -gt 500) {
        $msg = "High sum"
    }
    elseif ($sum -gt 100) {
        $msg = "Medium sum"
    }
    else {
        $msg = "Low sum"
    }
    $rand = Get-Random -Minimum 10 -Maximum 99
    $result = "$msg : $sum ($text) rand=$rand"
    $result = $result.ToUpper()
    $result | Out-Null
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($n = 0; $n -lt $ITERATIONS; $n++) {
    $null = $sb.Invoke()
}
$sw.Stop()
$t2 = $sw.Elapsed

$raw = $sb.ToString()

$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($n = 0; $n -lt $ITERATIONS; $n++) {
    Invoke-Expression $sb.ToString()
}
$sw.Stop()
$t3 = $sw.Elapsed

$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($n = 0; $n -lt $ITERATIONS; $n++) {
    & $sb | Out-Null
}
$sw.Stop()
$t4 = $sw.Elapsed

# --- Output ---
Write-Host ""
Write-Host "Iterations: $ITERATIONS"
Write-Host ("Inline:                   {0,10:N2} ms" -f $t1.TotalMilliseconds)
Write-Host ("ScriptBlock.Invoke():     {0,10:N2} ms" -f $t2.TotalMilliseconds)
Write-Host ("ToString()+IEX:           {0,10:N2} ms" -f $t3.TotalMilliseconds)
Write-Host ("& ToString()+IEX:           {0,10:N2} ms" -f $t4.TotalMilliseconds)
Write-Host ""
Write-Host ("Invoke() slowdown:        x{0}" -f [Math]::Round($t2.TotalMilliseconds / $t1.TotalMilliseconds, 2))
Write-Host ("ToString()+IEX slowdown:  x{0}" -f [Math]::Round($t3.TotalMilliseconds / $t1.TotalMilliseconds, 2))
