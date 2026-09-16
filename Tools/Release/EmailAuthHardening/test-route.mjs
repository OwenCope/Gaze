import assert from 'node:assert/strict';
import { registerHooks } from 'node:module';
const site='file:///Users/owencope/Developer/gaze-site/';
registerHooks({ resolve(specifier, context, next) {
  if(specifier==='server-only')return {url:'data:text/javascript,export{}',shortCircuit:true};
  if(specifier==='next/server')return {url:site+'node_modules/next/server.js',shortCircuit:true};
  if(specifier==='@/lib/email-code')return {url:site+'src/lib/email-code.ts',shortCircuit:true};
  if(specifier==='@/lib/email-challenge-store') return {url:'data:text/javascript,'+encodeURIComponent(`export const emailCodeEnabled=(...args)=>globalThis.gazeRouteFixture.module.emailCodeEnabled(...args); export const normalizeIp=(...args)=>globalThis.gazeRouteFixture.module.normalizeIp(...args); export const requestCodeFlow=(...args)=>globalThis.gazeRouteFixture.module.requestCodeFlow(...args); export const getProductionChallengeStore=()=>globalThis.gazeRouteFixture.store;`),shortCircuit:true};
  return next(specifier,context);
}});
process.env.NODE_ENV='development';
process.env.AUTH_SECRET='synthetic-secret-for-route-tests';
process.env.RESEND_API_KEY='synthetic-resend-key';
process.env.SIGNIN_EMAIL_FROM='test@example.invalid';
for(const key of ['VERCEL','BLOB_READ_WRITE_TOKEN','BLOB_STORE_ID','BLOB_PRIVATE_READ_WRITE_TOKEN','BLOB_PRIVATE_STORE_ID','VERCEL_OIDC_TOKEN']) delete process.env[key];
const storeModule=await import(site+'src/lib/email-challenge-store.ts');
const codeModule=await import(site+'src/lib/email-code.ts');
const safe=await import(site+'src/lib/safe-callback.ts');
globalThis.gazeRouteFixture={module:storeModule,store:storeModule.createMemoryChallengeStore()};
let sent=[],mailMode='ok';
globalThis.fetch=async (url,init)=> {
  assert.equal(url,'https://api.resend.com/emails');
  assert.equal(init.headers.Authorization,'Bearer synthetic-resend-key');
  assert.ok(init.signal instanceof AbortSignal);
  sent.push(JSON.parse(init.body));
  if(mailMode==='throw')throw new Error('synthetic offline transport');
  return new Response('{}',{status: mailMode==='ok'?200:503});
};
const {POST}=await import(site+'src/app/api/signin-code/route.ts');
let checks=0;
function check(name,fn){fn();checks++;console.log('PASS '+name);}
function request(body){return new Request('http://localhost/api/signin-code',{method:'POST',headers:{'Content-Type':'application/json','x-forwarded-for':'203.0.113.20'},body:JSON.stringify(body)});}
for(const input of [null,[],{}, {email:12},{email:{}},{email:['a@example.invalid']},{email:'bad'}, {email:'a\u0000@example.invalid'}]) {
  const before=sent.length,response=await POST(request(input));
  check('malformed input returns 400 without mail/cookie',()=>{assert.equal(response.status,400);assert.equal(sent.length,before);assert.equal(response.headers.get('set-cookie'),null);});
}
let response=await POST(request({email:'  Test@Example.INVALID '}));
check('normalized successful send returns only ok',()=>assert.equal(response.status,200));
assert.deepEqual(await response.json(),{ok:true});
const cookie=response.cookies.get(codeModule.CODE_COOKIE)?.value;
check('cookie retains HttpOnly and SameSite',()=>{assert.ok(cookie.startsWith('v2.'));assert.match(response.headers.get('set-cookie'),/HttpOnly/i);assert.match(response.headers.get('set-cookie'),/SameSite=lax/i);});
const deliveredCode=sent.at(-1).subject.slice(0,6);
check('address normalized at delivery',()=>assert.equal(sent.at(-1).to,'test@example.invalid'));
const verified=await storeModule.verifyCodeFlow({cookie,emailRaw:'test@example.invalid',codeRaw:deliveredCode,now:Date.now(),store:globalThis.gazeRouteFixture.store});
check('route-issued code verifies once',()=>assert.equal(verified.status,'ok'));
const replay=await storeModule.verifyCodeFlow({cookie,emailRaw:'test@example.invalid',codeRaw:deliveredCode,now:Date.now(),store:globalThis.gazeRouteFixture.store});
check('route-issued cookie replay denied',()=>assert.equal(replay.status,'replay'));
for(let i=0;i<4;i++)assert.equal((await POST(request({email:'test@example.invalid'}))).status,200);
response=await POST(request({email:'test@example.invalid'}));
check('sixth send returns 429 without cookie',()=>{assert.equal(response.status,429);assert.equal(response.headers.get('set-cookie'),null);});
globalThis.gazeRouteFixture.store=storeModule.createFailingChallengeStore();
response=await POST(request({email:'backend@example.invalid'}));
check('storage failure returns 503 without cookie',()=>{assert.equal(response.status,503);assert.equal(response.headers.get('set-cookie'),null);});
globalThis.gazeRouteFixture.store=storeModule.createMemoryChallengeStore();mailMode='throw';
response=await POST(request({email:'offline@example.invalid'}));
check('transport failure returns 502 with no live challenge',()=>{assert.equal(response.status,502);assert.equal(globalThis.gazeRouteFixture.store.size(),0);assert.equal(response.headers.get('set-cookie'),null);});
process.env.NODE_ENV='production'; const before=sent.length;
response=await POST(request({email:'production@example.invalid'}));
check('production without shared state sends nothing',()=>{assert.equal(response.status,503);assert.equal(sent.length,before);});
for(const input of [undefined,null,123,[], '//evil.invalid','https://evil.invalid','javascript:alert(1)','/\\evil.invalid','/\n/evil.invalid']) check('unsafe callback falls back home',()=>assert.equal(safe.safeCallbackPath(input),'/'));
for(const input of ['/','/releases','/releases?tag=0.3#notes','/admin'])check('local callback preserved',()=>assert.equal(safe.safeCallbackPath(input),input));
console.log(`${checks} actual-route/callback checks passed; synthetic transport only.`);
