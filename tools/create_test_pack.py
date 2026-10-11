import json
import sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
p = json.loads((root/'client/packs/sunny_farm.json').read_text())
p['id']='download_test'
p['title']='Downloaded Test Farm'
Path(sys.argv[1]).mkdir(parents=True, exist_ok=True)
(Path(sys.argv[1])/'download_test.json').write_text(json.dumps(p))

import shutil
covers = Path(sys.argv[1]) / 'covers'
covers.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'client/assets/covers/sunny_farm.png', covers / 'download_test.png')
