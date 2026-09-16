const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {createRequire,Module}=require('node:module');
const site='/Users/owencope/Developer/gaze-site',req=createRequire(path.join(site,'package.json')),ts=req('typescript');
const file=path.join(site,'src/app/api/readme/route.ts');
let admin=true,writes=[],failWrite=false,conflict=false,revalidated=[],checks=0;
const version='a'.repeat(64),savedVersion='b'.repeat(64);
class ReadmeConflictError extends Error {}
const mod=new Module(file);mod.require=id=>{
 if(id==='@/auth')return {auth:async()=>({user:{isAdmin:admin}})};
 if(id==='@/lib/readme')return {ReadmeConflictError,saveReadmeDocument:async(text,expectedVersion)=>{if(failWrite)throw new Error('synthetic storage failure');if(conflict)throw new ReadmeConflictError('Synthetic stale draft');writes.push({text,expectedVersion});return {version:savedVersion};}};
 if(id==='next/cache')return {revalidatePath(value){revalidated.push(value);}};
 return req(id);
};
mod._compile(ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,esModuleInterop:true}}).outputText,file);
const post=body=>mod.exports.POST(new Request('http://localhost/api/readme',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}));
(async()=>{
 for(const input of [null,[],{}, {readme:3},{readme:null},{readme:['text']}]){
  const res=await post(input);assert.equal(res.status,400);assert.equal(writes.length,0);checks++;
 }
 let res=await mod.exports.POST(new Request('http://localhost/api/readme',{method:'POST',body:'{'}));assert.equal(res.status,400);assert.equal(writes.length,0);checks++;
 for(const expectedVersion of [undefined,null,42,'','A'.repeat(64),'a'.repeat(63)]) {
  res=await post({readme:'text',expectedVersion});assert.equal(res.status,400);assert.equal(writes.length,0);checks++;
 }
 res=await post({readme:'',expectedVersion:'missing'});assert.equal(res.status,200);assert.deepEqual(await res.json(),{ok:true,version:savedVersion});assert.deepEqual(writes,[{text:'',expectedVersion:'missing'}]);checks++;
 res=await post({readme:'  # Exact text\n',expectedVersion:version});assert.equal(res.status,200);assert.deepEqual(writes.at(-1),{text:'  # Exact text\n',expectedVersion:version});assert.deepEqual(revalidated,['/testers','/admin/readme','/testers','/admin/readme']);checks++;
 admin=false;res=await post({readme:'denied',expectedVersion:version});assert.equal(res.status,403);assert.equal(writes.length,2);checks++;
 admin=true;conflict=true;res=await post({readme:'stale',expectedVersion:version});assert.equal(res.status,409);assert.deepEqual(await res.json(),{error:'Synthetic stale draft'});assert.equal(writes.length,2);assert.equal(revalidated.length,4);checks++;
 conflict=false;failWrite=true;await assert.rejects(()=>post({readme:'failed',expectedVersion:version}),/synthetic storage/);assert.equal(writes.length,2);assert.equal(revalidated.length,4);checks++;
 console.log(`${checks} current notes-route cases passed; document service stubbed, no real authentication, data or network.`);
})().catch(e=>{console.error(e);process.exitCode=1;});
