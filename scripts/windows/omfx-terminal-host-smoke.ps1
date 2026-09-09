param(
  [Parameter(Mandatory = $true)]
  [string]$Executable
)

$repoRoot = (Get-Location).Path
$fixture = Join-Path $env:RUNNER_TEMP "omfx-terminal-client-fixture.exe"
$smokeHome = Join-Path $env:RUNNER_TEMP "omfx-terminal-host-smoke-home"
$trace = Join-Path $env:RUNNER_TEMP "omfx-terminal-host-smoke.trace"

Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $smokeHome -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $trace -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $smokeHome | Out-Null

& zig build-exe -ODebug -lc "-femit-bin=$fixture" ".\src\terminal_client_fixture.zig"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $fixture)) {
  throw "terminal client fixture build failed"
}

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = (Resolve-Path -LiteralPath $fixture).Path
$startInfo.WorkingDirectory = $repoRoot
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.Environment["HOME"] = $smokeHome
$startInfo.Environment["USERPROFILE"] = $smokeHome
$startInfo.Environment["FX_TERMINAL_CAPABILITY_FIXTURE"] = "start"
$startInfo.Environment["FX_TERMINAL_HOST_IDLE_MS"] = "30_000"
$startInfo.Environment["FX_DISABLE_KEYCHAIN"] = "1"
$startInfo.Environment["FX_AUTO_UPGRADE"] = "0"
$startInfo.Environment["FX_TRACE_LOG"] = $trace
$startInfo.Environment["FX_TRACE_SCOPES"] = "terminal_client,terminal_host,native_session"
$startInfo.Environment["FX_TERMINAL_HOST_EXECUTABLE"] = (Resolve-Path -LiteralPath $Executable).Path

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
[void]$process.Start()
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()

if (-not $process.WaitForExit(45 * 1000)) {
  try { $process.Kill($true) } catch { $process.Kill() }
  $process.WaitForExit()
  throw "terminal host smoke timed out"
}

$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
$traceTail = if (Test-Path -LiteralPath $trace) {
  (Get-Content -LiteralPath $trace -Tail 80 -ErrorAction SilentlyContinue) -join " | "
} else {
  ""
}
if ($process.ExitCode -ne 0) {
  throw "terminal host smoke exited with code $($process.ExitCode) (stdout=$stdout stderr=$stderr trace=$traceTail)"
}
if ($stdout -notmatch '"kind":"completed"') {
  Write-Output "terminal host smoke stderr: $stderr"
  if (Test-Path -LiteralPath $trace) {
    Write-Output "terminal host smoke trace:"
    Get-Content -LiteralPath $trace
  }
  throw "terminal host smoke did not complete a start request: $stdout (trace=$traceTail)"
}
if ($stdout -match "unsupported_host|TerminalHostUnsupported|panic") {
  throw "terminal host smoke reported unsupported or panic output: $stdout (trace=$traceTail)"
}
if (-not [string]::IsNullOrWhiteSpace($stderr)) {
  throw "terminal host smoke wrote stderr: $stderr (trace=$traceTail)"
}

Write-Output "Windows terminal host and native session smoke passed"
