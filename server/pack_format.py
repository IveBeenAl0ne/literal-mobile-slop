"""Version 1 data-only tycoon format. Mirrors the native validator."""
import math
import re

MAX_BYTES = 1024 * 1024
ID = re.compile(r'^[a-z0-9_-]{1,48}$')
COLOR = re.compile(r'^#?(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$')
KINDS = {'source', 'processor', 'shop', 'worker', 'decoration'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(v, lo, hi):
    return type(v) in (int, float) and math.isfinite(v) and lo <= v <= hi


def valid_id(v):
    return isinstance(v, str) and ID.fullmatch(v) is not None


def validate(p):
    require(isinstance(p, dict), 'Pack must be an object')
    require(p.get('format') == 1 and valid_id(p.get('id')), 'Invalid format or ID')
    require(number(p.get('version'), 1, 1000000), 'Invalid version')
    for key in ('title', 'description'):
        require(isinstance(p.get(key), str) and len(p[key]) <= 500, f'Invalid {key}')
    require(isinstance(p.get('theme'), dict), 'Missing theme')
    for key in ('ground', 'accent', 'player'):
        require(isinstance(p['theme'].get(key), str) and COLOR.fullmatch(p['theme'][key]), f'Invalid theme {key}')
    require(number(p.get('starting_cash'), 0, 1000000), 'Invalid starting cash')
    require(isinstance(p.get('items'), list) and 1 <= len(p['items']) <= 32, 'Expected 1–32 items')
    items = set()
    for item in p['items']:
        require(isinstance(item, dict) and valid_id(item.get('id')) and item['id'] not in items, 'Invalid/duplicate item')
        require(isinstance(item.get('color'), str) and COLOR.fullmatch(item['color']), 'Invalid item color')
        items.add(item['id'])
    require(isinstance(p.get('stations'), list) and 1 <= len(p['stations']) <= 100, 'Expected 1–100 stations')
    ids = set()
    for s in p['stations']:
        require(isinstance(s, dict) and valid_id(s.get('id')) and s['id'] not in ids, 'Invalid/duplicate station')
        ids.add(s['id'])
        require(s.get('kind') in KINDS, 'Invalid station kind')
        require(isinstance(s.get('name'), str) and len(s['name']) <= 64, 'Invalid station name')
        require(isinstance(s.get('position'), list) and len(s['position']) == 2 and all(number(v, -18, 18) for v in s['position']), 'Invalid position')
        for key in ('cost', 'price', 'capacity', 'cycle'):
            lo = .2 if key == 'cycle' else (1 if key == 'capacity' else 0)
            require(number(s.get(key), lo, 100 if key == 'capacity' else 1000000), f'Invalid {key}')
        if s['kind'] in ('source', 'processor'):
            require(s.get('output') in items, 'Unknown output')
        if s['kind'] in ('processor', 'shop'):
            require(s.get('input') in items, 'Unknown input')
        require(isinstance(s.get('requires', []), list), 'Invalid prerequisites')
        if 'visual' in s:
            require(isinstance(s['visual'], list) and len(s['visual']) <= 64, 'Too many model parts')
            for part in s['visual']:
                require(isinstance(part, dict) and part.get('shape') in ('box', 'cylinder', 'cone', 'sphere'), 'Invalid model shape')
                require(isinstance(part.get('color'), str) and COLOR.fullmatch(part['color']), 'Invalid model color')
                for key in ('position', 'size'):
                    require(isinstance(part.get(key), list) and len(part[key]) == 3 and all(number(v, -5 if key == 'position' else .01, 5) for v in part[key]), 'Invalid model vector')
    for s in p['stations']:
        require(all(isinstance(d, str) and d in ids and d != s['id'] for d in s.get('requires', [])), 'Invalid prerequisite')
        if s['kind'] == 'worker':
            require(s.get('target') in ids, 'Invalid worker target')
    visited = set()
    for _ in ids:
        for s in p['stations']:
            if set(s.get('requires', [])) <= visited:
                visited.add(s['id'])
    require(visited == ids, 'Circular prerequisites')
    return p
