"""Validate custom giant creation and combat in an isolated native server."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/skill-library'))
import training_verify

training_verify.RUN = ROOT / 'backups/green_giant_20261011/native_runtime/gmsv'
training_verify.OUT = ROOT / 'docs/custom_pets'
training_verify.HERE = Path(__file__).resolve().parent

if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    training_verify.main('green_giant')
