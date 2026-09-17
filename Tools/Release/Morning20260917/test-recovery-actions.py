import subprocess,json,time,pathlib,hashlib,urllib.request,urllib.error,os
root=pathlib.Path(os.environ.get('GAZE_PREVIEW_OUTPUT_DIR','build/morning-20260917/final'))
baseurl='http://127.0.0.1:55523'
cli=[os.environ.get('AGENT_BROWSER_BIN','/Users/owencope/.npm/_npx/6de2aa2fded2970c/node_modules/.bin/agent-browser'),'--session','gaze-morning']
cookie=json.loads((root/'admin-cookie.json').read_text())
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
results=[]
def api(path,body=None,method=None,authorized=True):
 headers={'Content-Type':'application/json'}
 if authorized:headers['Cookie']=cookie['name']+'='+cookie['value']
 req=urllib.request.Request(baseurl+path,data=None if body is None else json.dumps(body).encode(),headers=headers,method=method or ('POST' if body is not None else 'GET'))
 try:r=opener.open(req,timeout=10)
 except urllib.error.HTTPError as e:r=e
 raw=r.read();return r.code,json.loads(raw) if 'json' in r.headers.get('Content-Type','') else raw.decode(errors='replace')
def run(*args):
 p=subprocess.run(cli+list(args),capture_output=True,text=True,timeout=20)
 if p.returncode:raise RuntimeError(p.stderr or p.stdout)
 return p.stdout.strip()
def ev(js):return json.loads(run('eval',js))
def wait(js):
 end=time.monotonic()+8
 while time.monotonic()<end:
  if ev(js):return
  time.sleep(.07)
 raise AssertionError('Timed out: '+js)
def check(name,condition=True):
 assert condition,name
 results.append(name);(root/'functional-results.json').write_text(json.dumps(results,indent=2)+'\n');print('PASS',name,flush=True)
def click(name):run('find','role','button','click','--name',name)
def goto(path):run('open',baseurl+path);wait('location.pathname==='+json.dumps(path))
def nav(path):run('click','nav[aria-label="Admin"] a[href="'+path+'"]');wait('location.pathname==='+json.dumps(path))
def records():
 status,data=api('/api/releases');assert status==200;return {r['tag']:r for r in data}
def seed(tag,draft,private=False,video=False):
 data={'tag':tag,'name':'Synthetic '+tag,'date':'2026-09-17T00:00:00.000Z','body':'Isolated test fixture.','images':[{'src':baseurl+'/product/setup-welcome-detail.webp','alt':'Fixture image'}] if video else [],'videos':[baseurl+'/previews/gaze-panel-detail.mp4'] if video else [],'contributors':[],'prerelease':False,'draft':draft,'private':private}
 status,_=api('/api/releases',data);assert status==200
