"""Run a temporary probe in the existing isolated task runtime and restore it."""
from pathlib import Path
import json
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'docs/npc_overlap_fix'
RUN = ROOT / 'backups/content71/shared-task-integration-20261004/native_runtime/gmsv'

def run(name, npc_source=None, extra_files=None, config='moduleInitial()\n'):
    OUT.mkdir(parents=True, exist_ok=True)
    result = OUT / (name + '.json')
    if result.exists():
        result.unlink()
    files = {
        'data/npc.txt': (npc_source or ROOT / 'gmsv/data/npc.txt').read_bytes(),
        'lua/ModuleConfig.lua': (config + "dofile('lua/npc_overlap_probe.lua')\n").encode('gbk'),
        'lua/npc_overlap_probe.lua': (HERE / (name + '.lua')).read_text('utf-8').replace('__OUTPUT__', result.as_posix()).encode('gbk'),
    }
    files.update(extra_files or {})
    originals = {rel: (RUN / rel).read_bytes() if (RUN / rel).exists() else None for rel in files}
    process = None
    try:
        for rel, data in files.items():
            path = RUN / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        with (OUT / (name + '.log')).open('wb') as log:
            process = subprocess.Popen([str(RUN / 'cgmsv.exe')], cwd=RUN, stdin=subprocess.DEVNULL,
                                       stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            deadline = time.monotonic() + 100
            report = None
            while time.monotonic() < deadline and process.poll() is None:
                if result.exists():
                    raw = result.read_bytes()
                    try:
                        try:
                            report = json.loads(raw.decode('utf-8'))
                        except UnicodeDecodeError:
                            report = json.loads(raw.decode('gbk'))
                    except json.JSONDecodeError:
                        pass  # The native writer may have just opened the file.
                    else:
                        break
                time.sleep(.25)
            if report is None:
                raise RuntimeError(f'No complete probe report; exit={process.poll()}; see {log.name}')
            result.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', 'utf-8')
            print(json.dumps({'status': report['status'], 'report': str(result), 'error': report.get('error')}, ensure_ascii=False))
            return report
    finally:
        if process is not None:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)
        for rel, original in originals.items():
            path = RUN / rel
            if original is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(original)

if __name__ == '__main__':
    run(sys.argv[1])
