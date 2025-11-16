function Initialize-AdvancedGridButtons {
    param (
        [System.Windows.Forms.Control]$Container,
        [hashtable[]]$Buttons,
        [int]$PaddingRight,
        [int]$PaddingTop
    )

    $spacing = 10
    $y = $PaddingTop - 4
    $x = $Container.ClientSize.Width - $PaddingRight

    for ($i = $buttons.Count - 1; $i -ge 0; $i--) {
        $btnInfo = $buttons[$i]

        if ($btnInfo.type -eq "button") {
            $ctrl = New-Object System.Windows.Forms.Button
        }
        else { contunue }

        $ctrl.Text = $btnInfo.name
        $ctrl.Width = $btnInfo.width
        $ctrl.Height = $btnInfo.height
        $ctrl.Add_Click($btnInfo.onClick)

        $x -= $ctrl.Width
        $ctrl.Left = $x
        $ctrl.Top = $y
        $ctrl.Anchor = "Top,Right"
        $Container.Controls.Add($ctrl)

        $x -= $spacing
    }
}