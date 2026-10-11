"""Compile sword/mage task predicates without changing other professions."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'tools/content-audit/templates/sharedTaskAdapters.lua'
RUNTIME = 'gmsv/lua/Modules/sharedTaskAdapters.lua'
HELPER = 'gmsv/lua/Modules/magicTaskJobs.lua'
DATA = 'gmsv/lua/Modules/magicTaskJobsData.lua'
MAGIC = range(181, 188)


def lua(v):
    if v is None: return 'nil'
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, int): return str(v)
    if isinstance(v, str): return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list): return '{' + ','.join(lua(x) for x in v) + '}'
    return '{' + ','.join('[' + lua(k) + ']=' + lua(x) for k, x in v.items()) + '}'


def evaluate(job, c):
    if c.get('field')=='family': job=job//10*10
    ops = {'==': lambda a,b:a==b, '!=':lambda a,b:a!=b,
           '>=':lambda a,b:a>=b, '<=':lambda a,b:a<=b,
           '>':lambda a,b:a>b, '<':lambda a,b:a<b}
    group = ops[c['tests'][0][0]](job, c['tests'][0][1])
    result = False
    for join, (op, target) in zip(c['joins'], c['tests'][1:]):
        value = ops[op](job, target)
        if join == '&&': group = group and value
        else: result, group = result or group, value
    return result or group


def compatible(job, c):
    if job not in MAGIC or c['nativeMagic']: return evaluate(job, c)
    sword, mage = evaluate(job-170, c), evaluate(job-110, c)
    return sword and mage if c['reject'] else sword or mage


def compile_tasks():
    designs = json.loads((ROOT / 'docs/cg71_content_audit/shared_integration/custom_script_designs.json').read_text('utf-8'))
    raw_keys = [c['key'] for c in designs if c.get('target') == 'player'
                and c.get('field') == 'CHAR_职业' and c.get('value') is None and not c.get('jobRangeJobs')]
    token = rb'JobAncestry|Job'
    if raw_keys:
        token += rb'|Luac\s+(?:' + b'|'.join(re.escape(k.encode()) for k in raw_keys) + rb')'
    ws = rb'[ \t\xa1]*'
    operator = rb'(?:>\s*=|<\s*=|!\s*=|=\s*=|>|<)'
    test = rb'(?:' + token + rb')\b' + ws + operator + ws + rb'\d+'
    run = re.compile(test + rb'(?:' + ws + rb'(?:&&|\|\||II)' + ws + test + rb')*', re.I)
    cmp = re.compile(rb'(' + token + rb')\b' + ws + rb'(' + operator + rb')' + ws + rb'(\d+)', re.I)
    catalog_path = ROOT / 'tools/npc-overlap/magic_task_predicates.json'
    conditions = json.loads(catalog_path.read_text('utf-8')) if catalog_path.exists() else {}
    files, cases, changed = {}, {}, []
    for key,c in conditions.items():
        cases[key] = {'expression': c['source'], 'expected': {str(j):int(compatible(j,c)) for j in MAGIC}}
    counts = {'script_files_scanned': 0, 'native_predicate_runs': 0, 'changed_runs': 0,
              'shared_range_predicates': 0, 'shared_ranges_extended': 0}
    for c in designs:
        jobs = c.get('jobRangeJobs')
        if jobs:
            counts['shared_range_predicates'] += 1
            admitted = [j for j in MAGIC if j-170 in jobs or j-110 in jobs or j in jobs]
            if any(j not in jobs for j in admitted): counts['shared_ranges_extended'] += 1
    for path in sorted((ROOT / 'gmsv/data/npc').rglob('*.txt')):
        if path.name == 'event_format.txt': continue
        counts['script_files_scanned'] += 1
        original = path.read_bytes()
        locations = []
        output = []
        for number, line in enumerate(original.splitlines(keepends=True), 1):
            if line.lstrip().startswith((b'#', b'//')):
                output.append(line); continue
            pieces = re.split(rb'("(?:[^"\\]|\\.)*")', line)
            for i in range(0, len(pieces), 2):
                def replace(m):
                    counts['native_predicate_runs'] += 1
                    expression = m[0]
                    parsed=cmp.findall(expression)
                    fields={'family' if name.lower()==b'jobancestry' else 'job' for name,op,value in parsed}
                    assert len(fields)==1,'Mixed job/family predicates require explicit review: '+str(path)
                    tests = [[re.sub(rb'\s+', b'', op).decode(), int(value)] for name,op,value in parsed]
                    joins = [j.decode().replace('II', '||') for j in re.findall(rb'&&|\|\||II', expression)]
                    assert len(tests) == len(joins)+1
                    reject = all(t[0] == '!=' for t in tests)
                    if len(tests) == 2 and joins == ['||']:
                        reject |= tests[0][0] in ('<','<=') and tests[1][0] in ('>','>=') and tests[0][1] <= tests[1][1]
                    c = {'tests': tests, 'joins': joins, 'reject': bool(reject), 'nativeMagic': False,'field':fields.pop()}
                    c['nativeMagic'] = any(180 <= t[1] <= 187 for t in tests) and any(
                        evaluate(j,c) and not (evaluate(j-170,c) or evaluate(j-110,c)) for j in MAGIC)
                    affected = any(compatible(j, c) != evaluate(j, c) for j in MAGIC)
                    if not affected: return expression
                    key = 'msjob:' + hashlib.sha256(lua(c).encode()).hexdigest()[:20]
                    c['source'] = expression.decode('ascii',errors='replace')
                    conditions[key] = c
                    cases[key] = {'expression': expression.decode('ascii', errors='replace'),
                                  'expected': {str(j): int(compatible(j,c)) for j in MAGIC}}
                    locations.append({'line': number, 'key': key, 'expression': cases[key]['expression']})
                    counts['changed_runs'] += 1
                    return ('Luac ' + key + ' >= 1').encode()
                pieces[i] = run.sub(replace, pieces[i])
            output.append(b''.join(pieces))
        data = b''.join(output)
        if data != original:
            rel = path.relative_to(ROOT).as_posix()
            files[rel] = data
            changed.append({'path': rel, 'conditions': locations})
            # Any remaining Job expression must already match the compatibility rule.
            for line in data.splitlines():
                if line.lstrip().startswith((b'#',b'//')): continue
                for piece in re.split(rb'("(?:[^"\\]|\\.)*")', line)[::2]:
                    for m in run.finditer(piece):
                        tests = [[re.sub(rb'\s+', b'', op).decode(), int(value)] for name,op,value in cmp.findall(m[0])]
                        joins = [j.decode().replace('II','||') for j in re.findall(rb'&&|\|\||II',m[0])]
                        # Replacements are fully covered by their generated, native-tested keys.
                        assert tests
    source_bytes = SOURCE.read_bytes()
    runtime_bytes = (ROOT / RUNTIME).read_bytes()
    source = source_bytes.decode('utf-8').replace('\r\n','\n')
    assert source == runtime_bytes.decode('gbk').replace('\r\n','\n'), 'Task adapter source/runtime differ'
    if "local TaskJobs=dofile('lua/Modules/magicTaskJobs.lua')" not in source:
      source = source.replace("local D=dofile('lua/Modules/sharedTaskAdaptersData.lua')", 
                            "local D=dofile('lua/Modules/sharedTaskAdaptersData.lua')\nlocal TaskJobs=dofile('lua/Modules/magicTaskJobs.lua')")
      source = source.replace(" local c=by[text];if not c then return end", 
                            " if TaskJobs.has(text) then\n  if not Char.IsPlayer(p) then return 0 end\n  return TaskJobs.check(get(p,'CHAR_职业'),text,get(p,'CHAR_职类ID'))\n end\n local c=by[text];if not c then return end")
      before = "  if c.jobRangeJobs then for _,id in ipairs(c.jobRangeJobs) do if value==id then return 1 end end;return 0 end"
      assert before in source
      source = source.replace(before, "  if c.jobRangeJobs then return TaskJobs.range(value,c.jobRangeJobs) end")
      before = "  value=c.mode==1 and value+c.value or c.value"
      assert before in source
      source = source.replace(before, before + "\n  if c.target=='player' and c.field=='CHAR_职业' then\n   local promoted=TaskJobs.promotedJob(get(p,'CHAR_职业'),value)\n   if promoted~=value then set(p,'CHAR_职类ID',180);value=promoted end\n  end")
    files[SOURCE.relative_to(ROOT).as_posix()] = source.replace('\n','\r\n' if b'\r\n' in source_bytes else '\n').encode('utf-8')
    files[RUNTIME] = source.replace('\n','\r\n' if b'\r\n' in runtime_bytes else '\n').encode('gbk')
    helper = (ROOT / 'tools/npc-overlap/magic_task_jobs.lua').read_bytes().decode('utf-8')
    files[HELPER] = helper.encode('gbk')
    files[DATA] = ('return ' + lua(conditions) + '\n').encode('gbk')
    files[catalog_path.relative_to(ROOT).as_posix()] = (json.dumps(conditions,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    report = dict(counts, unique_native_checks=len(conditions), changed_script_files=len(changed),
                  jobs=list(MAGIC), sword_jobs=list(range(11,18)), mage_jobs=list(range(71,78)),
                  scope='Job predicates in installed Event scripts and shared task legacy adapters; prerequisites retain their original conditions.',
                  changed_scripts=changed, cases=cases)
    return files, report
