using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

internal static class Program
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    private const string TaskName = "OneClickCloseAll";

    [STAThread]
    private static void Main()
    {
        Process p = null;
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo("schtasks.exe");
            psi.Arguments = "/run /tn \"" + TaskName + "\"";
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;

            p = Process.Start(psi);
            bool exited = p == null || p.WaitForExit(8000);

            if (p != null && (!exited || p.ExitCode != 0))
            {
                MessageBoxW(IntPtr.Zero,
                    "没能启动「关闭所有窗口」任务。\n\n计划任务 OneClickCloseAll 可能已被删除，\n请用管理员身份重新运行 install-task.ps1。",
                    "关窗", 0x00000030);
            }
        }
        catch (Exception ex)
        {
            MessageBoxW(IntPtr.Zero, "启动失败：" + ex.Message, "关窗", 0x00000010);
        }
        finally
        {
            if (p != null) p.Dispose();
        }
    }
}
