"""Sync the pet tutor and sanctuary placement to GBK, preserving newlines."""
from pathlib import Path
from pet_skill_policy import install as install_policy
from job_tutors_install import install as install_tutors

ROOT = Path(__file__).resolve().parents[2]


def main():
    for source, runtime in (
        ('tools/skill-library/petSkillTutor.lua', 'gmsv/lua/Modules/petSkillTutor.lua'),
        ('tools/skill-library/skillTraining.lua', 'gmsv/lua/Modules/skillTraining.lua'),
        ('tools/skill-library/skillLibrary.lua', 'gmsv/lua/Modules/skillLibrary.lua'),
        ('tools/sanctuary/sanctuaryData.lua', 'gmsv/lua/Modules/sanctuaryData.lua'),
        ('tools/sanctuary/Npc.lua', 'gmsv/lua/libs/Module/Parts/Npc.lua'),
    ):
        (ROOT / runtime).write_bytes((ROOT / source).read_bytes().decode('utf-8').encode('gbk'))
    config = ROOT / 'gmsv/lua/ModuleConfig.lua'
    raw = config.read_bytes()
    if b"loadModule('petSkillTutor')" not in raw:
        newline = b'\r\n' if b'\r\n' in raw else b'\n'
        config.write_bytes(raw + newline + b"loadModule('petSkillTutor')" + newline)
    install_tutors()
    print('Separate player/pet tutors installed; restart to load native skill permissions.')


if __name__ == '__main__':
    main()