pid=subprocess.check_output(['lsof','-nP','-iTCP:55523','-sTCP:LISTEN','-t'],text=True).strip()
cwd=[l[1:] for l in subprocess.check_output(['lsof','-a','-p',pid,'-d','cwd','-Fn'],text=True).splitlines() if l.startswith('n')][0]
assert cwd.startswith('/private/tmp/gaze-site-build-') or cwd.startswith('/tmp/gaze-site-build-')
status,feed=api('/api/latest',authorized=False)
assert status==200 and feed['latest']['name'].startswith('Synthetic build fixture ')
run('cookies','set',cookie['name'],cookie['value'],'--url',baseurl)
run('set','viewport','1280','900')
seed('0.0-qadraft',True,True);seed('0.0-qapublic',False);seed('0.0-qaclip',True,video=True)
goto('/admin/0.0-qadraft/edit');run('find','label','Title','fill','Edited synthetic draft');click('Save draft');wait('location.pathname==="/admin"')
check('Save draft preserves draft and private audience',records()['0.0-qadraft']['draft'] and records()['0.0-qadraft']['private'])
goto('/admin/0.0-qadraft/edit');click('Publish release');wait('location.pathname==="/releases/0.0-qadraft"')
check('Publish is explicit and preserves tester-only audience',not records()['0.0-qadraft']['draft'] and records()['0.0-qadraft']['private'])
check('Published tester-only fixture remains hidden to signed-out readers',api('/releases/0.0-qadraft',authorized=False)[0]==404)
goto('/admin/0.0-qapublic/edit');run('find','label','Title','fill','Edited published fixture');click('Save changes');wait('location.pathname==="/releases/0.0-qapublic"')
check('Save changes preserves published status',not records()['0.0-qapublic']['draft'])
goto('/admin/0.0-qapublic/edit');ev('window.confirm=()=>false;true');click('Unpublish to draft')
check('Cancelling Unpublish does not change publication',not records()['0.0-qapublic']['draft'] and ev('location.pathname')=='/admin/0.0-qapublic/edit')
ev('window.confirm=()=>true;true');click('Unpublish to draft');wait('location.pathname==="/admin"')
check('Confirmed Unpublish creates a draft',records()['0.0-qapublic']['draft'])
goto('/admin/0.0-qaclip/edit')
check('Only image descriptions are editable',ev('document.querySelectorAll("input[aria-label=\\"Image description\\"]").length===1 && !document.querySelector("input[aria-label=\\"Clip description\\"]") && document.body.textContent.includes("Video clip")'))
# Missing storage configuration makes the real local token request fail before file transfer.
goto('/admin/new')
(root/'upload-fixture.zip').write_bytes(b'Synthetic fixture, not a build.')
run('upload','input[type=file][accept^=".dmg"]',str((root/'upload-fixture.zip').resolve()))
wait('[...document.querySelectorAll("h2")].find(x=>x.textContent==="The build").parentElement.querySelector("[role=alert]")!==null')
check('Build upload error stays beside the build control',ev('![...document.querySelectorAll("h2")].find(x=>x.textContent==="Pictures and clips").parentElement.querySelector("[role=alert]")'))
# Notes baseline is read only from the known isolated server copy.
pid=subprocess.check_output(['lsof','-nP','-iTCP:55523','-sTCP:LISTEN','-t'],text=True).strip()
cwd=[l[1:] for l in subprocess.check_output(['lsof','-a','-p',pid,'-d','cwd','-Fn'],text=True).splitlines() if l.startswith('n')][0]
assert cwd.startswith('/private/tmp/gaze-site-build-') or cwd.startswith('/tmp/gaze-site-build-')
notes=pathlib.Path(cwd)/'data/readme.md';sha=lambda text:hashlib.sha256(text.encode()).hexdigest()
baseline='Saved synthetic notes baseline.'
assert api('/api/readme',{'readme':baseline,'expectedVersion':sha(notes.read_text())})[0]==200
key='gaze.readmeDraft.v1:preview@example.test'
ev('sessionStorage.removeItem('+json.dumps(key)+');true')
goto('/admin/readme');run('find','label','Tester notes','fill','Unsaved draft A');nav('/admin');nav('/admin/readme')
wait('document.body.textContent.includes("Restore draft")')
check('Navigation offers explicit recovery without overwriting server text',ev('document.querySelector("#tester-notes").value==='+json.dumps(baseline)+' && document.querySelector("#tester-notes").disabled'))
click('Restore draft');wait('document.querySelector("#tester-notes").value==="Unsaved draft A"')
check('Restore returns the unsaved text and enables editing',not ev('document.querySelector("#tester-notes").disabled'))
click('Save notes');wait('[...document.querySelectorAll("[role=status]")].some(x=>x.textContent==="Saved")')
check('Acknowledged exact draft clears recovery storage',ev('sessionStorage.getItem('+json.dumps(key)+')===null') and notes.read_text()=='Unsaved draft A')
# Delay a real local response while newer typing continues.
ev('''(()=>{window.qaNoteFetch=window.fetch.bind(window);window.fetch=async(input,init)=>{const response=await window.qaNoteFetch(input,init);if(String(input)==='/api/readme'&&init?.method==='POST'){window.qaAck=await response.clone().json();return new Promise(resolve=>{window.qaReleaseAck=()=>resolve(response)})}return response};return true})()''')
run('find','label','Tester notes','fill','Submitted A');click('Save notes');wait('typeof window.qaReleaseAck==="function"');run('find','label','Tester notes','fill','Newer typing B');ev('window.qaReleaseAck();true')
wait('[...document.querySelectorAll("button")].some(x=>x.textContent==="Save notes"&&!x.disabled)')
stored=ev('JSON.parse(sessionStorage.getItem('+json.dumps(key)+'))')
check('Late acknowledgement keeps newer typing with the acknowledged base',ev('document.querySelector("#tester-notes").value==="Newer typing B" && ![...document.querySelectorAll("[role=status]")].some(x=>x.textContent==="Saved")') and stored['text']=='Newer typing B' and stored['baseVersion']==sha('Submitted A'))
ev('window.fetch=window.qaNoteFetch;true');click('Save notes');wait('sessionStorage.getItem('+json.dumps(key)+')===null')
check('Saving the newer draft clears it only after acknowledgement',notes.read_text()=='Newer typing B')
run('find','label','Tester notes','fill','Recovered stale draft');nav('/admin')
assert api('/api/readme',{'readme':'Newer server version','expectedVersion':sha('Newer typing B')})[0]==200
goto('/admin/readme');wait('document.body.textContent.includes("Restore draft")');click('Restore draft');click('Save notes')
wait('document.body.textContent.includes("Someone else saved newer notes")')
check('Stale recovered base receives conflict without overwrite',notes.read_text()=='Newer server version' and ev('document.querySelector("#tester-notes").value==="Recovered stale draft"'))
ev('window.confirm=()=>false;true');click('Reload saved notes')
check('Cancelling conflict reload retains the recovered draft',ev('document.querySelector("#tester-notes").value==="Recovered stale draft"'))
ev('window.confirm=()=>true;true');click('Reload saved notes');wait('document.querySelector("#tester-notes")?.value==="Newer server version"')
check('Confirmed reload clears the old recovery draft',ev('sessionStorage.getItem('+json.dumps(key)+')===null') and not ev('document.body.textContent.includes("Restore draft")'))
# Storage failure cannot block ordinary server saving.
ev('window.qaSetItem=Storage.prototype.setItem;Storage.prototype.setItem=function(){throw new DOMException("Synthetic denied","SecurityError")};true')
run('find','label','Tester notes','fill','Saved despite storage failure')
wait('document.body.textContent.includes("Draft recovery is unavailable")')
click('Save notes');wait('[...document.querySelectorAll("[role=status]")].some(x=>x.textContent==="Saved")')
check('Unavailable storage keeps editing and server save functional',notes.read_text()=='Saved despite storage failure')
ev('Storage.prototype.setItem=window.qaSetItem;true')
# Mobile navigation geometry and actual computed text colors.
run('set','viewport','320','844');goto('/admin/testers')
navdata=ev('({width:innerWidth,links:[...document.querySelectorAll("nav[aria-label=Admin] a")].map(a=>({name:a.getAttribute("aria-label"),left:a.getBoundingClientRect().left,right:a.getBoundingClientRect().right,height:a.getBoundingClientRect().height}))})')
check('All four admin destinations fit at320px',len(navdata['links'])==4 and all(x['left']>=0 and x['right']<=320 and x['height']>=44 for x in navdata['links']))
print('Completed',len(results),'functional checks',flush=True)

