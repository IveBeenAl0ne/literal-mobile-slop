"""Check distributed GLBs before mobile export, including geometry bounds/budget."""
import json
import math
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class ModelTests(unittest.TestCase):
    def test_glb_integrity_and_mobile_budget(self):
        manifest = json.loads((ROOT / 'client/assets/models/manifest.json').read_text())
        self.assertEqual(len(manifest), 31)
        self.assertLess(sum(m['triangles'] for m in manifest), 60000)
        for entry in manifest:
            with self.subTest(asset=entry['file']):
                raw = (ROOT / 'client/assets/models' / entry['file']).read_bytes()
                self.assertEqual(struct.unpack_from('<III', raw), (0x46546c67, 2, len(raw)))
                size, kind = struct.unpack_from('<II', raw, 12)
                self.assertEqual(kind, 0x4e4f534a)
                gltf = json.loads(raw[20:20+size])
                binary_size, kind = struct.unpack_from('<II', raw, 20+size)
                self.assertEqual(kind, 0x004e4942)
                self.assertEqual(binary_size, len(raw)-28-size)
                self.assertLess(entry['triangles'], 7000)
                for view in gltf['bufferViews']:
                    self.assertLessEqual(view['byteOffset']+view['byteLength'], binary_size)
                for accessor in gltf['accessors']:
                    self.assertTrue(all(math.isfinite(v) for v in accessor['min']+accessor['max']))
                    self.assertTrue(all(lo <= hi for lo,hi in zip(accessor['min'], accessor['max'])))
                triangles = sum(gltf['accessors'][p['attributes']['POSITION']]['count']//3 for mesh in gltf['meshes'] for p in mesh['primitives'])
                self.assertEqual(triangles, entry['triangles'])

    def test_malformed_asset_choices_are_rejected(self):
        import sys
        import copy
        sys.path.insert(0, str(ROOT / 'server'))
        from pack_format import validate
        original = json.loads((ROOT / 'client/packs/sunny_farm.json').read_text())
        for value in ['../../arbitrary.glb', [], {}, 3]:
            pack = copy.deepcopy(original)
            pack['stations'][0]['model'] = value
            with self.assertRaises(ValueError): validate(pack)
            pack = copy.deepcopy(original)
            pack['setting'] = value
            with self.assertRaises(ValueError): validate(pack)
