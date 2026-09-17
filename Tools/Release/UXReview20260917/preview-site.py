#!/usr/bin/env python3
"""Build an isolated local UX preview. Never copies credentials or production data."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import sys

root = Path(__file__).resolve().parents[3]
site = Path('/Users/owencope/Developer/gaze-site')
preview = root / 'build/gaze-full-ux-20260917/site-preview'
assert preview.is_relative_to(root / 'build') and preview != site
preview.mkdir(parents=True, exist_ok=True)
shutil.copytree(site / 'src', preview / 'src', dirs_exist_ok=True)
for name in ['package.json', 'tsconfig.json', 'next-env.d.ts', 'next.config.ts', 'postcss.config.mjs']:
    source = site / name
    if source.is_file():
        shutil.copy2(source, preview / name)
for name in ['public', 'node_modules']:
    link = preview / name
    if not link.exists():
        link.symlink_to(site / name, target_is_directory=True)

overrides = {
    'src/auth.ts': '''
const session = {user: {id: "preview", name: "Preview owner", email: "preview@example.test", image: null, isAdmin: true}, expires: "2099-01-01T00:00:00.000Z"};
export async function auth() { return session; }
export const handlers = {
  GET: async (request: Request) => request.url.includes("/csrf")
    ? Response.json({csrfToken: "local-preview"}) : Response.json(session),
  POST: async () => Response.json({error: "Authentication is simulated in this local preview."}, {status: 403}),
};
export async function signIn(...args: unknown[]): Promise<never> { throw new Error("Preview authentication is disabled"); }
export async function signOut(...args: unknown[]): Promise<never> { throw new Error("Preview authentication is disabled"); }
''',
    'src/proxy.ts': '''
import { NextResponse, type NextRequest } from "next/server";
export function proxy(request: NextRequest) {
  if (!["GET", "HEAD", "OPTIONS"].includes(request.method) && request.nextUrl.pathname !== "/api/signin-code") {
    return NextResponse.json({error: "Writes are disabled in the local UX preview."}, {status: 403});
  }
  return NextResponse.next();
}
export const config = { matcher: "/:path*" };
''',
    'src/app/api/signin-code/route.ts': '''
export async function POST(request: Request) {
  const {email} = await request.json();
  if (email === "fail@example.test") return Response.json({error: "Simulated send failure. Your address is kept."}, {status: 503});
  return Response.json({ok: true, simulated: true});
}
''',
}
for path, text in overrides.items():
    (preview / path).write_text(text.strip() + '\n')

signin = preview / 'src/app/signin/page.tsx'
source = signin.read_text()
provider_line = 'email: Boolean(process.env.RESEND_API_KEY && process.env.SIGNIN_EMAIL_FROM && emailCodeEnabled()),'
assert provider_line in source
signin.write_text(source.replace(provider_line, 'email: true,'))

layout = preview / 'src/app/layout.tsx'
source = layout.read_text()
layout.write_text(source.replace('</body>', '<div style={{position:"fixed",bottom:0,left:0,right:0,zIndex:9999,padding:"5px 12px",background:"#202020",color:"#fff",fontSize:12,textAlign:"center"}}>Local UX preview · sample data · email simulated · writes disabled</div></body>'))

data = preview / 'data'
data.mkdir(exist_ok=True)
releases = [
    {'tag':'preview-draft','name':'An upcoming Gaze update','date':'2026-09-17T00:00:00Z',
     'body':'This is a sample draft for checking the editor link.','images':[], 'videos':[], 'contributors':[], 'prerelease':True,'draft':True,'private':False},
    {'tag':'preview-0.4','name':'A more comfortable setup','date':'2026-09-16T00:00:00Z',
     'body':'Clearer setup recovery and controls that stay close at hand.\n\n## What changed\n\n- Retry camera setup without going back.\n- Find your enrolled faces near the top.\n\nThis is sample content for the local design review.',
     'images':[{'src':'/product/setup-companion.webp','alt':'Gaze companion in the setup preview'}],
     'videos':[],'contributors':[],'prerelease':False,'draft':False,'private':False},
]
for name, value in {'releases.json': releases, 'testers.json':[{'email':'preview@example.test','roles':[],'addedAt':'2026-09-17T00:00:00Z'}],
                    'roles.json': [], 'settings.json':{'releasesRequireSignIn':False}}.items():
    (data / name).write_text(json.dumps(value, indent=2)+'\n')
(data / 'readme.md').write_text('# Local tester preview\n\nThis page uses sample data. No production account or build is loaded.\n')

manifest = {
    'canonical':str(site), 'preview':str(preview),
    'purpose':'UI layout/interaction only; simulated auth, email and data; mutation routes blocked',
    'overrides':list(overrides)+['src/app/signin/page.tsx providers.email', 'src/app/layout.tsx preview banner'],
    'sourceHashes':{str(p.relative_to(site/'src')):hashlib.sha256(p.read_bytes()).hexdigest() for p in (site/'src').rglob('*') if p.is_file()},
}
(preview.parent/'site-preview-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Prepared {preview}', flush=True)
if '--serve' in sys.argv:
    environment={'PATH':os.environ['PATH'], 'NODE_ENV':'development', 'NEXT_TELEMETRY_DISABLED':'1'}
    if 'TMPDIR' in os.environ: environment['TMPDIR']=os.environ['TMPDIR']
    os.chdir(preview)
    os.execvpe('node', ['node', str(site/'node_modules/next/dist/bin/next'), 'dev', '--webpack', '--hostname', '127.0.0.1', '--port', '55524'], environment)
