// ============================================================
//  NETWORK SENTINEL - Lanzador silencioso (stub C#)
//  Compilado por  src\_build_exe.ps1  ->  NetworkSentinel.exe
//  Lanza el widget (via NetworkSentinel.vbs) sin ventanas.
// ============================================================
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        try
        {
            string dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            string vbs = Path.Combine(dir, "NetworkSentinel.vbs");
            string ps1 = Path.Combine(dir, "NetworkSentinel.ps1");
            if (File.Exists(vbs))
            {
                Process.Start(new ProcessStartInfo("wscript.exe", "\"" + vbs + "\"")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true
                });
            }
            else if (File.Exists(ps1))
            {
                Process.Start(new ProcessStartInfo("powershell.exe",
                    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + ps1 + "\"")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true
                });
            }
        }
        catch { }
    }
}
