"""Validate custom profession services and item effects in the isolated server."""
from pathlib import Path
from validate_shared_tasks_native import RUN,start,stop,probe_config
stop()
text=(Path(__file__).parent/'templates/sharedServicesProbe.lua').read_text(encoding='utf-8')
(RUN/'lua/shared_services_probe.lua').write_bytes(text.encode('gbk'))
(RUN/'lua/ModuleConfig.lua').write_bytes(probe_config('shared_services_probe.lua'))
start()
