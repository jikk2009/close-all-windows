#Requires -Version 5.1
<#
  关窗 —— 安装脚本
  作用：把程序装到当前用户目录、注册提权计划任务、创建「关窗」快捷方式。
  需要管理员权限（会自动弹 UAC 请求）。
#>
param([switch]$Silent)

$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$install = Join-Path $env:LOCALAPPDATA 'OneClickCloseAll'
$logFile = Join-Path $env:TEMP 'guanchuang-install.log'
$TaskName = 'OneClickCloseAll'

function Log([string]$text) {
    Add-Content -LiteralPath $logFile -Value ("[" + (Get-Date -Format 'HH:mm:ss') + "] " + $text) -Encoding UTF8
}

function Show-Msg([string]$text, [string]$title, [string]$icon) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($text, $title,
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]$icon)
}

try {
    Set-Content -LiteralPath $logFile -Value '' -Encoding UTF8

    # 1. 没有管理员权限就重新以管理员身份启动自己
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log '当前不是管理员，请求提权'
        try {
            # 用 -Command 而不是 -File：ShellExecute 提权时中文/空格路径用 -File 会出错
            $inner = "& '" + $PSCommandPath + "'"
            if ($Silent) { $inner += ' -Silent' }
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList (
                '-NoProfile -ExecutionPolicy Bypass -Command "' + $inner + '"')
        }
        catch {
            Show-Msg "安装需要管理员权限，你刚刚取消了授权。`n`n请重新右键「安装.cmd」→ 以管理员身份运行。" '关窗 安装' 'Warning'
        }
        exit 0
    }

    Log '开始安装'

    # 2. 检查安装包里的文件是否齐全
    $files = @('关窗.exe', 'CloseAllWindows.ps1', 'CloseAllWindows.Ui.ps1', 'closeall.ico')
    foreach ($f in $files) {
        $p = Join-Path $here $f
        if (-not (Test-Path -LiteralPath $p)) { throw "安装包不完整，缺少：$f" }
    }

    # 3. 复制到用户目录
    New-Item -ItemType Directory -Path $install -Force | Out-Null
    foreach ($f in $files) {
        Copy-Item -LiteralPath (Join-Path $here $f) -Destination (Join-Path $install $f) -Force
    }
    Log "已复制文件到 $install"

    # 4. 注册“最高权限”计划任务（这样普通双击也能关掉管理员程序）
    $scriptPath = Join-Path $install 'CloseAllWindows.ps1'
    $psExe = Join-Path $PSHOME 'powershell.exe'
    $action = New-ScheduledTaskAction -Execute $psExe `
        -Argument ('-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $scriptPath + '"') `
        -WorkingDirectory $install
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $taskPrincipal `
        -Settings $settings -Description '关窗：一键关闭所有窗口（提权运行）' -Force | Out-Null
    Log '计划任务已注册'

    # 5. 创建快捷方式（桌面 + 开始菜单，后者用于固定到任务栏）
    $launcher = Join-Path $install '关窗.exe'
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $ws = New-Object -ComObject WScript.Shell
    foreach ($lnkPath in (Join-Path $desktop '关窗.lnk'), (Join-Path $startMenu '关窗.lnk')) {
        $lnk = $ws.CreateShortcut($lnkPath)
        $lnk.TargetPath = $launcher
        $lnk.WorkingDirectory = $install
        $lnk.IconLocation = "$launcher,0"
        $lnk.Description = '一键关闭所有窗口'
        $lnk.Hotkey = 'CTRL+ALT+SHIFT+Q'
        $lnk.WindowStyle = 1
        $lnk.Save()
        Log "已创建快捷方式：$lnkPath"
    }

    Log '安装完成'
    if (-not $Silent) { Show-Msg "安装完成！`n`n· 桌面和开始菜单里已经有「关窗」`n· 双击就能关掉所有打开的窗口`n`n想固定到任务栏：`n打开「开始」菜单 → 搜索「关窗」→ 右键 → 固定到任务栏" '关窗 安装' 'Information' }
}
catch {
    Log ("错误：" + $_.Exception.Message)
    Show-Msg ("安装失败：`n" + $_.Exception.Message + "`n`n日志：" + $logFile) '关窗 安装' 'Error'
    exit 1
}
