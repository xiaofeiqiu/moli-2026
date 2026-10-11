"""Install native bank inventory only in the disposable server launched by the probe.

The Lua API has no bank deposit setter. These offsets are verified against the
exact shipped executable; gameplay modules never use process memory access.
"""
import ctypes
import hashlib
import re
import struct
from ctypes import wintypes
from pathlib import Path

SERVER_SHA256 = 'bc69e795441d0819e547b569e4df3eae97278176e047cc829a36d19a6072cd76'


def install(process, executable, fixture):
    executable = Path(executable).resolve()
    root = Path(__file__).resolve().parents[2]
    assert executable.is_relative_to(root / 'backups'), executable
    assert hashlib.sha256(executable.read_bytes()).hexdigest() == SERVER_SHA256
    assert process.poll() is None
    api = ctypes.WinDLL('kernel32', use_last_error=True)
    api.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    api.OpenProcess.restype = wintypes.HANDLE
    api.ReadProcessMemory.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                     ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
    api.WriteProcessMemory.argtypes = api.ReadProcessMemory.argtypes
    api.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = api.OpenProcess(0x8 | 0x10 | 0x20, False, process.pid)
    assert handle, ctypes.get_last_error()

    def read(address, count=8):
        buffer = ctypes.create_string_buffer(count)
        transferred = ctypes.c_size_t()
        assert api.ReadProcessMemory(handle, address, buffer, count, ctypes.byref(transferred))
        assert transferred.value == count
        return buffer.raw

    def write(address, data):
        buffer = ctypes.create_string_buffer(data)
        transferred = ctypes.c_size_t()
        assert api.WriteProcessMemory(handle, address, buffer, len(data), ctypes.byref(transferred))
        assert transferred.value == len(data)

    def pointer(address):
        return struct.unpack('<Q', read(address))[0]

    try:
        def address(value):
            return int(re.fullmatch(r'userdata: (0x[0-9a-fA-F]+)', value)[1], 16)

        player, donor = address(fixture['player_pointer']), address(fixture['donor_pointer'])
        for pet in fixture['pets']:
            pet['pointer'] = address(pet['pointer'])
        assert struct.unpack('<i', read(player + 4, 4))[0] == fixture['player']
        assert struct.unpack('<i', read(donor + 4, 4))[0] == fixture['donor']
        player_inventory, donor_inventory = pointer(player + 0x680), pointer(donor + 0x680)
        # Validate every slot before the first mutation.
        for slot, pet in enumerate(fixture['pets']):
            assert pointer(donor_inventory + slot * 8) == pet['pointer']
            assert pointer(player_inventory + 0x40 + slot * 8) == 0
            assert struct.unpack('<i', read(pet['pointer'] + 4, 4))[0] == pet['index']
            assert pointer(pet['pointer'] + 0x830) == donor
        for slot, pet in enumerate(fixture['pets']):
            write(player_inventory + 0x40 + slot * 8, struct.pack('<Q', pet['pointer']))
            write(donor_inventory + slot * 8, struct.pack('<Q', 0))
            write(pet['pointer'] + 0x830, struct.pack('<Q', player))
    finally:
        api.CloseHandle(handle)
