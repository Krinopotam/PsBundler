. "$PSScriptRoot/../../debounce.ps1"
. "$PSScriptRoot/../../../helpers/strings.ps1"

# Init Filter textBox panel
function Initialize-GridFilterPanel {
    param(
        [System.Windows.Forms.Control]$container,
        [System.Windows.Forms.DataGridView]$grid
    )

    $panelFilter = New-Object System.Windows.Forms.Panel

    $txtFilter = New-Object System.Windows.Forms.TextBox
    $txtFilter.Name = "txtFilter"
    $txtFilter.Left = 3
    $txtFilter.Width = 200
    $txtFilter.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $txtFilter.BackColor = [System.Drawing.Color]::LemonChiffon
    $txtFilter.Tag = $grid

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "X"
    $closeButton.Width = $txtFilter.Height
    $closeButton.Height = $txtFilter.Height
    $closeButton.Left = $txtFilter.Right + 3
    $closeButton.Top = $txtFilter.Top
    $closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeButton.FlatAppearance.BorderSize = 0
    $closeButton.Tag = $grid
    $closeButton.Add_Click({ 
            param($s, $e)
            $s.Parent.Controls["txtFilter"].Text = "" 
            $grid = $s.Tag
            $grid.Focus()
        })
    $panelFilter.Controls.Add($closeButton) | Out-Null

    $panelFilter.Height = $txtFilter.Height
    $panelFilter.Width = $closeButton.Right
    $panelFilter.Top = $grid.Bottom - $panelFilter.Height
    $panelFilter.Left = $grid.left
    $panelFilter.BackColor = $txtFilter.BackColor
    $panelFilter.Visible = $false
    $panelFilter.Anchor = "Bottom,Left"
    $panelFilter.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $panelFilter.Controls.Add($txtFilter) | Out-Null
    
    $container.Controls.Add($panelFilter) | Out-Null
    $panelFilter.BringToFront() | Out-Null

    $grid.Tag.panelFilter = $panelFilter
    $grid.Tag.txtFilter = $txtFilter
        

    $txtFilter.Add_KeyDown({
            param($s, $e)
            if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { 
                $s.Text = "" 
                $grid = $s.Tag
                $grid.Focus()
            }
        }) | Out-Null

    $txtFilter.Add_TextChanged({
            param($s, $e)
            $hasFilter = $s.Text.Length -gt 0
            $s.Parent.Visible = $hasFilter
            Start-Debounce -StateObj $s -Action { param($ctrl) Set-AdvancedGridFilter -txtFilter $ctrl }
        }) | Out-Null 

}

function Set-AdvancedGridFilter {
    param([System.Windows.Forms.TextBox]$txtFilter)
    
    $grid = $txtFilter.Tag
    $dt = $grid.DataSource
    $columns = $grid.Columns | Where-Object { $_.Visible }

    $filterText = $txtFilter.Text

    if (-not $filterText) { 
        $dt.RemoveFilter()
        $grid.DefaultCellStyle.BackColor = [System.Drawing.Color]::White
        return 
    }

    $finalFilter = $null

    $queryMode = Test-IsTextIsQueryFilter -text $filterText -columns $columns
    if ($queryMode) {
        try {
            $finalFilter = Get-GridQueryFilterString -text $filterText -grid $grid
            #Write-Host "--- filter: $finalFilter"
            $txtFilter.BackColor = [System.Drawing.Color]::LightBlue
            $txtFilter.Parent.BackColor = [System.Drawing.Color]::LightBlue
        }
        catch {
            #Write-Error "--- filter: $finalFilter, $($_.Exception.Message)"
            $txtFilter.BackColor = [System.Drawing.Color]::OrangeRed
            $txtFilter.Parent.BackColor = [System.Drawing.Color]::OrangeRed
            return
        }
    }
    else {
        $finalFilter = Get-GridSimpleFilterString -text $filterText -columns $columns
        $txtFilter.BackColor = [System.Drawing.Color]::LightYellow
        $txtFilter.Parent.BackColor = [System.Drawing.Color]::LightYellow
    }

    if (-not $finalFilter) {
        $dt.RemoveFilter()
        $grid.DefaultCellStyle.BackColor = [System.Drawing.Color]::White
        return
    }

    try {
        $dt.Filter = $finalFilter
        $grid.DefaultCellStyle.BackColor = [System.Drawing.Color]::LightCyan
    }
    catch {
        $txtFilter.BackColor = [System.Drawing.Color]::OrangeRed
        $txtFilter.Parent.BackColor = [System.Drawing.Color]::OrangeRed
    }

    return
}

