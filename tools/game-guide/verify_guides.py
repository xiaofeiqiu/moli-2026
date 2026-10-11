"""Check guide coverage, local links, and current source hashes; read-only."""
from pathlib import Path
from urllib.parse import unquote, urlsplit
import collections
import hashlib
import json
import re

import build_guides as b


def main():
    manifest = json.loads((b.OUT/'维护/来源清单.json').read_text(encoding='utf8'))
    errors = []
    for name, digest in manifest['sources'].items():
        path = b.ROOT/name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            errors.append('来源变化或缺失：'+name)
    expected = {t['unit'] for t in b.CATALOG}
    actual = [t['unit'] for t in manifest['shared']]
    if set(actual) != expected or len(actual) != len(expected):
        errors.append('共享任务目录缺项或重复')
    if {p['unit'] for p in manifest['supplements']} != set(b.UNITS)-expected:
        errors.append('目录外附属资料缺项')
    pages = manifest['native']+manifest['shared']+manifest['supplements']+list(manifest['steps'].values())
    for page in pages:
        if not (b.OUT/page['path']).is_file():
            errors.append('缺少攻略页：'+page['path'])
    links = 0
    markdown = list(b.OUT.rglob('*.md'))
    for path in markdown:
        content = path.read_text(encoding='utf8')
        if '\ufffd' in content:
            errors.append('文本包含替换字符：'+str(path.relative_to(b.OUT)))
        for target in re.findall(r'\]\(([^\n]+?)\)', content):
            target = target.strip('<>')
            if target.startswith(('#','http:','https:','mailto:')):
                continue
            links += 1
            resolved = path.parent/unquote(urlsplit(target).path)
            if not resolved.exists():
                errors.append('失效链接：'+str(path.relative_to(b.OUT))+' -> '+target)
    # These published novice values must still match the current source.
    config = b.src.text(b.ROOT/'gmsv/cgmsv.cf')
    for key, value in {'maxlevel':200,'baseexprate':20,'battleskillexprate':20,
                       'productskillexprate':20,'charuppoint':10,'petuppoint':2,'extbagpage':3}.items():
        if not re.search(r'(?m)^'+key+'='+str(value)+r'\s*$', config):
            errors.append('新手规则需重写：'+key)
    source = b.src.text(b.ROOT/'tools/sanctuary/sanctuaryData.lua')
    runtime = b.src.text(b.ROOT/'gmsv/lua/Modules/sanctuaryData.lua')
    if source.replace('\r\n','\n') != runtime.replace('\r\n','\n'):
        errors.append('圣殿位置源码与运行副本不一致')
    for fragment in ['floor=60003','arrival={x=24,y=36}',
                     'return_arrival={x=223,y=86}',
                     'map=1000,x=223,y=85','map=60003,x=32,y=34']:
        if fragment not in source:
            errors.append('新手圣殿位置需重写：'+fragment)
    novice = (b.OUT/'新手攻略.md').read_text(encoding='utf8')
    for value in ['223,85','24,36','32,34','223,86','60003','国民衫','国民袍','/difficulty 1']:
        if value not in novice:
            errors.append('新手攻略缺少关键内容：'+value)
    summary = dict(markdown=len(markdown), local_links=links, source_hashes=len(manifest['sources']),
                   native=len(manifest['native']), catalog=len(actual),
                   supplementary=len(manifest['supplements']), steps=len(manifest['steps']), errors=errors)
    print(json.dumps(summary,ensure_ascii=False,indent=2))
    if errors:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