# A late response from an unmounted editor must not erase a reopened editor's draft.
goto('/admin/readme')
ev("""(()=>{window.oldNoteFetch=window.fetch.bind(window);window.fetch=async(input,init)=>{const r=await window.oldNoteFetch(input,init);if(String(input)==='/api/readme'&&init?.method==='POST')return new Promise(resolve=>{window.finishOldSave=()=>resolve(r)});return r};return true})()""")
run('find','label','Tester notes','fill','Old pending save after leave');click('Save notes');wait('typeof window.finishOldSave==="function"')
nav('/admin');nav('/admin/readme')
wait('document.querySelector("#tester-notes")?.value==="Old pending save after leave" && !document.querySelector("#tester-notes").disabled')
run('find','label','Tester notes','fill','New draft in reopened editor')
before=ev('sessionStorage.getItem('+json.dumps(key)+')')
ev('window.finishOldSave();true');time.sleep(.25)
after=ev('sessionStorage.getItem('+json.dumps(key)+')')
check('Unmounted acknowledgement cannot erase the reopened editor draft',before is not None and before==after and ev('document.querySelector("#tester-notes").value==="New draft in reopened editor"'))
ev('window.fetch=window.oldNoteFetch;true');click('Save notes');wait('sessionStorage.getItem('+json.dumps(key)+')===null')
check('Reopened editor can save after old request finishes',notes.read_text()=='New draft in reopened editor')
print('Final total:',len(results),'functional checks',flush=True)
