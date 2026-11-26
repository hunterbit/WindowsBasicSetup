param([string]$Trace)
# Preme "Si" sulla finestra "Conferma" appena compare (al massimo 60 secondi)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class W32b {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
}
"@
Add-Content $Trace "autoyes partito"
for ($i = 0; $i -lt 120; $i++) {
    $h = [W32b]::FindWindow("#32770", "Conferma")
    if ($h -ne [IntPtr]::Zero) {
        $ok = [W32b]::PostMessage($h, 0x111, [IntPtr]6, [IntPtr]::Zero)
        Add-Content $Trace "autoyes: trovata, PostMessage=$ok"
        exit 0
    }
    Start-Sleep -Milliseconds 500
}
Add-Content $Trace "autoyes: non trovata"
