#Requires -Version 5.1
# 需要以管理员身份运行：注册“最高权限”计划任务，并创建「关窗」快捷方式
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'OneClickCloseAll'),
    [string]$TaskName = 'OneClickCloseAll',
    [string]$LogFile = (Join-Path $env:LOCALAPPDATA 'OneClickCloseAll\setup.log')
)

$ErrorActionPreference = 'Stop'
$lines = @()
function Write-Log([string]$text) {
    $script:lines += $text
    Set-Content -LiteralPath $LogFile -Value ($script:lines -join "`r`n") -Encoding UTF8
}

try {
    Write-Log "开始 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Log "身份: $($identity.Name)  管理员: $isAdmin"
    if (-not $isAdmin) { throw '需要管理员权限运行' }

    $scriptPath = Join-Path $InstallDir 'CloseAllWindows.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw "找不到 $scriptPath" }
    $psExe = Join-Path $PSHOME 'powershell.exe'
    Write-Log "脚本: $scriptPath"

    $action = New-ScheduledTaskAction -Execute $psExe `
        -Argument ('-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $scriptPath + '"') `
        -WorkingDirectory $InstallDir
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $taskPrincipal `
        -Settings $settings -Description '一键关闭所有窗口（提权运行）' -Force | Out-Null
    Write-Log '计划任务已注册'

    $task = Get-ScheduledTask -TaskName $TaskName
    Write-Log ("任务: {0}  RunLevel={1}  LogonType={2}" -f $task.State, $task.Principal.RunLevel, $task.Principal.LogonType)

    # 快捷方式：优先指向启动器 exe，没有就退回 schtasks
    $launcher = Join-Path $InstallDir '关窗.exe'
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $ws = New-Object -ComObject WScript.Shell

    foreach ($lnkPath in (Join-Path $desktop '关窗.lnk'), (Join-Path $startMenu '关窗.lnk')) {
        $lnk = $ws.CreateShortcut($lnkPath)
        if (Test-Path -LiteralPath $launcher) {
            $lnk.TargetPath = $launcher
            $lnk.WorkingDirectory = $InstallDir
            $lnk.IconLocation = "$launcher,0"
        }
        else {
            $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\schtasks.exe'
            $lnk.Arguments = '/run /tn "' + $TaskName + '"'
            $lnk.WorkingDirectory = Join-Path $env:SystemRoot 'System32'
            $lnk.IconLocation = (Join-Path $InstallDir 'closeall.ico') + ',0'
        }
        $lnk.Description = '一键关闭所有窗口'
        $lnk.Hotkey = 'CTRL+ALT+SHIFT+Q'
        $lnk.WindowStyle = 1
        $lnk.Save()
        Write-Log "快捷方式已创建: $lnkPath"
    }

    Write-Log 'OK'
}
catch {
    Write-Log ('ERROR: ' + $_.Exception.Message)
    exit 1
}
exit 0
