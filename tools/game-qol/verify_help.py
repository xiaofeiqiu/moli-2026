"""Check configured Lua chat commands against help, README, and GBK copies."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def uncomment(source):
    source = re.sub(r'--\[\[.*?\]\]', '', source, flags=re.S)
    return re.sub(r'--[^\n]*', '', source)


def commands(source):
    source = uncomment(source)
    names = set(re.findall(r'function\s+commands\.([A-Za-z0-9_]+)\s*\(', source))
    names.update(re.findall(r'\bregCommand\s*\(\s*[\'\"]([^\'\"]+)', source))
    names.update(re.findall(r'[\'\"]/([A-Za-z0-9_\u4e00-\u9fff]+)', source))
    comparisons = [
        r'\bcommand(?:\s*:\s*lower\s*\(\s*\))?\s*(?:==|~=)\s*[\'\"]([^\'\"]+)',
        r'string\.lower\s*\(\s*command\s*\)\s*(?:==|~=)\s*[\'\"]([^\'\"]+)',
    ]
    for pattern in comparisons:
        names.update(re.findall(pattern, source))
    # Automatic QoL switches dispatch through DEFAULT[command].
    if 'DEFAULT[command]' in source:
        defaults = re.search(r'local\s+DEFAULT\s*=\s*\{([^}]+)\}', source)
        assert defaults, 'QoL DEFAULT table missing'
        names.update(re.findall(r'([A-Za-z0-9_]+)\s*=\s*(?:true|false)', defaults[1]))
    return {name.lower() for name in names}


def verify():
    catalog = (HERE / 'commandHelp.lua').read_text('utf-8')
    documented = set()
    for names, usage, description in re.findall(
        r"entry\(\{([^}]*)\},'([^']*)','([^']*)'", catalog
    ):
        assert usage.strip() and description.strip(), 'Empty help usage or description'
        for name in re.findall(r"'([^']+)'", names):
            assert '/' + name.lower() in usage.lower(), f'Help usage omits alias {name}'
            documented.add(name.lower())
    readme = (ROOT / 'README.md').read_text('utf-8')
    readme_names = {name.lower() for name in re.findall(r'/([A-Za-z0-9_\u4e00-\u9fff]+)', readme)}
    config = uncomment((ROOT / 'gmsv/lua/ModuleConfig.lua').read_bytes().decode('gbk'))
    configured = re.findall(r'loadModule\s*\(\s*[\'\"]([^\'\"]+)', config)
    discovered = set()
    for module in configured:
        path = ROOT / f'gmsv/lua/Modules/{module}.lua'
        found = commands(path.read_bytes().decode('gbk'))
        missing = found - documented
        assert not missing, f'{module}: commands missing from /help: {sorted(missing)}'
        missing = found - readme_names
        assert not missing, f'{module}: commands missing from README: {sorted(missing)}'
        discovered.update(found)
    assert not documented - discovered, f'Help documents unknown commands: {sorted(documented - discovered)}'
    for source, runtime in (
        (HERE / 'commandHelp.lua', ROOT / 'gmsv/lua/Modules/commandHelp.lua'),
        (HERE / 'gameQoL.lua', ROOT / 'gmsv/lua/Modules/gameQoL.lua'),
        (HERE / 'fight.lua', ROOT / 'gmsv/lua/Modules/fight.lua'),
        (ROOT / 'tools/module-reload/admin.lua', ROOT / 'gmsv/lua/Modules/admin.lua'),
        (ROOT / 'tools/five-pet/fivePet.lua', ROOT / 'gmsv/lua/Modules/fivePet.lua'),
    ):
        assert source.read_text('utf-8') == runtime.read_bytes().decode('gbk').replace('\r\n', '\n'), \
            f'Source/runtime mismatch: {runtime.relative_to(ROOT)}'
    print(f'PASS: {len(discovered)} command names/aliases across {len(configured)} configured modules; '
          'help, README, and UTF-8/GBK copies agree.')


if __name__ == '__main__':
    verify()
