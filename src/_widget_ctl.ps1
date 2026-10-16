$wd = Split-Path -Parent $PSScriptRoot
$sig = @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
[DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
'@
Add-Type -MemberDefinition $sig -Name W -Namespace QF

function Find-Widget {
    $script:Found = [IntPtr]::Zero
    $cb = [QF.W+EnumWindowsProc]{
        param([IntPtr]$h, [IntPtr]$l)
        if ([QF.W]::IsWindowVisible($h)) {
            $sb = New-Object System.Text.StringBuilder 256
            [void][QF.W]::GetWindowText($h, $sb, 256)
            if ($sb.ToString() -eq 'Network Sentinel') {
                $sb2 = New-Object System.Text.StringBuilder 256
                [void][QF.W]::GetClassName($h, $sb2, 256)
                if ($sb2.ToString() -like 'HwndWrapper*') { $script:Found = $h; return $false }
            }
        }
        return $true
    }
    [void][QF.W]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:Found
}

$h = Find-Widget
if ($h -eq [IntPtr]::Zero) { 'no hay ventana del widget abierta'; exit 0 }
"ventana encontrada: $h"
[void][QF.W]::SendMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 3

if ((Find-Widget) -eq [IntPtr]::Zero) { 'OK: ventana cerrada' } else { 'FALLO: sigue abierta' }

$hist = Join-Path $wd 'network_sentinel_history.json'
if (Test-Path $hist) {
    $json = Get-Content $hist -Raw
    if ($json -match '"value"|"Count"') { 'FALLO: historial json sucio' }
    else { 'OK: historial json plano'; $json }
}
