# ============================================================
#  NETWORK SENTINEL - Genera NetworkSentinel.exe (lanzador con icono)
#  Uso: powershell -NoProfile -ExecutionPolicy Bypass -File .\src\_build_exe.ps1
#  Requiere: NetworkSentinel.ico en la carpeta raiz + csc.exe (viene con
#  .NET Framework 4.x, presente en cualquier Windows 10/11).
# ============================================================
$wd  = Split-Path -Parent $PSScriptRoot
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { Write-Host 'FALLO: no encuentro csc.exe (.NET Framework 4.x)'; exit 1 }

$src = Join-Path $PSScriptRoot '_exe_stub.cs'
$ico = Join-Path $wd 'NetworkSentinel.ico'
$out = Join-Path $wd 'NetworkSentinel.exe'
if (-not (Test-Path $src)) { Write-Host 'FALLO: falta src\_exe_stub.cs'; exit 1 }
if (-not (Test-Path $ico)) { Write-Host 'FALLO: falta NetworkSentinel.ico en la carpeta raiz'; exit 1 }

& $csc /nologo /target:winexe /optimize+ "/win32icon:$ico" "/out:$out" "$src"
if ($LASTEXITCODE -eq 0 -and (Test-Path $out)) {
    Write-Host ("OK: NetworkSentinel.exe generado ({0} bytes) con icono embebido" -f (Get-Item $out).Length)
} else {
    Write-Host "FALLO: compilacion del exe (codigo $LASTEXITCODE)"
    exit 1
}
