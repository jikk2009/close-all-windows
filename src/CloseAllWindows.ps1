#Requires -Version 5.1
<#
.SYNOPSIS
    一键关闭当前所有可见的程序窗口。

.DESCRIPTION
    默认「单击即关」：双击快捷方式后直接开始关闭，不弹任何窗口。
    关闭方式是给每个窗口发送正常的“关闭”消息（相当于点窗口右上角的 X），
    所以有未保存内容的程序仍会自己弹出保存提示，不会悄悄丢数据。

.PARAMETER Confirm
    关闭前先弹出确认框，列出来要关的窗口（需要“先看一眼”时用）。

.PARAMETER DryRun
    只列出将要关闭的窗口，不执行任何关闭操作。

.PARAMETER Force
    对无响应的程序直接强制结束进程（默认不强杀）。

.PARAMETER Exclude
    额外排除的进程名，例如  -Exclude chrome,Code

.PARAMETER TimeoutSeconds
    等待窗口自行关闭的秒数，默认 8 秒。

.EXAMPLE
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\CloseAllWindows.ps1
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\CloseAllWindows.ps1 -Confirm
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\CloseAllWindows.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [switch]$Confirm,
    [switch]$DryRun,
    [switch]$Force,
    [string[]]$Exclude = @(),
    [int]$TimeoutSeconds = 8,
    [switch]$NoDialog
)

# ===================== 可按需修改的设置 =====================

# 永远不“强制结束”的进程（关掉它们会导致桌面/输入法/系统组件异常）
$NeverKill = @(
    'explorer', 'dwm', 'winlogon', 'csrss', 'wininit', 'services', 'lsass',
    'smss', 'svchost', 'system', 'registry', 'idle', 'memory compression',
    'audiodg', 'sihost', 'taskhostw', 'fontdrvhost', 'spoolsv',
    'applicationframehost', 'shellexperiencehost', 'startmenuexperiencehost',
    'searchhost', 'textinputhost', 'lockapp', 'logonui', 'securityhealthservice'
)

# 这些窗口类不是“程序窗口”，一律跳过
$SkipWindowClasses = @(
    'Progman', 'WorkerW', 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd',
    'Windows.UI.Core.CoreWindow', 'ApplicationManager_DesktopShellWindow',
    'MultitaskingViewFrame', 'ForegroundStaging', 'XamlExplorerHostIslandWindow',
    'Windows.Internal.Shell.TabProxyWindow', 'NotifyIconOverflowWindow'
)

# 你希望“永远不关闭”的程序（进程名，不带 .exe，多个用逗号隔开）。
# 默认排除 DeepSeek Harness 自己：否则一键关闭会把当前这个对话窗口一起关掉。
# 想把 DSH 也一起关掉，就把下面改成：$UserExclude = @()
# 想再保留浏览器：$UserExclude = @('DeepSeek Harness', 'chrome', 'msedge')
$UserExclude = @('DeepSeek Harness')

# ===========================================================

$ErrorActionPreference = 'Stop'

$uiFile = Join-Path $PSScriptRoot 'CloseAllWindows.Ui.ps1'
if (-not (Test-Path -LiteralPath $uiFile)) {
    throw "缺少界面文件：$uiFile"
}
. $uiFile

