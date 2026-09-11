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

$endpoint = Join-Path $smokeHome ".fx\terminal-host\host.sock"
$hostStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
$hostStartInfo.FileName = (Resolve-Path -LiteralPath $Executable).Path
$hostStartInfo.WorkingDirectory = $repoRoot
$hostStartInfo.UseShellExecute = $false
$hostStartInfo.RedirectStandardOutput = $true
$hostStartInfo.RedirectStandardError = $true
$hostStartInfo.Environment["HOME"] = $smokeHome
$hostStartInfo.Environment["USERPROFILE"] = $smokeHome
$hostStartInfo.Environment["FX_TERMINAL_HOST_IDLE_MS"] = "120_000"
$hostStartInfo.Environment["FX_DISABLE_KEYCHAIN"] = "1"
$hostStartInfo.Environment["FX_AUTO_UPGRADE"] = "0"
$hostStartInfo.Environment["FX_TRACE_LOG"] = $trace
$hostStartInfo.Environment["FX_TRACE_SCOPES"] = "terminal_host"
$hostStartInfo.Environment["FX_TRACE_STDERR"] = "1"
$hostStartInfo.Environment["FX_TERMINAL_HOST_DIAGNOSTIC"] = "1"
[void]$hostStartInfo.ArgumentList.Add("--fx-internal-terminal-host")

$hostProcess = [System.Diagnostics.Process]::new()
$hostProcess.StartInfo = $hostStartInfo
$hostStarted = $false
$hostProbeError = $null
$hostStdout = ""
$hostStderr = ""
try {
  [void]$hostProcess.Start()
  $hostStarted = $true
  $hostStdoutTask = $hostProcess.StandardOutput.ReadToEndAsync()
  $hostStderrTask = $hostProcess.StandardError.ReadToEndAsync()

  $hostDeadline = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $hostDeadline -and -not (Test-Path -LiteralPath $endpoint)) {
    if ($hostProcess.HasExited) { break }
    Start-Sleep -Milliseconds 100
  }
  if (-not (Test-Path -LiteralPath $endpoint)) {
    throw "host did not create endpoint for the native socket probe"
  }

  $probeSocket = [System.Net.Sockets.Socket]::new(
    [System.Net.Sockets.AddressFamily]::Unix,
    [System.Net.Sockets.SocketType]::Stream,
    [System.Net.Sockets.ProtocolType]::Unspecified
  )
  try {
    [void]$probeSocket.Connect(
      [System.Net.Sockets.UnixDomainSocketEndPoint]::new($endpoint)
    )
    Write-Output "Windows native .NET AF_UNIX client connected to the omfx host"
  } finally {
    $probeSocket.Dispose()
  }
} catch {
  $hostProbeError = $_.Exception.Message
} finally {
  if ($hostStarted -and -not $hostProcess.HasExited) {
    try { $hostProcess.Kill($true) } catch { $hostProcess.Kill() }
    $hostProcess.WaitForExit()
  }
  if ($hostStarted) {
    $hostStdout = $hostStdoutTask.GetAwaiter().GetResult()
    $hostStderr = $hostStderrTask.GetAwaiter().GetResult()
  }
  $hostProcess.Dispose()
}
if ($null -ne $hostProbeError) {
  $hostTrace = if (Test-Path -LiteralPath $trace) {
    (Get-Content -LiteralPath $trace -Tail 80 -ErrorAction SilentlyContinue) -join " | "
  } else {
    ""
  }
  throw "native .NET AF_UNIX probe failed: $hostProbeError (stdout=$hostStdout stderr=$hostStderr trace=$hostTrace)"
}

# The probe intentionally leaves a queued connection behind. Start the real
# client handshake from a clean profile so it exercises the normal cold-start
# path rather than the probe's stale endpoint and identity record.
Remove-Item -LiteralPath $smokeHome -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $smokeHome | Out-Null

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
$startInfo.Environment["FX_TRACE_STDERR"] = "1"
$startInfo.Environment["FX_TERMINAL_HOST_DIAGNOSTIC"] = "1"
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
if ($stderr -match "panic|unreachable|unsupported_host|TerminalHostUnsupported") {
  throw "terminal host smoke reported a runtime failure on stderr: $stderr (trace=$traceTail)"
}

Write-Output "Windows terminal host and native session smoke passed"
