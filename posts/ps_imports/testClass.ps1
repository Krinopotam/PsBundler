using assembly System.Windows.Forms

$code = @'
Class MyClass {
    [System.Windows.Forms.Form]$form
    MyClass() {
        $this.form = [System.Windows.Forms.Form]::new()
        $txt = @"
        test1 row
        test2 row
"@

        Write-Host $txt
    }
}
'@


 Invoke-Expression $code
 $cl = [MyClass]::New()