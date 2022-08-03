New-Variable -Name sfdxCommands -Scope Script -Force
New-Variable -Name sfdxCommandsFile -Scope Global -Force

$global:sfdxCommandsFile = "$HOME/.sfdxcommands.json"

<# The below script is executed in the background when a new ps session starts to pull all sfdx commands into a variable #>
$sfdxCommandsFileCreateBlock = {
    Param($sfdxCommandsFile)
    $tempCommandsFile = "$HOME/.sfdxcommandsinit.json"
    sfdx commands --hidden --json | Out-File -FilePath $tempCommandsFile
    Move-Item -Path $tempCommandsFile -Destination $sfdxCommandsFile -Force
    return Get-Content $sfdxCommandsFile | ConvertFrom-Json
}

<# Check if the command file exists. If not - create it. This is to ensure less frequent executions. #>
if( -not (Test-Path -Path $global:sfdxCommandsFile -PathType Leaf)){
    $sfdxCommandsFileCreateJob = Start-Job -ScriptBlock $sfdxCommandsFileCreateBlock -argumentlist $global:sfdxCommandsFile
}

<# Check if the command file has not updated more than 10 days. If so - update it. #>
if((Test-Path -Path $global:sfdxCommandsFile -PathType Leaf) && Test-Path $global:sfdxCommandsFile -OlderThan (Get-Date).AddDays(-10)){
    $lastWrite = (get-item $global:sfdxCommandsFile).LastWriteTime
    $timespan = new-timespan -days 10
    if (((Get-Date) - $lastWrite) -gt $timespan) {
        $sfdxCommandsFileCreateJob = Start-Job -ScriptBlock $sfdxCommandsFileCreateBlock -argumentlist $global:sfdxCommandsFile
    }
}

<# script block for autocomplete. looks up matching commands from the file created above #>
$scriptBlock = {
    param($wordToComplete, $commandAst, $cursorPosition)

    if (!$script:sfdxCommands) {
        if (Test-Path $global:sfdxCommandsFile -PathType Leaf) {
            $script:sfdxCommands = Get-Content $global:sfdxCommandsFile | ConvertFrom-Json
        }
        else {
            $script:sfdxCommands = Receive-Job -Wait -Job $sfdxCommandsFileCreateJob
        }
    }

    if ($commandAst.CommandElements.Count -eq 1) {
        <# List all commands #>
        $script:sfdxCommands | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_.id, $_.id, 'Method', $_.description)
        }
    }
    elseif ($commandAst.CommandElements.Count -eq 2 -and $wordToComplete -ne "") {
        <# Completing a command #>
        $commandPattern = ".*" + $commandAst.CommandElements[1].Value + ".*" <# Complete if force: is not specified too #>
        $script:sfdxCommands | Where-Object id -match $commandPattern | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_.id, $_.id, 'Method', $_.description)
        }
    }
    elseif ($commandAst.CommandElements.Count -gt 2) {
        <# Completing a parameter #>
        $parameterToMatch = $commandAst.CommandElements[-1].ToString().TrimStart("-") + "*";
        
        ($script:sfdxCommands | Where-Object id -eq $commandAst.CommandElements[1].Value).flags.PsObject.Properties | Where-Object Name -like $parameterToMatch | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new("--" + $_.Value.name, $_.Value.name, 'ParameterName', $_.Value.description)
        }
    }
}
<# register the above script to fire when tab is pressed following the sfdx command#>
Register-ArgumentCompleter -Native -CommandName sfdx -ScriptBlock $scriptBlock
