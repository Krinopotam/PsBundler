Class MyTest {
    [string]GetVar() {
        return "var 2"
    }
}

$var = [MyTest]::new()
$var.GetVar()
[MyTest].Assembly