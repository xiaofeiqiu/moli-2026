"""Exercise the pet equipment NPC in the isolated sanctuary server."""
import sys
from verify import main

if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main('pet_equip_probe.lua', 'pet_equip_result')
