from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
for name, terms in [
    ('lua参考/CONST.lua', ['職', '职', '声望', '最大血', 'BattleCom', '战斗Index', '宠道栏', '道具_耐久', '道具_最大耐久', '道具_数量', '道具_类型', '道具_已鉴定']),
    ('gmsv/lua/Modules/adminCommands.lua', ['Job', '职业', '职系', '职阶']),
    ('lua参考/Char.lua', ['SetSkill', 'Gold', 'ItemNum']),
]:
    print(name)
    print('\n'.join(x for x in (ROOT/name).read_bytes().decode('gbk', errors='replace').splitlines() if any(t in x for t in terms)))
