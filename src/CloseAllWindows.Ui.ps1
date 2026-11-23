#Requires -Version 5.1
# ============================================================================
#  一键关闭所有窗口 — 界面与格式化辅助（由 CloseAllWindows.ps1 点源加载）
# ============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ('CloseAllWindows.Dpi' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CloseAllWindows
{
    public static class Dpi
    {
        [DllImport("user32.dll")]
        private static extern bool SetProcessDpiAwarenessContext(IntPtr context);

        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        public static void Enable()
        {
            try { if (SetProcessDpiAwarenessContext(new IntPtr(-2))) return; } catch { }
            try { SetProcessDPIAware(); } catch { }
        }

        // 以隐藏方式启动的进程，窗口第一次 ShowWindow 会被 STARTUPINFO 覆盖成 SW_HIDE。
        // 再显式调用一次 SW_SHOW，确保对话框一定可见。
        public static void ForceShow(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return;
            try { ShowWindow(hWnd, 5); } catch { }
        }
    }
}
'@ -Language CSharp
}

function Enable-DpiAwareness {
    try { [CloseAllWindows.Dpi]::Enable() } catch { }
}

# 当前缩放比例（96 DPI = 1.0，150% = 1.5）
function Get-UiScale {
    $dpi = 96.0
    try {
        $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
        if ($null -ne $g) { $dpi = [double]$g.DpiX; $g.Dispose() }
    }
    catch { $dpi = 96.0 }
    if ($dpi -lt 96.0) { $dpi = 96.0 }
    return ($dpi / 96.0)
}

function New-ScaledPoint {
    param([double]$X, [double]$Y, [double]$Scale)
    return (New-Object System.Drawing.Point(
        [int][Math]::Round($X * $Scale), [int][Math]::Round($Y * $Scale)))
}

function New-ScaledSize {
    param([double]$Width, [double]$Height, [double]$Scale)
    return (New-Object System.Drawing.Size(
        [int][Math]::Round($Width * $Scale), [int][Math]::Round($Height * $Scale)))
}

function Format-WindowTitle {
    param([string]$Text, [int]$Max = 58)
    $t = ($Text -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Max) { return $t.Substring(0, $Max - 1) + [char]0x2026 }
    return $t
}

function Format-WindowLine {
    param($Window)
    $name = $Window.ProcessName
    if ([string]::IsNullOrEmpty($name)) { $name = '未知进程' }
    return ('{0}    [{1}  PID {2}]' -f (Format-WindowTitle $Window.Title), $name, $Window.ProcessId)
}

# 按可用像素宽度裁剪标题，避免列表出现横向滚动条
function Get-FittedWindowLine {
    param($Window, [int]$MaxWidth, [System.Drawing.Font]$Font)

    $name = $Window.ProcessName
    if ([string]::IsNullOrEmpty($name)) { $name = '未知进程' }
    $suffix = ('    [{0}  PID {1}]' -f $name, $Window.ProcessId)
    $title = ($Window.Title -replace '\s+', ' ').Trim()

    $measure = [System.Windows.Forms.TextRenderer]
    if ($measure::MeasureText(($title + $suffix), $Font).Width -le $MaxWidth) {
        return ($title + $suffix)
    }

    while ($title.Length -gt 0) {
        $title = $title.Substring(0, $title.Length - 1)
        $candidate = $title + [char]0x2026 + $suffix
        if ($measure::MeasureText($candidate, $Font).Width -le $MaxWidth) { return $candidate }
    }
    return $suffix.Trim()
}

# 构建确认对话框，返回 @{ Form = 窗体; Force = 复选框 }
function New-CloseDialogForm {
    param([object[]]$Windows, [bool]$ForceChecked)

    $scale = Get-UiScale

    $form = New-Object System.Windows.Forms.Form
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.Text = '一键关闭所有窗口'
    $form.ClientSize = (New-ScaledSize 540 442 $scale)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = ('将关闭下面 {0} 个窗口（每个程序都会先收到正常的关闭请求）：' -f $Windows.Count)
    $label.AutoSize = $true
    $label.Location = (New-ScaledPoint 14 12 $scale)
    $form.Controls.Add($label)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = (New-ScaledPoint 14 38 $scale)
    $list.Size = (New-ScaledSize 512 300 $scale)
    $list.IntegralHeight = $false
    $list.SelectionMode = [System.Windows.Forms.SelectionMode]::None
    $list.HorizontalScrollbar = $false
    $textWidth = $list.ClientSize.Width - [int][Math]::Round(24 * $scale)
    foreach ($w in $Windows) {
        [void]$list.Items.Add((Get-FittedWindowLine $w $textWidth $list.Font))
    }
    $form.Controls.Add($list)

    $tip = New-Object System.Windows.Forms.Label
    $tip.Text = '有未保存内容的程序会先弹出「是否保存」，请到对应程序里确认。'
    $tip.AutoSize = $true
    $tip.ForeColor = [System.Drawing.Color]::DimGray
    $tip.Location = (New-ScaledPoint 14 346 $scale)
    $form.Controls.Add($tip)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = '对无响应的程序强制结束（可能丢失未保存内容）'
    $chk.AutoSize = $true
    $chk.Checked = $ForceChecked
    $chk.Location = (New-ScaledPoint 14 370 $scale)
    $form.Controls.Add($chk)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = '关闭全部'
    $ok.Size = (New-ScaledSize 88 30 $scale)
    $ok.Location = (New-ScaledPoint 350 400 $scale)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Add_Click({ $this.FindForm().Close() })
    $form.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = '取消'
    $cancel.Size = (New-ScaledSize 88 30 $scale)
    $cancel.Location = (New-ScaledPoint 446 400 $scale)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Add_Click({ $this.FindForm().Close() })
    $form.Controls.Add($cancel)

    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    return [pscustomobject]@{ Form = $form; Force = $chk }
}

function Show-CloseConfirm {
    param([object[]]$Windows, [switch]$Skip, [switch]$ForceAll)

    if ($Skip) {
        return [pscustomobject]@{ Ok = $true; Force = [bool]$ForceAll }
    }

    Enable-DpiAwareness
    [void][System.Windows.Forms.Application]::EnableVisualStyles()

    $dialog = New-CloseDialogForm -Windows $Windows -ForceChecked ([bool]$ForceAll)
    $form = $dialog.Form

    # 不用 ShowDialog：隐藏启动时它的首个 ShowWindow 可能被系统强制成 SW_HIDE，
    # 导致对话框不可见且脚本卡住。这里自己跑消息循环，并显式把窗口显示出来。
    $form.Show()
    [CloseAllWindows.Dpi]::ForceShow($form.Handle)
    $form.Activate()

    while ($form.Visible) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 25
    }

    $result = $form.DialogResult
    $checked = $dialog.Force.Checked
    $form.Dispose()

    return [pscustomobject]@{
        Ok    = ($result -eq [System.Windows.Forms.DialogResult]::OK)
        Force = $checked
    }
}