function Test-IsTextIsQueryFilter {
    param(
        [string]$text,
        [System.Windows.Forms.DataGridViewColumn[]]$columns
    )

    if (-not $text) { return $false }

    return $text.StartsWith('==')
}

function Get-GridSimpleFilterString {
    param(
        [string]$text,
        [System.Windows.Forms.DataGridViewColumn[]]$columns
    )

    if (-not $text) { return $null }
    
    $text = Convert-EscapeRowFilterValue -value $text

    # --- Simple text mode ---
    $globalFilters = @()
    $isNumeric = $text -match '^-?\d+(\.\d+)?$'
    $isDate = $false
    $parsedDate = Convert-ToDateTime $text
    if ($parsedDate) { $isDate = $true }

    foreach ($col in $columns) {
        $colName = Convert-EscapeRowFilterValue -value $col.DataPropertyName
        $colType = $col.ValueType

        if (@([int], [long], [double]) -contains $colType -and $isNumeric) { 
            $globalFilters += "$colName = $text"
        }
        elseif ($colType -eq [datetime] -and $isDate) {
            $globalFilters += (Get-FlexibleDateFilter -parsedDate $parsedDate -colName $colName)
        }
        elseif ($colType -eq [string]) {
            $globalFilters += "$colName LIKE '%$text%'"
        }
    }

    if ($globalFilters.Count -gt 0) {
        return '(' + [string]::Join(' OR ', $globalFilters) + ')'
    }
    else {
        return $null
    }
}

function Get-FlexibleDateFilter {
    param(
        [datetime]$parsedDate,
        [string]$colName
    )

    if (-not $parsedDate) { return $null }

    $fmt = 'yyyy-MM-dd HH:mm:ss'
    $start = $parsedDate
    $end = $null

    if ($parsedDate.Second -ne 0) { $end = $parsedDate.AddSeconds(1) }
    elseif ($parsedDate.Minute -ne 0) { $end = $parsedDate.AddMinutes(1) }
    elseif ($parsedDate.Hour -ne 0) { $end = $parsedDate.AddHours(1) }
    elseif ($parsedDate.Day -ne 1) { $end = $parsedDate.AddDays(1) }
    elseif ($parsedDate.Month -ne 1) { $end = $parsedDate.AddMonths(1) }
    else { $end = $parsedDate.AddYears(1) }

    return "($colName >= #$($start.ToString($fmt))# AND $colName < #$($end.ToString($fmt))#)"
}


