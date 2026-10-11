"""Generate a catalog and optionally copy packs for any static HTTP host."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'server'))
from pack_format import MAX_BYTES, validate


def export_catalog(packs, output):
    entries = []
    files = []
    for path in sorted(Path(packs).glob('*.json')):
        raw = path.read_bytes()
        if len(raw) > MAX_BYTES:
            raise ValueError(f'{path}: exceeds pack size limit')
        pack = validate(json.loads(raw))
        if path.stem != pack['id']:
            raise ValueError(f'{path}: filename must match pack ID')
        entries.append({key: pack[key] for key in ('id', 'version', 'title', 'description')} |
                       {'sha256': hashlib.sha256(raw).hexdigest(), 'size': len(raw)})
        files.append((path.name, raw))
    if len(entries) > 100:
        raise ValueError('Catalog supports at most 100 packs')
    catalog = (json.dumps({'format': 1, 'packs': entries}, indent=2) + '\n').encode()
    if len(catalog) > MAX_BYTES:
        raise ValueError('Catalog exceeds client response size limit')
    output = Path(output)
    (output / 'packs').mkdir(parents=True, exist_ok=True)
    for name, raw in files:
        (output / 'packs' / name).write_bytes(raw)
    # Publish the matching hashes after writing every pack.
    (output / 'catalog.json').write_bytes(catalog)
    return catalog


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packs', type=Path, default=ROOT / 'client' / 'packs')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'client')
    parser.add_argument('--check', action='store_true', help='Check committed catalog without writing files')
    args = parser.parse_args()
    if args.check:
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            generated = export_catalog(args.packs, directory)
        if not (args.output_dir / 'catalog.json').exists() or (args.output_dir / 'catalog.json').read_bytes() != generated:
            sys.exit('Catalog is stale. Run python tools/export_catalog.py and commit client/catalog.json.')
    else:
        export_catalog(args.packs, args.output_dir)
