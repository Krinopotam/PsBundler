    Class MyClassA {
        MyClassA() {
            Write-Host "MyClassA"
        }

    }


$sb = {
    "111111"

}

Write-Host (& $sb)
