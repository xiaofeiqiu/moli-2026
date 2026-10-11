"""Install only the pet upgrade NPC and its shared placement, preserving newlines."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def install():
    for source, runtime in (
        ('tools/skill-library/petSkillUpgrade.lua', 'gmsv/lua/Modules/petSkillUpgrade.lua'),
        ('tools/sanctuary/sanctuaryData.lua', 'gmsv/lua/Modules/sanctuaryData.lua'),
    ):
        src, dst = ROOT / source, ROOT / runtime
        raw = dst.read_bytes() if dst.exists() else src.read_bytes()
        newline = '\r\n' if b'\r\n' in raw else '\n'
        text = src.read_bytes().decode('utf-8').replace('\r\n', '\n')
        dst.write_bytes(text.replace('\n', newline).encode('gbk'))
    config = ROOT / 'gmsv/lua/ModuleConfig.lua'
    raw = config.read_bytes()
    if b"loadModule('petSkillUpgrade')" not in raw:
        newline = b'\r\n' if b'\r\n' in raw else b'\n'
        config.write_bytes(raw + (b'' if raw.endswith(b'\n') else newline)
                           + b"loadModule('petSkillUpgrade')" + newline)
    print('Installed petSkillUpgrade at sanctuary 38,18; GM can load/reload it or restart.')


if __name__ == '__main__':
    install()
