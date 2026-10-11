import copy
import hashlib
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'server'))
from pack_format import validate
from server import CatalogServer

ROOT = Path(__file__).resolve().parents[1]

class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.pack = json.loads((ROOT/'client/packs/sunny_farm.json').read_text())
        self.server = CatalogServer(('127.0.0.1', 0), self.temp.name, 'test-secret')
        self.url = f'http://127.0.0.1:{self.server.server_port}'
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def post(self, p, token='test-secret'):
        return urlopen(Request(self.url+'/publish', data=json.dumps(p).encode(), headers={'X-Editor-Token':token}, method='POST'))

    def test_publish_download_and_update(self):
        with self.post(self.pack) as r: self.assertEqual(r.status,200)
        with urlopen(self.url+'/catalog.json') as r: entry=json.load(r)['packs'][0]
        with urlopen(self.url+'/packs/sunny_farm.json') as r: raw=r.read()
        self.assertEqual(entry['sha256'],hashlib.sha256(raw).hexdigest())
        self.assertEqual(json.loads(raw),self.pack)
        with self.assertRaises(HTTPError) as cm: self.post(self.pack)
        self.assertEqual(cm.exception.code,409)
        self.pack['version'] += 1
        with self.post(self.pack) as r: self.assertEqual(r.status,200)

    def test_publish_denies_wrong_token(self):
        with self.assertRaises(HTTPError) as cm: self.post(self.pack,'wrong')
        self.assertEqual(cm.exception.code,403)

    def test_rejects_invalid_pack_without_overwriting(self):
        with self.post(self.pack): pass
        p=copy.deepcopy(self.pack);p['version'] += 1;p['stations'][0]['output']='missing'
        with self.assertRaises(HTTPError) as cm: self.post(p)
        self.assertEqual(cm.exception.code,400)
        self.assertEqual(self.server.catalog()['packs'][0]['version'],self.pack['version'])

    def test_bad_dependencies_and_path_traversal(self):
        p=copy.deepcopy(self.pack);p['id']='../escape'
        with self.assertRaises(ValueError):validate(p)
        p=copy.deepcopy(self.pack);p['stations'][0]['requires']=['market'];p['stations'][1]['requires']=['patch']
        with self.assertRaises(ValueError):validate(p)
        with self.assertRaises(HTTPError):urlopen(self.url+'/packs/../server.py.json')

    def test_all_starter_packs(self):
        for path in (ROOT/'client/packs').glob('*.json'):validate(json.loads(path.read_text()))

if __name__ == '__main__':unittest.main()