# ---------- Win32 封装 ----------
if (-not ('CloseAllWindows.Native' -as [type])) {
    $src = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace CloseAllWindows
{
    public class WindowInfo
    {
        public IntPtr Handle;
        public string Title;
        public string ClassName;
        public uint ProcessId;
        public string ProcessName;
        public bool Hung;
    }

    public static class Native
    {
        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr hWnd, StringBuilder text, int maxCount);

        [DllImport("user32.dll")]
        public static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool IsHungAppWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll")]
        private static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);

        [DllImport("user32.dll")]
        public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int index);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
        private static extern int GetWindowLong32(IntPtr hWnd, int index);

        [DllImport("dwmapi.dll")]
        private static extern int DwmGetWindowAttribute(IntPtr hWnd, int attribute, out int value, int size);

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_BASIC_INFORMATION
        {
            public IntPtr Reserved1;
            public IntPtr PebBaseAddress;
            public IntPtr Reserved2_0;
            public IntPtr Reserved2_1;
            public IntPtr UniqueProcessId;
            public IntPtr InheritedFromUniqueProcessId;
        }

        [DllImport("ntdll.dll")]
        private static extern int NtQueryInformationProcess(IntPtr processHandle, int processInformationClass,
            ref PROCESS_BASIC_INFORMATION processInformation, int processInformationLength, out int returnLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(int access, bool inheritHandle, int processId);

        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        private const int GWL_EXSTYLE = -20;
        private const long WS_EX_TOOLWINDOW = 0x00000080L;
        private const long WS_EX_TRANSPARENT = 0x00000020L;
        private const long WS_EX_NOACTIVATE = 0x08000000L;
        private const int DWMWA_CLOAKED = 14;

        private static IntPtr GetWindowLongPtrSafe(IntPtr hWnd, int index)
        {
            if (IntPtr.Size == 8) return GetWindowLongPtr64(hWnd, index);
            return new IntPtr(GetWindowLong32(hWnd, index));
        }

        // 有“宿主窗口”的窗口（弹出对话框等）不算独立窗口，它们会跟随主窗口一起关闭
        private static bool HasOwner(IntPtr hWnd)
        {
            return GetWindow(hWnd, 4) != IntPtr.Zero; // GW_OWNER
        }

        public static List<WindowInfo> Enumerate()
        {
            List<WindowInfo> list = new List<WindowInfo>();

            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
            {
                if (!IsWindowVisible(hWnd)) return true;
                if (GetWindowTextLength(hWnd) == 0) return true;
                if (HasOwner(hWnd)) return true;

                int cloaked = 0;
                if (DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out cloaked, sizeof(int)) == 0 && cloaked != 0)
                    return true;

                long exStyle = GetWindowLongPtrSafe(hWnd, GWL_EXSTYLE).ToInt64();
                if ((exStyle & WS_EX_TOOLWINDOW) != 0) return true;
                if ((exStyle & WS_EX_NOACTIVATE) != 0) return true;
                if ((exStyle & WS_EX_TRANSPARENT) != 0) return true;

                StringBuilder title = new StringBuilder(1024);
                GetWindowText(hWnd, title, title.Capacity);
                StringBuilder cls = new StringBuilder(256);
                GetClassName(hWnd, cls, cls.Capacity);

                uint pid;
                GetWindowThreadProcessId(hWnd, out pid);

                string processName = "";
                try { processName = Process.GetProcessById((int)pid).ProcessName; }
                catch { }

                WindowInfo info = new WindowInfo();
                info.Handle = hWnd;
                info.Title = title.ToString().Trim();
                info.ClassName = cls.ToString();
                info.ProcessId = pid;
                info.ProcessName = processName;
                info.Hung = IsHungAppWindow(hWnd);
                list.Add(info);

                return true;
            }, IntPtr.Zero);

            return list;
        }

        public static int GetWindowOwnerPid(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return 0;
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            return (int)pid;
        }

        public static int GetParentProcessId(int processId)
        {
            IntPtr handle = OpenProcess(0x1000, false, processId); // PROCESS_QUERY_LIMITED_INFORMATION
            if (handle == IntPtr.Zero) return 0;
            try
            {
                PROCESS_BASIC_INFORMATION info = new PROCESS_BASIC_INFORMATION();
                int length;
                int status = NtQueryInformationProcess(handle, 0, ref info,
                    Marshal.SizeOf(typeof(PROCESS_BASIC_INFORMATION)), out length);
                if (status != 0) return 0;
                return info.InheritedFromUniqueProcessId.ToInt32();
            }
            finally { CloseHandle(handle); }
        }
    }
}
'@
    Add-Type -TypeDefinition $src -Language CSharp
}

# ---------- 辅助函数 ----------

function Test-WindowAlive {
    param([IntPtr]$Handle)
    ([CloseAllWindows.Native]::IsWindow($Handle) -and [CloseAllWindows.Native]::IsWindowVisible($Handle))
}

