// Actual current storage + store + API, with a versioned in-memory SDK transport.
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const {Module,createRequire}=require('node:module');
const site='/Users/owencope/Developer/gaze-site',req=createRequire(path.join(site,'package.json')),ts=req('typescript');
const {BlobPreconditionFailedError}=req('@vercel/blob');
for(const key of ['BLOB_READ_WRITE_TOKEN','BLOB_STORE_ID','BLOB_PRIVATE_STORE_ID','VERCEL_OIDC_TOKEN'])delete process.env[key];
process.env.VERCEL='1';process.env.BLOB_PRIVATE_READ_WRITE_TOKEN='synthetic-private-only';
let raw='[]',version=0,puts=0,gets=0,admin=true;
const sdk={BlobPreconditionFailedError,
 async get(key,opts){assert.equal(key,'releases.json');assert.equal(opts.access,'private');assert.equal(opts.token,'synthetic-private-only');assert.equal(opts.useCache,false);gets++;return {statusCode:200,blob:{etag:`v${version}`},stream:new Response(raw).body};},
 async put(key,text,opts){assert.equal(key,'releases.json');assert.equal(opts.access,'private');assert.equal(opts.token,'synthetic-private-only');assert.equal(opts.allowOverwrite,true);assert.equal(opts.addRandomSuffix,false);if(opts.ifMatch!==`v${version}`)throw new BlobPreconditionFailedError();raw=text;version++;puts++;return {etag:`v${version}`};}
};
function stack(){
 const cache=new Map();
 function load(rel){
  if(cache.has(rel))return cache.get(rel);
  const file=path.join(site,rel),mod=new Module(file);cache.set(rel,mod.exports);
  mod.require=id=>{
   if(id==='@vercel/blob')return sdk;
   if(id==='@/auth')return {auth:async()=>({user:{isAdmin:admin}})};
   if(id==='next/cache')return {revalidatePath(){}};
   if(id.startsWith('@/'))return load('src/'+id.slice(2)+'.ts');
   return req(id);
  };
  mod._compile(ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,esModuleInterop:true}}).outputText,file);
  cache.set(rel,mod.exports);return mod.exports;
 }
 return {storage:load('src/lib/storage.ts'),store:load('src/lib/store.ts'),api:load('src/app/api/releases/route.ts')};
}
const release=(tag)=>({tag,name:`Synthetic ${tag}`,date:'2026-09-16T00:00:00.000Z',body:'Synthetic notes',images:[],videos:[],contributors:[],draft:false,private:false,prerelease:false});
function seed(tags){raw=JSON.stringify(tags.map(release));version=0;puts=0;gets=0;}
let checks=0;
function check(name,fn){fn();checks++;console.log('PASS '+name);}
const post=(api,body)=>api.POST(new Request('http://localhost/api/releases',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}));
(async()=>{
 const a=stack(),b=stack();
 seed(['1.0']);await Promise.all([a.store.upsert(release('1.1'),'1.0'),b.store.upsert(release('2.0'))]);
 check('rename plus independent creation preserves both',()=>{assert.deepEqual(JSON.parse(raw).map(r=>r.tag).sort(),['1.1','2.0']);assert.equal(puts,2);assert.ok(gets>=3);});
 seed(['1.0','2.0']);const collision=await Promise.allSettled([a.store.upsert(release('3.0'),'1.0'),b.store.upsert(release('3.0'),'2.0')]);
 check('concurrent rename collision has one winner without erasing loser',()=>{assert.equal(collision.filter(r=>r.status==='fulfilled').length,1);assert.equal(JSON.parse(raw).length,2);assert.equal(puts,1);});
 seed(['1.0']);await Promise.allSettled([a.store.remove('1.0'),b.store.upsert(release('1.1'),'1.0')]);
 check('delete winning before rename cannot resurrect old record',()=>assert.deepEqual(JSON.parse(raw),[]));
 for(const invalid of [null,[],{tag:1,name:'x'},{tag:'1.1',name:[]},{tag:'1.1',name:'x',previousTag:[]},{tag:'1.1',name:'x',previousTag:''},{tag:'1.1',name:'x',previousTag:null},{tag:'1.1',name:'x',date:'tomorrow'},{tag:'1.1',name:'x',body:{}},{tag:'1.1',name:'x',contributors:[{}]},{tag:'1.1',name:'x',private:'false'},{tag:'1.1',name:'x',download:{url:'/dl/Gaze.dmg',name:'Gaze.dmg',size:1}}]){
  seed(['1.0']);const response=await post(a.api,invalid);
  check('malformed release input refused before storage',()=>{assert.equal(response.status,400);assert.equal(gets,0);assert.equal(puts,0);});
 }
 seed(['1.0']);const response=await post(a.api,{...release('1.1'),previousTag:' 1.0 '});const body=await response.json();
 check('actual API and CAS commit rename with canonical source',()=>{assert.equal(response.status,200);assert.equal(body.tag,'1.1');assert.equal('previousTag' in JSON.parse(raw)[0],false);assert.equal(puts,1);});
 seed(['1.0']);admin=false;const denied=await post(a.api,release('1.2'));
 check('non-admin cannot reach metadata',()=>{assert.equal(denied.status,403);assert.equal(gets,0);assert.equal(puts,0);});
 await assert.rejects(()=>a.storage.mutateMetadata('../outside.json',()=>({text:'{}',result:null})),/Unsupported/);
 check('runtime document allowlist refuses unsupported keys',()=>assert.equal(gets,0));
 console.log(`${checks} combined checks passed; no real auth, storage or network.`);
})().catch(e=>{console.error(e);process.exitCode=1;});
