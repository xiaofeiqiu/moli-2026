"""Compact diagnostics for the staged pack; no game files are changed."""
import collections
import json
from pathlib import Path
from integrate_shared_tasks import OUT, STAGE, DATA
import audit_content as core

m = json.loads((OUT / 'id_mapping.json').read_text(encoding='utf-8'))
defs = collections.defaultdict(dict)
for e in m['entities']:
    defs[e['kind']][e['new_id']] = e
native = json.loads((OUT / 'native_result.json').read_text(encoding='utf-8'))
tables = {}
for kind, key in [('enemy', 2), ('enemybase', 1), ('group', 2), ('itemset', 11)]:
    tables[kind] = {int(c[key]): c for _, c in core.records((STAGE / 'gmsv/data' / (kind+'.txt')).read_bytes()) if len(c)>key and core.number(c[key]) is not None}
names = collections.defaultdict(list)
for id, c in tables['enemybase'].items():
    names[core.label(c[0])].append(id)
enemy_failures = []
for x in native['failures']:
    if x['kind'] != 'enemy': continue
    e = defs['enemy'].get(x['id'])
    c = tables['enemy'][x['id']]
    enemy_failures.append({'id':x['id'],'old_id':e['old_id'],'name':core.label(c[0]),'base':core.number(c[3]),
                           'exact_name_templates':names[core.label(c[0])], 'source':e['path'], 'line':e['line']})
print('NATIVE_ENEMY_FAILURES',json.dumps(enemy_failures,ensure_ascii=False,indent=2))
u = json.loads((OUT/'unresolved.json').read_text(encoding='utf-8'))
print('MISSING_MAPS',json.dumps(collections.Counter(x['floor'] for x in u if x['kind']=='missing_map').most_common(50)))
print('UNRESOLVED_TABLES',json.dumps(collections.Counter(x['table'] for x in u if x['kind']=='unresolved_reference')))
print('MISSING_SCRIPTS',json.dumps(sorted({x['script'] for x in u if x['kind']=='missing_script'}),ensure_ascii=False))
