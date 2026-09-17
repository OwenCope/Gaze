const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { createRequire } = require('node:module');
const root = path.resolve(__dirname, '../../..');
const site = '/Users/owencope/Developer/gaze-site';
const fixture = path.join(root, 'build/gaze-full-ux-20260917/react-fixture');
const dependency = createRequire(path.join(fixture, 'package.json'));
const React = dependency('react');
const { create, act } = dependency('react-test-renderer');
const ts = require(path.join(site, 'node_modules/typescript'));
globalThis.IS_REACT_ACT_ENVIRONMENT = true;

let now = 100_000;
let timerID = 0;
const timers = new Map();
const requests = [];
const signIns = [];
let failSend = false;
function load(file, imports) {
  const source = fs.readFileSync(file, 'utf8');
  const code = ts.transpileModule(source, {compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.ReactJSX,
  }}).outputText;
  const exports = {};
  vm.runInNewContext(code, {exports, require: imports, URL, AbortSignal, console,
    Date: {now: () => now},
    window: {
      setInterval: (callback) => { timers.set(++timerID, callback); return timerID; },
      clearInterval: (id) => timers.delete(id),
      location: {assign: () => { throw new Error('No real navigation in this test'); }},
    },
    fetch: async (url, options) => {
      requests.push({url, method: options.method, body: JSON.parse(options.body)});
      return {ok: !failSend, json: async () => ({error: 'Simulated send failure'})};
    },
  }, {filename: file});
  return exports;
}
const safe = load(path.join(site, 'src/lib/safe-callback.ts'), () => { throw new Error('Unexpected import'); });
const filename = path.join(site, 'src/components/email-sign-in.tsx');
const {EmailSignIn} = load(filename, (name) => {
  if (name === '@/lib/safe-callback') return safe;
  if (name === 'next-auth/react') return {signIn: async (...args) => { signIns.push(args); return {ok: false, error: 'CredentialsSignin'}; }};
  return dependency(name);
});

(async () => {
  let renderer;
  await act(async () => { renderer = create(React.createElement(EmailSignIn, {callbackUrl: '/admin/new'})); });
  const input = (label) => renderer.root.findByProps({'aria-label': label});
  const buttons = () => renderer.root.findAllByType('button');
  const resend = () => buttons().find((b) => String(b.props.children).startsWith('Request a new code'));
  const submit = () => renderer.root.findByType('form').props.onSubmit({preventDefault() {}});
  const change = async (label, value) => act(async () => input(label).props.onChange({target: {value}}));
  const advance = async (milliseconds) => act(async () => {
    now += milliseconds;
    for (const callback of [...timers.values()]) callback();
  });
  await change('Email address', 'preview@example.test');
  await act(submit);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, '/api/signin-code');
  assert.equal(requests[0].body.email, 'preview@example.test');
  assert.equal(resend().props.disabled, true);
  assert.equal(resend().props.children, 'Request a new code in 30s');
  await change('Six-digit sign-in code', '123456');
  assert.equal(buttons().find((b) => b.props.type === 'submit').props.disabled, false);
  await act(async () => resend().props.onClick({preventDefault() {}}));
  assert.equal(requests.length, 1, 'Early resend must not reach transport');
  await advance(29_500);
  assert.equal(resend().props.children, 'Request a new code in 1s');
  await advance(600);
  assert.equal(resend().props.disabled, false);
  assert.equal(timers.size, 0, 'Expired timer must be cleaned up');
  failSend = true;
  await act(async () => resend().props.onClick({preventDefault() {}}));
  assert.equal(input('Six-digit sign-in code').props.value, '123456');
  assert.equal(resend().props.disabled, false, 'A failed resend must not start a cooldown');
  assert.equal(renderer.root.findByProps({role: 'alert'}).props.children, 'Simulated send failure');
  failSend = false;
  await act(async () => resend().props.onClick({preventDefault() {}}));
  assert.equal(input('Six-digit sign-in code').props.value, '');
  assert.equal(resend().props.children, 'Request a new code in 30s');
  await act(async () => buttons().find((b) => b.props.children === 'Use a different address').props.onClick());
  assert.equal(input('Email address').props.value, 'preview@example.test');
  assert.equal(timers.size, 0);
  await act(submit);
  assert.equal(resend().props.disabled, true);
  await act(async () => renderer.unmount());
  assert.equal(timers.size, 0, 'Unmount must clean up the active timer');
  const result = {passed: true, actualComponent: filename,
    sha256: crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex'),
    renderer: 'react-test-renderer 19.2.8', transport: 'stubbed', clock: 'virtual',
    scenarios: ['first send', 'early resend blocked', 'code entry stays enabled', 'wall-clock expiry', 'failure retention', 'successful resend', 'different address', 'unmount cleanup'],
    realEmailsSent: 0, browserLayoutVerified: false};
  fs.writeFileSync(path.join(root, 'build/gaze-full-ux-20260917/email-component-result.json'), JSON.stringify(result, null, 2) + '\n');
  console.log('PASS: actual mounted EmailSignIn component; eight scenarios, fake transport/clock, no emails sent.');
})().catch((error) => { console.error(error); process.exitCode = 1; });
