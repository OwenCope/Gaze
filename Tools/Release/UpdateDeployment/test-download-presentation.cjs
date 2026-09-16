// The public/tester view model must not advertise placeholder or unsafe downloads.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {createRequire,Module}=require('node:module');
const root=process.argv[2] || '/Users/owencope/Developer/gaze-site';
const req=createRequire(path.join(root,'package.json')),ts=req('typescript');
let records=[];
function compile(relative){
  const file=path.join(root,'src/lib',relative+'.ts');
  const source=fs.readFileSync(file,'utf8');
  const out=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,esModuleInterop:true}}).outputText;
  const mod=new Module(file);mod.require=id=>{
    if(id==='./store')return {readAll:async()=>records};
    if(id==='./render-markdown')return {renderMarkdown: text=>text};
    if(id==='./release-download')return compile('release-download');
    return req(id);
  };mod._compile(out,file);return mod.exports;
}
const releases=compile('releases');
const base={tag:'1.0',name:'Synthetic',date:'2026-09-16',body:'notes',images:[],videos:[],contributors:[],draft:false,prerelease:false};
const valid={url:'https://fixture.public.blob.vercel-storage.com/Gaze-abc.dmg',name:'Gaze.dmg',size:100};
(async()=>{
 let checks=0;
 for(const download of [undefined,{url:'/dl/Gaze-0.3.dmg',name:'Gaze-0.3.dmg',size:100},{...valid,url:'javascript:alert(1)'},{...valid,url:'https://example.invalid/app.dmg'},{...valid,size:0}]){
  records=[{...base,download}];
  assert.equal((await releases.getReleases())[0].download,undefined);checks++;
 }
 records=[{...base,download:valid}];assert.deepEqual((await releases.getReleases())[0].download,valid);checks++;
 records=[{...base,private:true,download:valid}];assert.equal((await releases.getReleases()).length,0);checks++;
 assert.deepEqual((await releases.getReleases({includePrivate:true}))[0].download,valid);checks++;
 console.log(`${checks} download-presentation checks passed; no data or network access.`);
})().catch(error=>{console.error(error);process.exitCode=1;});
