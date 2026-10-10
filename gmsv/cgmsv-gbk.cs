// Console-only GBK adapter for the unmodified cgmsv.exe.
// Build with .NET Framework csc /target:exe /platform:x64.
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

internal static class GbkEngineLauncher
{
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetConsoleCP(uint codePage);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetConsoleOutputCP(uint codePage);
    [DllImport("kernel32.dll")]
    private static extern uint GetConsoleCP();
    [DllImport("kernel32.dll")]
    private static extern uint GetConsoleOutputCP();
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(IntPtr job, int infoClass,
        ref JobLimits limits, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcess(string application, StringBuilder commandLine,
        IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles,
        uint flags, IntPtr environment, string directory,
        ref StartupInfo startup, out ProcessInfo process);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll")]
    private static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetStdHandle(int kind);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
    {
        public uint Size;
        public string Reserved, Desktop, Title;
        public uint X, Y, Width, Height, XChars, YChars, Fill, Flags;
        public ushort Show, ReservedSize;
        public IntPtr ReservedBytes, Input, Output, Error;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInfo
    {
        public IntPtr Process, Thread;
        public uint ProcessId, ThreadId;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct BasicJobLimits
    {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinimumWorkingSet, MaximumWorkingSet;
        public uint ActiveProcesses;
        public UIntPtr Affinity;
        public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        public ulong ReadOperations, WriteOperations, OtherOperations;
        public ulong ReadBytes, WriteBytes, OtherBytes;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct JobLimits
    {
        public BasicJobLimits Basic;
        public IoCounters Io;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }

    private static string Quote(string value)
    {
        StringBuilder result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { ++slashes; continue; }
            result.Append('\\', c == '"' ? slashes * 2 + 1 : slashes);
            slashes = 0;
            result.Append(c);
        }
        result.Append('\\', slashes * 2);
        return result.Append('"').ToString();
    }

    private static int Main(string[] args)
    {
        IntPtr job = IntPtr.Zero;
        ProcessInfo child = new ProcessInfo();
        try
        {
            // Must be done before creating the engine: it shares this console.
            if (!SetConsoleCP(936) || !SetConsoleOutputCP(936))
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Cannot set the engine console to GBK (936).");
            if (args.Length == 1 && args[0] == "--check-codepage")
            {
                Console.WriteLine("Input={0}; Output={1}", GetConsoleCP(), GetConsoleOutputCP());
                return GetConsoleCP() == 936 && GetConsoleOutputCP() == 936 ? 0 : 1;
            }

            string directory = AppDomain.CurrentDomain.BaseDirectory;
            string engine = Path.Combine(directory, "cgmsv.exe");
            if (!File.Exists(engine)) throw new FileNotFoundException("Missing engine", engine);
            StringBuilder commandLine = new StringBuilder(Quote(engine));
            foreach (string arg in args) commandLine.Append(' ').Append(Quote(arg));

            // Closing the one-click launcher must still close its engine.
            job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            JobLimits limits = new JobLimits();
            limits.Basic.Flags = 0x00002000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            if (!SetInformationJobObject(job, 9, ref limits,
                (uint)Marshal.SizeOf(typeof(JobLimits))))
                throw new Win32Exception(Marshal.GetLastWin32Error());

            StartupInfo startup = new StartupInfo();
            startup.Size = (uint)Marshal.SizeOf(typeof(StartupInfo));
            startup.Flags = 0x00000100; // STARTF_USESTDHANDLES
            startup.Input = GetStdHandle(-10);
            startup.Output = GetStdHandle(-11);
            startup.Error = GetStdHandle(-12);
            if (!CreateProcess(engine, commandLine, IntPtr.Zero, IntPtr.Zero,
                true, 0x00000004, IntPtr.Zero, directory, ref startup, out child))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            if (!AssignProcessToJobObject(job, child.Process))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            if (ResumeThread(child.Thread) == uint.MaxValue)
                throw new Win32Exception(Marshal.GetLastWin32Error());
            CloseHandle(child.Thread);
            child.Thread = IntPtr.Zero;
            if (WaitForSingleObject(child.Process, uint.MaxValue) != 0)
                throw new Win32Exception(Marshal.GetLastWin32Error());
            uint exitCode;
            if (!GetExitCodeProcess(child.Process, out exitCode))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return unchecked((int)exitCode);
        }
        catch (Exception error)
        {
            if (child.Process != IntPtr.Zero) TerminateProcess(child.Process, 1);
            Console.Error.WriteLine("GBK console adapter: " + error.Message);
            return 1;
        }
        finally
        {
            if (child.Thread != IntPtr.Zero) CloseHandle(child.Thread);
            if (child.Process != IntPtr.Zero) CloseHandle(child.Process);
            if (job != IntPtr.Zero) CloseHandle(job);
        }
    }
}
