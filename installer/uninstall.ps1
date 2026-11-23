#Requires -Version 5.1
<#
  关窗 —— 卸载脚本
  作用：删除计划任务、快捷方式和程序文件。
#>
$ErrorActionPreference = 'Continue'

$install = Join-Path $env:LOCALAPPDATA 'OneClickCloseAll'
$logFile = Join-Path $env:TEMP 'guanchuang-uninstall.log'
$TaskName = 'OneClickCloseAll'

function Show-Msg([string]$text, [string]$title, [string]$icon) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($text, $title,
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]$icon)
}

function Log([string]$text) {
    Add-Content -LiteralPath $logFile -Value ("[" + (Get-Date -Format 'HH:mm:ss') + "] " + $text) -Encoding UTF8
}

try {
    Set-Content -LiteralPath $logFile -Value '' -Encoding UTF8

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        try {
            # 用 -Command 而不是 -File：ShellExecute 提权时中文/空格路径用 -File 会出错
            $inner = "& '" + $PSCommandPath + "'"
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList (
                '-NoProfile -ExecutionPolicy Bypass -Command "' + $inner + '"')
        }
        catch {
            Show-Msg "卸载需要管理员权限，你刚刚取消了授权。" '关窗 卸载' 'Warning'
        }
        exit 0
    }

    Log '开始卸载'

    # 1. 删除计划任务
    & schtasks /delete /tn $TaskName /f 2>&1 | Out-Null
    Log '已删除计划任务（如果本来存在的话）'

    # 2. 删除快捷方式
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    foreach ($lnk in (Join-Path $desktop '关窗.lnk'), (Join-Path $startMenu '关窗.lnk')) {
        Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
    }
    Log '已删除快捷方式'

    # 3. 让当前正在运行的程序先退出，再删目录
    Get-Process -Name '关窗' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $install -Recurse -Force -ErrorAction SilentlyContinue
    Log "已删除目录 $install"

    Show-Msg "卸载完成。`n`n任务栏上的图标如果还在，右键它 →「从任务栏取消固定」。" '关窗 卸载' 'Information'
}
catch {
    Log ("错误：" + $_.Exception.Message)
    Show-Msg ("卸载时出错：`n" + $_.Exception.Message) '关窗 卸载' 'Error'
}
