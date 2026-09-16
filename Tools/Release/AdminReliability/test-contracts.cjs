const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { Module, createRequire } = require('node:module');
const site = process.env.GAZE_SITE_DIR || '/Users/owencope/Developer/gaze-site';
const req = createRequire(path.join(site, 'package.json'));
const ts = req('typescript');
let allowed = true, failed = false, writes = [], revalidations = [], passed = 0;
const write = (kind) => async (value) => {
  if (failed) throw new Error('synthetic backend detail must not be exposed');
  writes.push({kind, value});
  return kind === 'settings' ? value : [];
};
function load(relative, dependencies = {}) {
  const file = path.join(site, relative), mod = new Module(file);
  mod.require = (id) => Object.hasOwn(dependencies, id) ? dependencies[id] : req(id);
  mod._compile(ts.transpileModule(fs.readFileSync(file, 'utf8'), {compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,esModuleInterop:true}}).outputText, file);
  return mod.exports;
}
const permissions = load('src/lib/permissions.ts');
const shared = {
  '@/auth': {auth: async () => ({user:{isAdmin:allowed}})},
  '@/lib/viewer': {getViewer: async () => ({can: (key) => { assert.equal(key,'manageRoles'); return allowed; }})},
  'next/cache': {revalidatePath: (value) => revalidations.push(value)},
  '@/lib/permissions': permissions,
};
const routes = {
  settings: load('src/app/api/settings/route.ts', {...shared, '@/lib/settings': {getSettings:async()=>({releasesRequireSignIn:false}),saveSettings:write('settings')}}),
  testers: load('src/app/api/testers/route.ts', {...shared, '@/lib/testers': {readTesters:async()=>[],addTester:write('tester'),removeTester:write('removeTester')}}),
  roles: load('src/app/api/roles/route.ts', {...shared, '@/lib/roles': {readRoles:async()=>[],upsertRole:write('role'),removeRole:write('removeRole')}}),
};
const request = (kind, body, method = 'POST', query = '') => new Request(`http://localhost/api/${kind}${query}`, {
  method, ...(method === 'POST' ? {headers:{'content-type':'application/json'},body:JSON.stringify(body)} : {})
});
async function rejectsBody(kind, body) {
  const before=writes.length, invalidations=revalidations.length;
  const result=await routes[kind].POST(request(kind,body));
  assert.equal(result.status,400,kind+' malformed body');
  assert.equal(typeof (await result.json()).error,'string');
  assert.equal(writes.length,before);assert.equal(revalidations.length,invalidations);passed++;
}
(async()=>{
  for (const kind of Object.keys(routes)) {
    for (const body of [null,[],false,42,'text',{}]) await rejectsBody(kind,body);
    const before=writes.length;
    const result=await routes[kind].POST(new Request(`http://localhost/api/${kind}`,{method:'POST',body:'{'}));
    assert.equal(result.status,400);assert.equal(writes.length,before);passed++;
  }
  for (const value of [0,'true',null,{},[]]) await rejectsBody('settings',{releasesRequireSignIn:value});
  for (const extra of [{email:4},{email:'bad'},{github:4},{note:{}},{roles:'tester'},{roles:[null]},{roles:['']}]) await rejectsBody('testers',{email:'person@example.test',...extra});
  for (const extra of [{name:4},{name:' '},{id:4},{id:''},{color:'red'},{color:'#0000'},{permissions:'viewPrivate'},{permissions:['constructor']},{permissions:[null]}]) await rejectsBody('roles',{name:'Reviewers',...extra});
  let result=await routes.settings.POST(request('settings',{releasesRequireSignIn:false,unknown:'not persisted'}));
  assert.equal(result.status,200);assert.deepEqual(writes.at(-1),{kind:'settings',value:{releasesRequireSignIn:false}});passed++;
  result=await routes.testers.POST(request('testers',{email:' Person@example.test ',github:'person',note:'synthetic',roles:[]}));
  assert.equal(result.status,200);assert.equal(writes.at(-1).value.email,'Person@example.test');assert.deepEqual(writes.at(-1).value.roles,[]);passed++;
  result=await routes.roles.POST(request('roles',{name:'Reviewers',color:'#abc',permissions:['viewPrivate']}));
  assert.equal(result.status,200);assert.equal(writes.at(-1).value.color,'#abc');passed++;
  result=await routes.roles.POST(request('roles',{name:'Reviewers'}));
  assert.equal(result.status,200);assert.equal(writes.at(-1).value.color,'#34C759');assert.deepEqual(writes.at(-1).value.permissions,[]);passed++;
  for (const [kind,query] of [['roles','?id='],['testers','?email=bad'],['testers','']]) {
    const count=writes.length;result=await routes[kind].DELETE(request(kind,null,'DELETE',query));assert.equal(result.status,400);assert.equal(writes.length,count);passed++;
  }
  for (const [kind,query] of [['roles','?id=reviewers'],['testers','?email=person%40example.test']]) {
    result=await routes[kind].DELETE(request(kind,null,'DELETE',query));assert.equal(result.status,200);passed++;
  }
  allowed=false;
  for (const kind of Object.keys(routes)) {
    const count=writes.length;
    assert.equal((await routes[kind].GET()).status,403);
    assert.equal((await routes[kind].POST(request(kind,null))).status,403);
    if(routes[kind].DELETE) assert.equal((await routes[kind].DELETE(request(kind,null,'DELETE'))).status,403);
    assert.equal(writes.length,count);passed++;
  }
  allowed=true;failed=true;
  for (const [kind,body] of [['settings',{releasesRequireSignIn:true}],['testers',{email:'person@example.test'}],['roles',{name:'Reviewers'}]]) {
    const count=writes.length,invalidations=revalidations.length;
    result=await routes[kind].POST(request(kind,body));assert.equal(result.status,503);
    assert(!(await result.text()).includes('synthetic backend detail'));assert.equal(writes.length,count);assert.equal(revalidations.length,invalidations);passed++;
  }
  for (const [kind,query] of [['roles','?id=reviewers'],['testers','?email=person%40example.test']]) {
    result=await routes[kind].DELETE(request(kind,null,'DELETE',query));assert.equal(result.status,503);passed++;
  }
  const client=load('src/lib/admin-response.ts',{'./permissions':permissions});
  assert.equal(client.isSettings({releasesRequireSignIn:'false'}),false);passed++;
  assert.equal(client.isTesterList([{email:'person@example.test',addedAt:'now',roles:4}]),false);passed++;
  assert.equal(client.isRoleList([{id:'r',name:'R',color:'#abc',permissions:['constructor']}]),false);passed++;
  await assert.rejects(()=>client.readAdminResponse(new Response('<html>',{status:502}),client.isSettings,'Could not save'),/HTTP 502/);passed++;
  await assert.rejects(()=>client.readAdminResponse(Response.json({ok:true}),client.isSettings,'Could not save'),/could not be confirmed/);passed++;
  assert.deepEqual(await client.readAdminResponse(Response.json({releasesRequireSignIn:true}),client.isSettings,'Could not save'),{releasesRequireSignIn:true});passed++;
  console.log(`${passed} admin request/response contract checks passed. Actual route and client source; auth, storage and revalidation stubbed.`);
})().catch(error=>{console.error(error);process.exitCode=1;});
