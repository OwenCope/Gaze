// Compile and exercise the actual site renderer; no server, secrets or remote requests.
const {readFileSync}=require('node:fs');
const {createRequire,Module}=require('node:module');
const path=require('node:path');
const site=process.argv[2] || '/Users/owencope/Developer/gaze-site';
const req=createRequire(path.join(site,'package.json'));
const ts=req('typescript');
const file=path.join(site,'src/lib/render-markdown.ts');
const source=readFileSync(file,'utf8');
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,esModuleInterop:true}}).outputText;
const mod=new Module(file);mod.filename=file;
mod.require=(id)=>id==='server-only'?{}:req(id);
mod._compile(compiled,file);
globalThis.gazeMarkdownFixture={renderMarkdown:mod.exports.renderMarkdown,parseDocument:req('htmlparser2').parseDocument};
import('./fixture.mjs').catch(error=>{console.error(error);process.exitCode=1;});
