# Starts Godot for tools/godot_d.sh so that it can never show on the screen. Windows fits a window back onto the screen whatever
# position it asks for, so a test run used to come up at 0,0 over whatever the person was doing. Instead Godot draws inside a host
# window made here and never shown (--wid): it renders, captures work, and nothing appears. This thread pumps the host's messages
# while Godot runs, as a parent window must. Reads GODOT_EXE, GODOT_ARGS, GODOT_PID_FILE, GODOT_W, GODOT_H; exits with Godot's code.
Add-Type -AssemblyName System.Windows.Forms
$host_window = New-Object System.Windows.Forms.Form
$host_window.ShowInTaskbar = $false
$host_window.FormBorderStyle = 'None'
$host_window.StartPosition = 'Manual'
$host_window.Location = New-Object System.Drawing.Point(-32000, -32000)
$host_window.ClientSize = New-Object System.Drawing.Size([int]$env:GODOT_W, [int]$env:GODOT_H)
$hwnd = $host_window.Handle.ToInt64()   # makes the window without showing it
$p = Start-Process -FilePath $env:GODOT_EXE -ArgumentList ("--wid $hwnd " + $env:GODOT_ARGS) -WindowStyle Hidden -PassThru
$null = $p.Handle
Set-Content -Path $env:GODOT_PID_FILE -Value $p.Id
while (-not $p.HasExited) {
  [System.Windows.Forms.Application]::DoEvents()
  Start-Sleep -Milliseconds 10
}
$host_window.Dispose()
exit $p.ExitCode
