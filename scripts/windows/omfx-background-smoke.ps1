param(
  [Parameter(Mandatory = $true)]
  [string]$Executable
)

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = (Resolve-Path -LiteralPath $Executable).Path
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.ArgumentList.Add("--fx-internal-background-wrapper")

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
[void]$process.Start()

$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$ready = $process.StandardError.BaseStream.ReadByte()
if ($ready -ne [int][char]'R') {
  try { $process.Kill($true) } catch { $process.Kill() }
  throw "background wrapper did not send ready byte (actual=$ready)"
}

$process.StandardInput.BaseStream.Write([byte[]](0x06, 0x0a), 0, 2)
$command = [System.Text.Encoding]::UTF8.GetBytes("echo FX_WINDOWS_BACKGROUND_SMOKE")
$process.StandardInput.BaseStream.Write($command, 0, $command.Length)
$process.StandardInput.Close()

if (-not $process.WaitForExit(30 * 1000)) {
  try { $process.Kill($true) } catch { $process.Kill() }
  throw "background wrapper timed out"
}

$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $process.StandardError.ReadToEnd()
if ($process.ExitCode -ne 0) {
  throw "background wrapper exited with code $($process.ExitCode) (stdout=$stdout stderr=$stderr)"
}
if ($stdout -notmatch "FX_WINDOWS_BACKGROUND_SMOKE") {
  throw "background wrapper output missing command marker: $stdout"
}
if ($stdout -notmatch "__FX_EXIT_CODE__=0") {
  throw "background wrapper output missing exit marker: $stdout"
}
if ($stderr.Length -ne 0) {
  throw "background wrapper wrote unexpected stderr after ready: $stderr"
}

Write-Output "Windows background wrapper smoke passed"