function Write-RunLog {
    param([string]$Text)
    try {
        $dir = Join-Path $env:LOCALAPPDATA 'OneClickCloseAll'
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Set-Content -LiteralPath (Join-Path $dir 'last-run.log') -Value $Text -Encoding UTF8
    }
    catch { }
}

# ---------- 1. 收集窗口 ----------
try {
    $allWindows = @([CloseAllWindows.Native]::Enumerate())
}
catch {
    $msg = '枚举窗口失败：' + $_.Exception.Message
    if (-not $DryRun) {
        [void][System.Windows.Forms.MessageBox]::Show($msg, '一键关闭所有窗口',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    else { Write-Error $msg }
    exit 1
}

# 保护自己：本进程、父进程链（终端/资源管理器等）、本进程的控制台窗口
$protectClose = New-Object 'System.Collections.Generic.HashSet[int]'
$protectKill = New-Object 'System.Collections.Generic.HashSet[int]'
[void]$protectClose.Add([int]$PID)
[void]$protectKill.Add([int]$PID)

$parent = [int]$PID
for ($i = 0; $i -lt 5; $i++) {
    $parent = [CloseAllWindows.Native]::GetParentProcessId($parent)
    if ($parent -le 4) { break }
    $parentName = ''
    try { $parentName = (Get-Process -Id $parent -ErrorAction Stop).ProcessName.ToLowerInvariant() } catch { }
    # 从桌面快捷方式启动时父进程是 explorer，不能因此排除所有文件夹窗口
    if ($parentName -ne 'explorer') { [void]$protectClose.Add($parent) }
    [void]$protectKill.Add($parent)
}

$consoleHandle = [CloseAllWindows.Native]::GetConsoleWindow()
$consolePid = 0
if ($consoleHandle -ne [IntPtr]::Zero) {
    $consolePid = [CloseAllWindows.Native]::GetWindowOwnerPid($consoleHandle)
    if ($consolePid -gt 4) {
        [void]$protectClose.Add($consolePid)
        [void]$protectKill.Add($consolePid)
    }
}

$excludeList = @()
foreach ($item in ($Exclude + $UserExclude)) {
    if ([string]::IsNullOrWhiteSpace($item)) { continue }
    # 支持 -Exclude "chrome,msedge"（整串）或 -Exclude chrome,msedge（数组）；
    # 只按逗号切分，进程名里的空格要保留（例如 "DeepSeek Harness"）
    foreach ($part in ($item -split ',')) {
        $name = $part.Trim()
        if ($name.Length -gt 0) {
            $excludeList += ($name -replace '\.exe$', '').ToLowerInvariant()
        }
    }
}

$candidates = @($allWindows | Where-Object {
    $w = $_
    $w.Title.Length -gt 0 -and
    ($SkipWindowClasses -notcontains $w.ClassName) -and
    (-not $protectClose.Contains([int]$w.ProcessId)) -and
    ($w.Handle -ne $consoleHandle) -and
    ($excludeList -notcontains $w.ProcessName)
} | Sort-Object ProcessName, Title)

# 个别系统进程拿不到进程名，尽量补一下（补不到也不影响“正常关闭”）
foreach ($w in $candidates) {
    if ([string]::IsNullOrEmpty($w.ProcessName)) {
        try { $w.ProcessName = (Get-Process -Id ([int]$w.ProcessId) -ErrorAction Stop).ProcessName } catch { }
    }
}

# ---------- 2. 仅查看模式 ----------
if ($DryRun) {
    Write-Host ''
    Write-Host ('仅查看（-DryRun）：共 {0} 个窗口，不会关闭任何窗口。' -f $candidates.Count) -ForegroundColor Cyan
    Write-Host ''
    if ($candidates.Count -eq 0) {
        Write-Host '  （没有匹配的窗口）' -ForegroundColor DarkGray
    }
    else {
        $index = 0
        foreach ($w in $candidates) {
            $index++
            '{0,3}. {1}' -f $index, (Format-WindowLine $w)
            if ($w.Hung) { '      ^ 无响应' }
        }
    }
    Write-Host ''
    exit 0
}

# ---------- 3. 没有可关闭的窗口 ----------
if ($candidates.Count -eq 0) {
    if ($Confirm) {
        [void][System.Windows.Forms.MessageBox]::Show('当前没有需要关闭的窗口。', '一键关闭所有窗口',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
    else {
        Write-RunLog -Text ('[{0}] 没有需要关闭的窗口' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    }
    exit 0
}

# ---------- 4. 确认（默认不确认，单击即关）----------
$answer = Show-CloseConfirm -Windows $candidates -Skip:(-not $Confirm -or $NoDialog) -ForceAll:$Force
if (-not $answer.Ok) { exit 0 }

# ---------- 5. 逐个正常关闭 ----------
foreach ($w in $candidates) {
    [void][CloseAllWindows.Native]::PostMessage($w.Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) # WM_CLOSE
}

$deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
$leftovers = @($candidates | Where-Object { Test-WindowAlive $_.Handle })
while ($leftovers.Count -gt 0 -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 150
    $leftovers = @($candidates | Where-Object { Test-WindowAlive $_.Handle })
}

# ---------- 6. 可选：强制结束仍然存在的进程 ----------
$killFailed = @()
if ($leftovers.Count -gt 0 -and ($answer.Force -or $Force)) {
    $killIds = @()
    $seen = @{}
    foreach ($w in $leftovers) {
        $id = [int]$w.ProcessId
        if ($id -le 4) { continue }
        if ($seen.ContainsKey($id)) { continue }
        if ($protectKill.Contains($id)) { continue }
        # 进程名未知时宁可不动，避免误杀系统进程
        if ([string]::IsNullOrEmpty($w.ProcessName)) { continue }
        if ($NeverKill -contains $w.ProcessName.ToLowerInvariant()) { continue }
        $seen[$id] = $true
        $killIds += $id
    }
    foreach ($id in $killIds) {
        try {
            Stop-Process -Id $id -Force -ErrorAction Stop
        }
        catch {
            $procName = ''
            try { $procName = (Get-Process -Id $id -ErrorAction Stop).ProcessName } catch { }
            $killFailed += ('PID {0}（{1}）：{2}' -f $id, $procName, $_.Exception.Message)
        }
    }
    if ($killIds.Count -gt 0) { Start-Sleep -Milliseconds 800 }
    $leftovers = @($candidates | Where-Object { Test-WindowAlive $_.Handle })
}

# ---------- 7. 结果 ----------
$closed = $candidates.Count - $leftovers.Count
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$logLines = @(
    "[$stamp] 关闭请求 $($candidates.Count) 个，已关闭 $closed 个，残留 $($leftovers.Count) 个"
)
foreach ($w in $candidates) { $logLines += ('  - {0}' -f (Format-WindowLine $w)) }
foreach ($w in $leftovers) { $logLines += ('  ! 未关闭 {0}' -f (Format-WindowLine $w)) }
foreach ($f in $killFailed) { $logLines += ('  x 强制结束失败 {0}' -f $f) }
Write-RunLog -Text ($logLines -join "`r`n")

if ($leftovers.Count -gt 0 -and $Confirm) {
    $lines = @()
    $lines += ('已请求关闭 {0} 个窗口，其中 {1} 个已关闭。' -f $candidates.Count, $closed)
    $lines += ''
    $lines += ('仍有 {0} 个窗口没有关闭：' -f $leftovers.Count)
    $n = 0
    foreach ($w in $leftovers) {
        $n++
        if ($n -le 10) { $lines += ('  {0}. {1}' -f $n, (Format-WindowLine $w)) }
    }
    if ($leftovers.Count -gt 10) { $lines += ('  ……另有 {0} 个' -f ($leftovers.Count - 10)) }
    $lines += ''
    $lines += '常见原因：程序正在询问「是否保存」；程序无响应；窗口来自管理员权限的进程（本工具未提权）。'
    if ($killFailed.Count -gt 0) { $lines += ''; $lines += '强制结束失败：' + ($killFailed -join '；') }
    [void][System.Windows.Forms.MessageBox]::Show(($lines -join "`r`n"), '一键关闭所有窗口 — 部分完成',
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
}
