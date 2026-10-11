#!/usr/bin/env python3
"""Dependency-free catalog server and local pack studio. Public GET, local authenticated publishing."""
import argparse
import hashlib
import json
import os
import secrets
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
from pack_format import MAX_BYTES, valid_id, validate

ROOT = Path(__file__).resolve().parent


def payload(value):
    return (json.dumps(value, indent=2, allow_nan=False) + '\n').encode()


class CatalogServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, packs, token):
        super().__init__(address, Handler)
        self.packs = Path(packs)
        self.packs.mkdir(parents=True, exist_ok=True)
        self.token = token
        self.publish_lock = threading.Lock()

    def catalog(self):
        entries = []
        for path in sorted(self.packs.glob('*.json')):
            try:
                raw = path.read_bytes()
                if len(raw) > MAX_BYTES:
                    continue
                p = validate(json.loads(raw))
                if path.stem != p['id']:
                    continue
                entries.append({k: p[k] for k in ('id', 'version', 'title', 'description') } | {'sha256': hashlib.sha256(raw).hexdigest(), 'size': len(raw)})
            except (ValueError, TypeError, KeyError):
                continue
        return {'format': 1, 'packs': entries}


class Handler(BaseHTTPRequestHandler):
    def respond(self, status, body, content_type='application/json'):
        if not isinstance(body, bytes):
            body = payload(body)
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(body)

    def local(self):
        return self.client_address[0] in ('127.0.0.1', '::1')

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/catalog.json':
            return self.respond(200, self.server.catalog())
        if path in ('/', '/editor') and self.local():
            return self.respond(200, (ROOT / 'editor.html').read_bytes(), 'text/html; charset=utf-8')
        if path.startswith('/packs/') and path.endswith('.json'):
            id = path[len('/packs/'):-5]
            if valid_id(id):
                file = self.server.packs / (id + '.json')
                if file.is_file() and file.stat().st_size <= MAX_BYTES:
                    return self.respond(200, file.read_bytes())
        self.respond(404, {'error': 'Not found'})

    def do_POST(self):
        if not self.local() or not secrets.compare_digest(self.headers.get('X-Editor-Token', ''), self.server.token):
            return self.respond(403, {'error': 'Publishing requires localhost and the editor token'})
        origin = self.headers.get('Origin')
        if origin:
            parsed = urlsplit(origin)
            if parsed.scheme != 'http' or parsed.hostname not in ('localhost', '127.0.0.1') or parsed.port != self.server.server_port:
                return self.respond(403, {'error': 'Invalid origin'})
        if urlsplit(self.path).path != '/publish':
            return self.respond(404, {'error': 'Not found'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= MAX_BYTES:
                return self.respond(413, {'error': 'Pack size must be between 1 byte and 1 MiB'})
            p = validate(json.loads(self.rfile.read(length)))
            raw = payload(p)
            if len(raw) > MAX_BYTES:
                return self.respond(413, {'error': 'Formatted pack exceeds 1 MiB'})
            with self.server.publish_lock:
                path = self.server.packs / (p['id'] + '.json')
                if path.exists() and json.loads(path.read_text())['version'] >= p['version']:
                    return self.respond(409, {'error': 'Increase version before publishing an update'})
                temp = path.with_suffix('.tmp')
                temp.write_bytes(raw)
                temp.replace(path)
            self.respond(200, {'id': p['id'], 'version': p['version'], 'sha256': hashlib.sha256(raw).hexdigest()})
        except (ValueError, KeyError, TypeError) as exc:
            self.respond(400, {'error': str(exc)})
        except OSError:
            self.respond(500, {'error': 'Unable to write pack'})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='0.0.0.0')
    parser.add_argument('--port', type=int, default=8787)
    parser.add_argument('--packs', type=Path, default=ROOT.parent / 'client' / 'packs')
    args = parser.parse_args()
    token = os.environ.get('TYCOON_EDITOR_TOKEN') or secrets.token_urlsafe(24)
    server = CatalogServer((args.host, args.port), args.packs, token)
    print(f'Catalog: http://<this-computers-LAN-IP>:{args.port}/catalog.json', flush=True)
    print(f'Studio: http://localhost:{args.port}/editor', flush=True)
    print(f'Editor token: {token}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
