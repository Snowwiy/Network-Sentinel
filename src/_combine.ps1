$wd = $PSScriptRoot
$parts = @('_p1.ps1', '_p2.ps1', '_p3a.ps1', '_p3b.ps1')
$text = ($parts | ForEach-Object { [IO.File]::ReadAllText((Join-Path $wd $_), [Text.Encoding]::UTF8) }) -join "`r`n"
$out = Join-Path (Split-Path -Parent $wd) 'NetworkSentinel.ps1'
[IO.File]::WriteAllText($out, $text, (New-Object Text.UTF8Encoding($true)))

$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($out, [ref]$tokens, [ref]$errors)
if ($errors.Count -eq 0) { "OK: combinado ($($text.Length) chars) y sintaxis valida" }
else {
    "FALLO: $($errors.Count) errores de sintaxis"
    $errors | Select-Object -First 10 | ForEach-Object { "  linea $($_.Extent.StartLineNumber): $($_.Message)" }
    exit 1
}
