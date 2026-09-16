#!/usr/bin/env python3
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from functools import partial
from html.parser import HTMLParser
import urllib.request
import sys
root=Path(__file__).resolve().parent
base='http://127.0.0.1:55523'
class Links(HTMLParser):
    links=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if tag=='link' and a.get('rel')=='stylesheet' and a.get('href','').startswith('/_next/'):
            self.links.append(a['href'])
parser=Links()
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
parser.feed(opener.open(base,timeout=5).read().decode())
assert parser.links,'Build the local preview first so the fixture can use its actual CSS.'
css=''.join('<link rel="stylesheet" href="'+base+p+'">' for p in parser.links)
(root/'index.html').write_text('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'+css+'<title>Synthetic admin fixture</title></head><body><div id="root"></div><script src="app.js"></script></body></html>')
server=ThreadingHTTPServer(('127.0.0.1',int(sys.argv[1]) if len(sys.argv)>1 else 18474),partial(SimpleHTTPRequestHandler,directory=str(root)))
print('Synthetic admin fixture ready',flush=True)
server.serve_forever()
