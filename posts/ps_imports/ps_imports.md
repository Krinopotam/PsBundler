# Импорты модулей в PowerShell: когда хочется как в JavaScript #


Предположим, у нас есть 2 модуля `module1.psm1` и `module2.psm1`, в которых есть функции с одинаковыми названиями `Use-Test`:

```powershell
######## module1.psm1 #########
function Use-Test {
    Write-Host "I am Use-Test from module1"
}

######## module2.psm1 #########
function Use-Test {
    Write-Host "I am Use-Test from module2"
}

```

Если мы последовательно импортируем оба этих модуля и вызовем функцию `Use-Test`, то сработает функция из второго модуля, который был импортирован последним.

```powershell
Import-Module "$PSScriptRoot\module1.psm1"
Import-Module "$PSScriptRoot\module2.psm1"

Use-Test
```

```output
I am Use-Test from module2
```

Получается, что функция из модуля 2 "перезатерла" одноименную функции из модуля 1.

Но это не в полной мере так. Если мы выполним команду `Get-Command Use-Test -All`, то мы увидим, что в нашей сессии на самом деле 2 версии функции `Use-Test`, одна из `module1`, вторая из `module2`.

```output
>Get-Command Use-test -All

CommandType     Name           Version    Source
-----------     ----           -------    ------
Function        Use-Test       0.0        module2
Function        Use-Test       0.0        module1
```

И к каждой из версий мы можем обратиться по квалифицированному имени, указав имя модуля:

```powershell
module1\Use-Test
module2\Use-Test
```

```output
Use-Test from module1.psm1
Use-Test from module2.psm1
```

При этом, если `Use-Test` в обоих модулях вызывает другую одноименную функцию, например `Use-SubTest`, то PowerShell сначала попытается найти и вызвать эту функцию в соответствующем модуле, а потом и во всей области видимости сессии.