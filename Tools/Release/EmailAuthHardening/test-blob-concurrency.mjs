// Real SDK error classes, in-memory transport: no HTTP, credentials, or live stores.
import assert from 'node:assert/strict';
import { registerHooks } from 'node:module';
registerHooks({ resolve(specifier, context, next) {
  if (specifier === '@/lib/email-code') return { url: 'file:///Users/owencope/Developer/gaze-site/src/lib/email-code.ts', shortCircuit: true };
  if (specifier === 'server-only') return { url: 'data:text/javascript,export{}', shortCircuit: true };
  return next(specifier, context);
}});
const { BlobPreconditionFailedError, BlobNotFoundError, BlobError } = await import('/Users/owencope/Developer/gaze-site/node_modules/@vercel/blob/dist/index.js');
const mod = await import(process.argv.includes('--current') ? 'file:///Users/owencope/Developer/gaze-site/src/lib/email-challenge-store.ts' : './email-challenge-store.proposed.ts');
const code = await import(process.argv.includes('--current') ? 'file:///Users/owencope/Developer/gaze-site/src/lib/email-code.ts' : './email-code.proposed.ts');
for (const key of ['BLOB_READ_WRITE_TOKEN', 'BLOB_STORE_ID', 'BLOB_PRIVATE_STORE_ID', 'VERCEL', 'VERCEL_OIDC_TOKEN']) delete process.env[key];
process.env.NODE_ENV = 'development';
process.env.AUTH_SECRET = 'synthetic-test-secret-only';
process.env.RESEND_API_KEY = 'synthetic-mailer-only';
process.env.SIGNIN_EMAIL_FROM = 'synthetic@example.invalid';
process.env.BLOB_PRIVATE_READ_WRITE_TOKEN = 'synthetic-private-only';
const now = 1_720_000_000_000;
let checks = 0;
function check(label, callback) { callback(); checks++; console.log(`PASS ${label}`); }
function fixture() {
  const data = new Map();
  const writes = [];
  let rev = 0;
  let readMode = 'normal';
  const sdk = {
    BlobPreconditionFailedError, BlobNotFoundError,
    async get(path, options) {
      assert.equal(options.access, 'private'); assert.equal(options.useCache, false);
      assert.equal(options.token, 'synthetic-private-only');
      const entry = data.get(path);
      if (!entry) return null;
      if (readMode === 'outage') throw new BlobError('unavailable');
      return {
        statusCode: readMode === '304' ? 304 : 200,
        blob: { etag: readMode === 'no-etag' ? '' : entry.etag },
        stream: new Response(readMode === 'corrupt' ? '{' : entry.body).body,
      };
    },
    async put(path, body, options) {
      assert.equal(options.access, 'private'); assert.equal(options.token, 'synthetic-private-only');
      assert.equal(options.addRandomSuffix, false);
      const prior = data.get(path);
      if (options.ifMatch !== undefined && prior?.etag !== options.ifMatch) throw new BlobPreconditionFailedError();
      if (!options.allowOverwrite && prior) throw new BlobError('already exists');
      if (prior) assert.equal(options.ifMatch, prior.etag, 'updates must use CAS');
      const etag = `revision-${++rev}`;
      data.set(path, { body, etag }); writes.push({ path, options });
      return { etag };
    },
    async del(path) { data.delete(path); },
  };
  return { data, writes, sdk, mode(value) { readMode = value; }, store: () => mod.createBlobChallengeStore(async () => sdk) };
}
{
  const f = fixture();
  const results = await Promise.all(Array.from({ length: 40 }, () => f.store().checkAndRecordSend('a@example.invalid', null, now)));
  check('simultaneous first sends cannot exceed five per address', () => {
    assert.equal(results.filter(r => r.status === 'ok').length, 5);
    assert.equal([...f.data.values()].map(x => JSON.parse(x.body))[0].count, 5);
  });
  check('initial counter put refuses overwrite', () => assert.equal(f.writes[0].options.allowOverwrite, false));
}
{
  const f = fixture();
  const results = await Promise.all(Array.from({length: 40}, (_,i) => f.store().checkAndRecordSend(`${i}@example.invalid`, '203.0.113.2', now)));
  check('concurrent cross-address sends respect shared IP budget', () => assert.ok(results.filter(r => r.status === 'ok').length <= 20));
}
{
  const f = fixture(), id = 'a'.repeat(32);
  const record = { email: 'a@example.invalid', createdAt: now, expiresAt: now + code.CODE_TTL_MS, attempts: 0, consumed: false };
  assert.equal((await f.store().create(id, record)).status, 'ok');
  const result = await Promise.all(Array.from({length: 12}, () => f.store().tryConsume(id, now)));
  check('concurrent valid replays have exactly one winner', () => assert.equal(result.filter(r=>r.status==='ok').length, 1));
  check('real SDK precondition errors re-read spent state', () => assert.ok(result.filter(r=>r.status==='consumed').length > 0));
}
{
  const f = fixture(), id = 'b'.repeat(32);
  await f.store().create(id, {email:'b@example.invalid',createdAt:now,expiresAt:now+code.CODE_TTL_MS,attempts:0,consumed:false});
  await Promise.all(Array.from({length:25}, () => f.store().recordFailedAttempt(id,now)));
  check('concurrent wrong guesses cannot lose attempt increments', () => assert.equal(JSON.parse(f.data.get(`auth/challenges/${id}.json`).body).attempts,5));
  check('correct code refused after parallel exhausted attempts', () => {});
  assert.equal((await f.store().tryConsume(id,now)).status,'locked');
}
for (const mode of ['304','no-etag','corrupt','outage']) {
  const f = fixture();
  await f.store().checkAndRecordSend('a@example.invalid',null,now);
  const before = f.writes.length; f.mode(mode);
  const result = await f.store().checkAndRecordSend('a@example.invalid',null,now);
  check(`${mode} fails closed without a reset/write`, () => { assert.equal(result.status,'backend'); assert.equal(f.writes.length,before); });
}
for (const bad of [{count:-1}, {count:1,windowStart:0}, {count:'1'}, {count:1.5}]) {
  const f=fixture(); await f.store().checkAndRecordSend('a@example.invalid',null,now);
  const entry=[...f.data.values()][0]; entry.body=JSON.stringify(bad);
  const before=f.writes.length;
  const result=await f.store().checkAndRecordSend('a@example.invalid',null,now);
  check('invalid counter fails closed',()=>{assert.equal(result.status,'backend');assert.equal(f.writes.length,before);});
}
delete process.env.BLOB_PRIVATE_READ_WRITE_TOKEN;
{
  const first=mod.getProductionChallengeStore(), second=mod.getProductionChallengeStore();
  check('development requests share one store',()=>assert.equal(first,second));
  const requested=await mod.requestCodeFlow({emailRaw:'dev@example.invalid',ipRaw:null,now,store:first,sendEmail:async()=>({ok:true}),makeCode:()=> '123456'});
  const verified=await mod.verifyCodeFlow({cookie:requested.cookieValue,emailRaw:'dev@example.invalid',codeRaw:'123456',now,store:second});
  check('development send then verify succeeds across factory calls',()=>assert.equal(verified.status,'ok'));
}
process.env.NODE_ENV='production';
check('standalone production never uses memory',()=>{assert.equal(mod.storeStatus().mode,'unconfigured');assert.equal(mod.emailCodeEnabled(),false);});
process.env.BLOB_PRIVATE_STORE_ID='private-store';
check('OIDC store without explicit token remains unavailable',()=>assert.equal(mod.emailCodeEnabled(),false));
process.env.VERCEL_OIDC_TOKEN='synthetic-oidc';
check('explicit private OIDC enables shared storage',()=>assert.equal(mod.emailCodeEnabled(),true));
process.env.BLOB_PRIVATE_READ_WRITE_TOKEN='same-synthetic'; process.env.BLOB_READ_WRITE_TOKEN='same-synthetic';
check('public credential reuse refused',()=>assert.equal(mod.emailCodeEnabled(),false));
console.log(`${checks} integration checks passed; no network or real state used.`);
