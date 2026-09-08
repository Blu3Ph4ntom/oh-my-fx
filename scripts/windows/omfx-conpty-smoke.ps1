param(
  [Parameter(Mandatory = $true)]
  [string]$Executable,
  [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;

public sealed class OmfxConPtyResult
{
    public int ExitCode { get; set; }
    public string Output { get; set; }
}

public static class OmfxConPty
{
    private const uint CreateUnicodeEnvironment = 0x00000400;
    private const uint ExtendedStartupInfoPresent = 0x00080000;
    private const uint HandleFlagInherit = 0x00000001;
    private const uint PseudoConsoleAttribute = 0x00020016;

    [StructLayout(LayoutKind.Sequential)]
    private struct Coord
    {
        public short X;
        public short Y;

        public Coord(short x, short y)
        {
            X = x;
            Y = y;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SecurityAttributes
    {
        public int Length;
        public IntPtr SecurityDescriptor;
        public int InheritHandle;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
    {
        public int Cb;
        public string Reserved;
        public string Desktop;
        public string Title;
        public int X;
        public int Y;
        public int XSize;
        public int YSize;
        public int XCountChars;
        public int YCountChars;
        public int FillAttribute;
        public int Flags;
        public short ShowWindow;
        public short Reserved2;
        public IntPtr Reserved2Pointer;
        public IntPtr StdInput;
        public IntPtr StdOutput;
        public IntPtr StdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct StartupInfoEx
    {
        public StartupInfo StartupInfo;
        public IntPtr AttributeList;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInformation
    {
        public IntPtr Process;
        public IntPtr Thread;
        public int ProcessId;
        public int ThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CreatePipe(
        out IntPtr readPipe,
        out IntPtr writePipe,
        ref SecurityAttributes attributes,
        int size);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetHandleInformation(
        IntPtr handle,
        uint mask,
        uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll")]
    private static extern int CreatePseudoConsole(
        Coord size,
        IntPtr inputReadSide,
        IntPtr outputWriteSide,
        uint flags,
        out IntPtr pseudoConsole);

    [DllImport("kernel32.dll")]
    private static extern void ClosePseudoConsole(IntPtr pseudoConsole);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool InitializeProcThreadAttributeList(
        IntPtr attributeList,
        int attributeCount,
        uint flags,
        ref IntPtr size);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool UpdateProcThreadAttribute(
        IntPtr attributeList,
        uint flags,
        IntPtr attribute,
        IntPtr value,
        IntPtr size,
        IntPtr previousValue,
        IntPtr returnSize);

    [DllImport("kernel32.dll")]
    private static extern void DeleteProcThreadAttributeList(IntPtr attributeList);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcess(
        string applicationName,
        StringBuilder commandLine,
        IntPtr processAttributes,
        IntPtr threadAttributes,
        bool inheritHandles,
        uint creationFlags,
        IntPtr environment,
        string currentDirectory,
        ref StartupInfoEx startupInfo,
        out ProcessInformation processInformation);

    public static OmfxConPtyResult Run(string executable, string workingDirectory, int timeoutSeconds)
    {
        IntPtr inputRead = IntPtr.Zero;
        IntPtr inputWrite = IntPtr.Zero;
        IntPtr outputRead = IntPtr.Zero;
        IntPtr outputWrite = IntPtr.Zero;
        IntPtr pseudoConsole = IntPtr.Zero;
        IntPtr attributeList = IntPtr.Zero;
        IntPtr pseudoConsoleValue = IntPtr.Zero;
        ProcessInformation processInformation = new ProcessInformation();
        StringBuilder output = new StringBuilder();
        AutoResetEvent outputChanged = new AutoResetEvent(false);
        Task reader = null;

        try
        {
            SecurityAttributes attributes = new SecurityAttributes
            {
                Length = Marshal.SizeOf<SecurityAttributes>(),
                InheritHandle = 1,
            };
            Ensure(CreatePipe(out inputRead, out inputWrite, ref attributes, 0), "CreatePipe input");
            Ensure(CreatePipe(out outputRead, out outputWrite, ref attributes, 0), "CreatePipe output");
            Ensure(SetHandleInformation(inputWrite, HandleFlagInherit, 0), "SetHandleInformation input");
            Ensure(SetHandleInformation(outputRead, HandleFlagInherit, 0), "SetHandleInformation output");

            int pseudoConsoleResult = CreatePseudoConsole(
                new Coord(120, 40),
                inputRead,
                outputWrite,
                0,
                out pseudoConsole);
            if (pseudoConsoleResult != 0)
                throw new InvalidOperationException("CreatePseudoConsole failed with HRESULT 0x" + pseudoConsoleResult.ToString("X8"));

            IntPtr attributeSize = IntPtr.Zero;
            InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref attributeSize);
            attributeList = Marshal.AllocHGlobal(attributeSize);
            Ensure(InitializeProcThreadAttributeList(attributeList, 1, 0, ref attributeSize), "InitializeProcThreadAttributeList");
            pseudoConsoleValue = Marshal.AllocHGlobal(IntPtr.Size);
            Marshal.WriteIntPtr(pseudoConsoleValue, pseudoConsole);
            Ensure(UpdateProcThreadAttribute(
                attributeList,
                0,
                new IntPtr(PseudoConsoleAttribute),
                pseudoConsoleValue,
                new IntPtr(IntPtr.Size),
                IntPtr.Zero,
                IntPtr.Zero), "UpdateProcThreadAttribute");

            StartupInfoEx startupInfo = new StartupInfoEx();
            startupInfo.StartupInfo.Cb = Marshal.SizeOf<StartupInfoEx>();
            startupInfo.AttributeList = attributeList;
            string quotedExecutable = "\"" + executable.Replace("\"", "\\\"") + "\"";
            Ensure(CreateProcess(
                null,
                new StringBuilder(quotedExecutable),
                IntPtr.Zero,
                IntPtr.Zero,
                true,
                ExtendedStartupInfoPresent | CreateUnicodeEnvironment,
                IntPtr.Zero,
                workingDirectory,
                ref startupInfo,
                out processInformation), "CreateProcess");

            CloseHandle(processInformation.Thread);
            processInformation.Thread = IntPtr.Zero;
            CloseHandle(inputRead);
            inputRead = IntPtr.Zero;
            CloseHandle(outputWrite);
            outputWrite = IntPtr.Zero;

            using (FileStream input = new FileStream(new SafeFileHandle(inputWrite, true), FileAccess.Write, 4096, false))
            using (FileStream terminalOutput = new FileStream(new SafeFileHandle(outputRead, true), FileAccess.Read, 4096, false))
            {
                inputWrite = IntPtr.Zero;
                outputRead = IntPtr.Zero;
                reader = Task.Run(() => ReadOutput(terminalOutput, output, outputChanged));
                Send(input, "/help\r");
                WaitForMarker(output, outputChanged, "Commands", timeoutSeconds);
                int helpOutputLength;
                lock (output) helpOutputLength = output.Length;
                Send(input, "\u001b");
                WaitForMarkerAfter(output, outputChanged, "\u001b[?1049l", helpOutputLength, timeoutSeconds);
                Send(input, "/quit\r");
                if (!WaitForProcess(processInformation.Process, timeoutSeconds))
                {
                    TerminateProcess(processInformation.Process, 124);
                    WaitForProcess(processInformation.Process, 5);
                    throw new TimeoutException("omfx ConPTY interaction timed out after " + timeoutSeconds + " seconds");
                }
                reader.Wait(5000);
            }

            return new OmfxConPtyResult
            {
                ExitCode = GetExitCode(processInformation.Process),
                Output = output.ToString(),
            };
        }
        finally
        {
            if (reader != null) reader.Wait(5000);
            if (processInformation.Process != IntPtr.Zero)
            {
                if (WaitForSingleObject(processInformation.Process, 0) == 0x00000102)
                {
                    TerminateProcess(processInformation.Process, 125);
                    WaitForSingleObject(processInformation.Process, 5000);
                }
                CloseHandle(processInformation.Process);
            }
            if (processInformation.Thread != IntPtr.Zero) CloseHandle(processInformation.Thread);
            if (inputRead != IntPtr.Zero) CloseHandle(inputRead);
            if (inputWrite != IntPtr.Zero) CloseHandle(inputWrite);
            if (outputRead != IntPtr.Zero) CloseHandle(outputRead);
            if (outputWrite != IntPtr.Zero) CloseHandle(outputWrite);
            if (pseudoConsoleValue != IntPtr.Zero) Marshal.FreeHGlobal(pseudoConsoleValue);
            if (attributeList != IntPtr.Zero)
            {
                DeleteProcThreadAttributeList(attributeList);
                Marshal.FreeHGlobal(attributeList);
            }
            if (pseudoConsole != IntPtr.Zero) ClosePseudoConsole(pseudoConsole);
            outputChanged.Dispose();
        }
    }

    private static void ReadOutput(FileStream stream, StringBuilder output, AutoResetEvent changed)
    {
        byte[] buffer = new byte[8192];
        int count;
        while ((count = stream.Read(buffer, 0, buffer.Length)) > 0)
        {
            lock (output) output.Append(Encoding.UTF8.GetString(buffer, 0, count));
            changed.Set();
        }
        changed.Set();
    }

    private static void Send(FileStream input, string value)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(value);
        input.Write(bytes, 0, bytes.Length);
        input.Flush();
    }

    private static void WaitForMarker(StringBuilder output, AutoResetEvent changed, string marker, int timeoutSeconds)
    {
        WaitForMarkerAfter(output, changed, marker, 0, timeoutSeconds);
    }

    private static void WaitForMarkerAfter(
        StringBuilder output,
        AutoResetEvent changed,
        string marker,
        int start,
        int timeoutSeconds)
    {
        Stopwatch stopwatch = Stopwatch.StartNew();
        while (stopwatch.Elapsed < TimeSpan.FromSeconds(timeoutSeconds))
        {
            lock (output)
            {
                if (output.Length > start && output.ToString(start, output.Length - start).Contains(marker, StringComparison.Ordinal)) return;
            }
            changed.WaitOne(100);
        }
        throw new TimeoutException("omfx ConPTY output did not contain " + marker);
    }

    private static bool WaitForProcess(IntPtr process, int timeoutSeconds)
    {
        uint result = WaitForSingleObject(process, (uint)(timeoutSeconds * 1000));
        return result == 0;
    }

    private static int GetExitCode(IntPtr process)
    {
        Ensure(GetExitCodeProcess(process, out uint code), "GetExitCodeProcess");
        return unchecked((int)code);
    }

    private static void Ensure(bool result, string operation)
    {
        if (!result) throw new Win32Exception(Marshal.GetLastWin32Error(), operation);
    }

    [DllImport("kernel32.dll")]
    private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateProcess(IntPtr process, uint exitCode);
}
"@

$exe = (Resolve-Path -LiteralPath $Executable).Path
$result = [OmfxConPty]::Run($exe, (Get-Location).Path, $TimeoutSeconds)
if ($result.ExitCode -ne 0) {
  throw "omfx ConPTY smoke exited with code $($result.ExitCode)"
}
if ($result.Output -notmatch "omfx" -or $result.Output -notmatch "Commands") {
  throw "omfx ConPTY smoke did not render the expected product/help surface"
}
if ($result.Output -match "panic|reached unreachable|abort") {
  throw "omfx ConPTY smoke output contains a process failure marker"
}
Write-Output "omfx ConPTY smoke passed: /help, Escape, /quit"
