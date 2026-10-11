import sys
import time
from urllib.request import urlopen
for n in range(50):
    try:
        with urlopen(sys.argv[1],timeout=1) as r:
            if r.status == 200: break
    except OSError: time.sleep(.1)
else: raise SystemExit('Server did not start')
