"""Run pet recovery checks on isolated ports and an empty test SQLite database."""
from pathlib import Path
import argparse
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/skill-library'))
import training_verify

training_verify.RUN = ROOT / 'backups/five_pet_recovery/native_runtime/gmsv'
training_verify.OUT = ROOT / 'docs/five_pet'
training_verify.HERE = Path(__file__).resolve().parent
if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('probe', nargs='?', default='smart_ai', choices=('recovery', 'regen_area', 'guard_followup', 'smart_ai', 'strong_guard', 'strong_guard_levels', 'pet_support_levels', 'revive_levels'))
    args = parser.parse_args()
    if args.probe == 'strong_guard':
        training_verify.RUN = ROOT / 'backups/five_pet_strong_guard/native_runtime/gmsv'
    if args.probe == 'strong_guard_levels':
        training_verify.RUN = ROOT / 'backups/five_pet_strong_guard_levels/native_runtime/gmsv'
    if args.probe == 'pet_support_levels':
        training_verify.RUN = ROOT / 'backups/five_pet_support_levels/native_runtime/gmsv'
    if args.probe == 'revive_levels':
        training_verify.RUN = ROOT / 'backups/five_pet_revive_levels/native_runtime/gmsv'
    if args.probe == 'regen_area':
        training_verify.RUN = ROOT / 'backups/five_pet_regen_area/native_runtime/gmsv'
    if args.probe == 'guard_followup':
        training_verify.RUN = ROOT / 'backups/five_pet_guard_followup/native_runtime/gmsv'
    if args.probe == 'smart_ai':
        training_verify.RUN = ROOT / 'backups/five_pet_smart_ai/native_runtime/gmsv'
    training_verify.main(args.probe)