function Get-GridQueryFilterString {
    param(
        [string]$text,
        [System.Windows.Forms.DataGridView]$grid
    )

    if ($text -and $text.StartsWith('==')) { $text = $text.Substring(2).Trim() }
    if (-not $text) { return $null }

    # Tokenize: parentheses are separate tokens; quoted strings and #col tokens are preserved.
    $tokenPattern = '(\(|\)|[''][^'']*['']|[""][^""]*[""]|!=|>=|<=|=|>|<|LIKE|NOTLIKE|AND|OR|[^\s()=!<>]+)'

    $regMatches = [regex]::Matches($text, $tokenPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    $tokens = @()
    foreach ($m in $regMatches) { $tokens += $m.Value }

    if ($tokens.Count -eq 0) { return $null }

    $rootNode = Convert-GridFilterTokensToNodes -tokens $tokens -grid $grid
    $query = Convert-GridFilterNodesToQuery -rootNode $rootNode
    return $query
}

function Convert-GridFilterTokensToNodes {
    param(
        [string[]]$tokens,
        [System.Windows.Forms.DataGridView]$grid
    )

    function ConvertValue ($value, $type) {
        $value = Remove-SurroundingQuotes -Text $value
        if (-not $value) { return $null }
        $value = Convert-EscapeRowFilterValue -value $value

        try {
            if ($type -eq [string]) { return $value }
            if ($type -eq [bool]) { return Convert-ToBoolean $value }
            elseif ($type -eq [datetime]) { return  Convert-ToDateTime $value }
            else { return [System.Convert]::ChangeType($value, $type) }
        }
        catch {
            return $null
        }
    }
    

    $operators = @('=', '!=', '>', '<', '>=', '<=', 'LIKE', 'NOTLIKE')

    $root = @{ Type = 'Group'; Children = @(); Parent = $null }
    $currentGroup = $root
    $curExpression = $null
    $nextToken = "Column"
    $i = 0

    while ($i -lt $tokens.Count) {
        $token = $tokens[$i].Trim()
        $upperToken = $token.ToUpper()
        $i++

        # -------- Opening bracket -----------
        if ($upperToken -eq '(') {
            if ($nextToken -ne "Column") { Throw "Unexpected '('" } # Brackets must be before columns
            $newGroup = @{ Type = 'Group'; Children = @(); Parent = $currentGroup }
            $currentGroup.Children += , $newGroup
            $currentGroup = $newGroup
            $nextToken = "Column"
            $curExpression = $null
            continue
        }

        # -------- Closing bracket -----------
        if ($upperToken -eq ')') {
            if ($currentGroup.Parent) { $currentGroup = $currentGroup.Parent }
            $nextToken = "Logical"
            $curExpression = $null
            continue
        }

        # -------- Logical operator -------------
        if ($upperToken -eq 'AND' -or $upperToken -eq 'OR' ) {
            if ($nextToken -ne "Logical") { Throw "Unexpected logical operator" }
            $currentGroup.Children += , @{ Type = 'Logical'; Value = $token; Parent = $currentGroup }
            $nextToken = "Column"
            $curExpression = $null
            continue
        }
        
        # -------- Column -------------------------
        if ($nextToken -eq 'Column') {
            $columnToken = Remove-SurroundingQuotes -Text $token
            $column = Get-AdvancedGridColumnByToken -columnToken $columnToken -grid $grid
            $colName = $null
            $colType = [string]
            if ($column) { 
                $colName = $column.Name
                $colType = $column.ValueType
            }
            # it is OK, if column is not found. Null column name will be skipped later
            $curExpression = @{ Type = 'Expression'; Column = $colName; Operator = $null; Value = $null; Parent = $currentGroup; ColType = $colType }
            $currentGroup.Children += , $curExpression
            $nextToken = "Operator"
            continue

        }

        # -------- Operator -----------------------
        if ($operators -contains $upperToken -and $curExpression) {
            if ($nextToken -ne 'Operator') { Throw "Unexpected operator" }
            if ($curExpression.ColType -ne [string] -and ($upperToken -eq 'LIKE' -or $upperToken -eq 'NOTLIKE')) { Throw "LIKE/NOTLIKE operators is not allowed for non-string columns" }    
            $curExpression.Operator = $upperToken
            $nextToken = "Value"
            continue
        }

        # -------- Value without operator ---------
        if ($nextToken -eq 'Operator' -and $curExpression -and $upperToken -ne 'AND' -and $upperToken -ne 'OR') {
            $operator = 'LIKE'
            if ($curExpression.ColType -ne [string]) { $operator = '=' }
            $curExpression.Operator = $operator
            $curExpression.Value = ConvertValue -value $token -type $curExpression.ColType
            $curExpression = $null
            $nextToken = "Logical"
            continue
        }

        # -------- Value with operator ---------
        if ($nextToken -eq 'Value' -and $curExpression) {
            $curExpression.Value = ConvertValue -value $token -type $curExpression.ColType
            $curExpression = $null
            $nextToken = "Logical"
            continue
        }

        # -------- Unfinished expression -------
        if ($curExpression) {
            # If we got here, curExpression is not valid. Remove it from parent group
            $parent = $curExpression.Parent
            $parent.Children = $($parent.Children | Where-Object { -not [object]::ReferenceEquals($_, $curExpression) })
            $curExpression = $null
            $nextToken = "Column"
            continue
        }

        Throw "Unexpected token: $token"
    }

    return $root
}

function Convert-GridFilterNodesToQuery {
    param(
        [hashtable]$rootNode
    )

    function BuildGroup($children) {
        if (-not $children) { return $null }

        $parts = @()
        $prevWasLogical = $true  # from beginning we can insert Expression/Group
        $i = 0

        while ($i -lt $children.Count) {
            $child = $children[$i]
            $str = $null

            if ($child.Type -eq 'Expression' -and (IsNodeValid $child)) {
                $v = $child.Value
                $colType = $child.ColType

                if (@([int], [long], [double], [bool]) -contains $colType) { 
                    #keep as number without quotes
                }
                elseif ($colType -eq [datetime]) {
                    $v = "#$($v.ToString('yyyy-MM-dd HH:mm:ss'))#"
                }
                elseif ($child.Operator -eq 'LIKE' -OR $child.Operator -eq 'NOTLIKE') { $v = "'%$v%'" }
                else { $v = "'$v'" }

                $colName = Convert-EscapeRowFilterValue -value $child.Column
                if ($child.Operator -eq 'NOTLIKE') { 
                    $str = "NOT ($colName LIKE $v)"
                }
                elseif ($colType -eq [bool]) {
                    if ($v) { $str = "$colName = TRUE" }
                    else { $str = "($colName = FALSE) or ($colName IS NULL)" }
                }
                else {
                    $str = "$colName $($child.Operator) $v"
                }
            }
            elseif ($child.Type -eq 'Group') {
                $str = BuildGroup($child.Children)
                if ($str -and -not $prevWasLogical) {
                    # Group is not first and no logical operator before -> skip group entirely
                    $str = $null
                }
            }
            elseif ($child.Type -eq 'Logical') {
                # Check if next child exists and is valid
                $nextValid = $false
                if ($i + 1 -lt $children.Count) {
                    $nextChild = $children[$i + 1]
                    $nextValid = IsNodeValid $nextChild
                }

                if (-not $prevWasLogical -and $nextValid) {
                    $str = $child.Value
                }
            }

            if ($str) {
                $parts += $str
                $prevWasLogical = ($child.Type -eq 'Logical')
            }

            $i++
        }

        if ($parts.Count -eq 0) { return $null }

        return '(' + ($parts -join ' ') + ')'
    }

    function IsNodeValid($node) {
        if (-not $node) { return $false }

        switch ($node.Type) {
            'Expression' { return ($node.Column -and $node.Operator -and ($node.Value -or $node.Value -is [bool])) }
            'Group' {
                foreach ($c in $node.Children) {
                    if (IsNodeValid $c) { return $true }
                }
                return $false
            }
            default { return $false }
        }
    }

    $result = BuildGroup($rootNode.Children)

    # Remove outer parentheses if unnecessary
    if ($result -match '^\((.*)\)$') { $result = $matches[1] }

    return $result
}

# Get grid column by token. Token can be display index, column name or header title
function Get-AdvancedGridColumnByToken {
    param(
        [string]$columnToken,
        [System.Windows.Forms.DataGridView]$grid
    )

    $visibleCols = $grid.Columns | Where-Object { $_.Visible }

    if ($columnToken -match '^\d+$') {
        # columnToken is number → DisplayIndex
        $displayIndex = [int]$columnToken
        foreach ($c in $visibleCols) {
            if ($c.DisplayIndex + 1 -eq $displayIndex) { return $c }
        }
    }
    else {
        # columnToken is string → match by Name or HeaderText
        foreach ($c in $visibleCols) {
            if ($c.Name -ieq $columnToken -or $c.HeaderText -ieq $columnToken) { return $c }
        }
    }

    return $null
}

# Convert string for using in DataGridView filter
function Convert-EscapeRowFilterValue($value) {
    if (-not $value) { return "" }

    $escaped = $value

    # Double single quotes for string in filter
    $escaped = $escaped.Replace("'", "''")

    # Escape special characters [, ], %, _, *
    $escaped = $escaped.Replace("[", "[[]")
    #$escaped = $escaped.Replace("]", "[]]")
    $escaped = $escaped.Replace("#", "[#]")
    $escaped = $escaped.Replace("%", "[%]")
    $escaped = $escaped.Replace("_", "[_]")
    $escaped = $escaped.Replace("*", "[*]")

    return $escaped
}