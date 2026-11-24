# Captures one ModelSim waveform figure (Windows).
# From sim/:  powershell -ExecutionPolicy Bypass -File ..\docs\figures\capture\capture.ps1 fig05 fig05.png
# 1. runs the ModelSim GUI on capture\<fig>.do (which runs the unchanged sim\run_*.do, undocks the
#    Wave window, sets short names and the zoom, then writes the file "cap_ready" in sim\)
# 2. captures the undocked Wave window (PrintWindow, so other windows on top do not matter)
# 3. crops it to the wave pane with crop.py and closes ModelSim
# Testbenches that end in $finish would open a "finish?" dialog in the GUI, so a copy of the
# installed modelsim.ini with OnFinish = stop is used for the run (the install is not changed).
param([string]$Fig, [string]$Out, [int]$TimeoutSec = 240)
$here = $PSScriptRoot
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public class W {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static List<IntPtr> Find(string prefix) {
    var res = new List<IntPtr>();
    EnumWindows((h, l) => { var sb = new StringBuilder(256); GetWindowText(h, sb, 256);
      if (IsWindowVisible(h) && sb.ToString().StartsWith(prefix)) res.Add(h); return true; }, IntPtr.Zero);
    return res;
  }
}
"@
Add-Type -AssemblyName System.Drawing

# modelsim.ini copy with OnFinish = stop
$vsimDir = Split-Path (Get-Command vsim).Source
$ini = Join-Path $env:TEMP "modelsim_capture.ini"
$lines = foreach ($l in Get-Content (Join-Path $vsimDir "..\modelsim.ini")) { $l; if ($l -match '^\[vsim\]') { 'OnFinish = stop' } }
$lines | Set-Content -Encoding ascii $ini
$env:MODELSIM = $ini

Remove-Item cap_ready -ErrorAction SilentlyContinue
$do = (Join-Path $here "$Fig.do").Replace('\', '/')
$p = Start-Process vsim -ArgumentList "-do", "`"$do`"" -PassThru
$t = 0
while (-not (Test-Path cap_ready) -and $t -lt $TimeoutSec) { Start-Sleep 1; $t++ }
if (-not (Test-Path cap_ready)) { Write-Host "TIMEOUT"; Get-Process vsim, vish -ErrorAction SilentlyContinue | Stop-Process -Force; exit 1 }
Start-Sleep 3
$h = [W]::Find("Wave") | Select-Object -First 1
$r = New-Object W+RECT; [W]::GetWindowRect($h, [ref]$r) | Out-Null
$bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
$g = [System.Drawing.Graphics]::FromImage($bmp); $dc = $g.GetHdc()
[W]::PrintWindow($h, $dc, 2) | Out-Null
$g.ReleaseHdc($dc); $g.Dispose()
$raw = Join-Path $env:TEMP "$Fig.raw.png"
$bmp.Save($raw, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Get-Process vsim, vish -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item cap_ready -ErrorAction SilentlyContinue
python (Join-Path $here "crop.py") $raw $Out
