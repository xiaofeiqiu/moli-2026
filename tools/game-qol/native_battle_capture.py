"""Read battle output from this test's disposable cgmsv process, without writes."""
from pathlib import Path
import ctypes
from ctypes import wintypes as W
import hashlib
import json
import subprocess


def captured_process_type(result, ack, run):
    # Buffer addresses were traced in this exact build; never apply them to another.
    expected = 'bc69e795441d0819e547b569e4df3eae97278176e047cc829a36d19a6072cd76'
    assert hashlib.sha256((run / 'cgmsv.exe').read_bytes()).hexdigest() == expected
    ack.unlink(missing_ok=True)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)

    class Module(ctypes.Structure):
        _fields_ = [('dwSize', W.DWORD), ('th32ModuleID', W.DWORD),
                    ('th32ProcessID', W.DWORD), ('GlblcntUsage', W.DWORD),
                    ('ProccntUsage', W.DWORD), ('modBaseAddr', ctypes.c_void_p),
                    ('modBaseSize', W.DWORD), ('hModule', W.HMODULE),
                    ('szModule', W.WCHAR * 256), ('szExePath', W.WCHAR * 260)]

    kernel.CreateToolhelp32Snapshot.argtypes = [W.DWORD, W.DWORD]
    kernel.CreateToolhelp32Snapshot.restype = W.HANDLE
    kernel.Module32FirstW.argtypes = [W.HANDLE, ctypes.POINTER(Module)]
    kernel.Module32FirstW.restype = W.BOOL
    kernel.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
    kernel.OpenProcess.restype = W.HANDLE
    kernel.ReadProcessMemory.argtypes = [W.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                        ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
    kernel.ReadProcessMemory.restype = W.BOOL
    kernel.CloseHandle.argtypes = [W.HANDLE]

    class CapturedProcess(subprocess.Popen):
        def __init__(self, *args, **kwargs):
            assert Path(kwargs['cwd']).resolve() == run.resolve()
            super().__init__(*args, **kwargs)
            self.memory = None
            self.base = None
            self.last_capture = None

        def read(self, addr, size):
            data = ctypes.create_string_buffer(size)
            got = ctypes.c_size_t()
            if not kernel.ReadProcessMemory(self.memory, addr, data, size, ctypes.byref(got)):
                raise ctypes.WinError(ctypes.get_last_error())
            return data.raw[:got.value]

        def poll(self):
            status = super().poll()
            if status is not None:
                return status
            try:
                report = json.loads(result.read_bytes().decode('gbk'))
            except (FileNotFoundError, UnicodeError, ValueError):
                return status
            capture = report.get('capture_requested')
            if not capture or self.last_capture == capture:
                return status
            if self.memory is None:
                # PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, for our own child PID.
                self.memory = kernel.OpenProcess(0x410, False, self.pid)
                if not self.memory:
                    raise ctypes.WinError(ctypes.get_last_error())
                snapshot = kernel.CreateToolhelp32Snapshot(0x18, self.pid)
                module = Module()
                module.dwSize = ctypes.sizeof(module)
                try:
                    assert kernel.Module32FirstW(snapshot, ctypes.byref(module))
                    assert Path(module.szExePath).resolve() == (run / 'cgmsv.exe').resolve()
                    self.base = module.modBaseAddr
                finally:
                    kernel.CloseHandle(snapshot)
            buffers = {}
            for name, rva in [('main', 0x19c7ca0), ('extra', 0x19cbca0)]:
                raw = self.read(self.base + rva, 0x4000).split(b'\0')[0]
                buffers[name] = raw.decode('gbk', errors='replace')
            ack.write_text(json.dumps({'capture': capture, 'buffers': buffers}), 'ascii')
            self.last_capture = capture
            return status

        def wait(self, *args, **kwargs):
            try:
                return super().wait(*args, **kwargs)
            finally:
                if self.memory:
                    kernel.CloseHandle(self.memory)
                    self.memory = None

    return CapturedProcess
