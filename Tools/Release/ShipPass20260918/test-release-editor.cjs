const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../../..');
const site = path.resolve(root, '../gaze-site');
const deps = path.join(root, 'build/gaze-full-ux-20260917/react-fixture/node_modules');
const React = require(path.join(deps, 'react'));
const { create, act } = require(path.join(deps, 'react-test-renderer'));
const ts = require(path.join(site, 'node_modules/typescript'));
global.IS_REACT_ACT_ENVIRONMENT = true;

const memory = new Map();
const listeners = new Map();
const requests = [];
const navigations = [];
let unavailable = false;
let focused;
let response = { status: 409, body: { error: 'Changed elsewhere.' } };
const browser = {
  sessionStorage: {
    getItem(key) { if (unavailable) throw new Error('Storage unavailable'); return memory.get(key) ?? null; },
    setItem(key, value) { if (unavailable) throw new Error('Storage unavailable'); memory.set(key, value); },
    removeItem(key) { if (unavailable) throw new Error('Storage unavailable'); memory.delete(key); },
  },
  addEventListener(name, callback) { listeners.set(name, callback); },
  removeEventListener(name, callback) { if (listeners.get(name) === callback) listeners.delete(name); },
};
const element = tag => React.forwardRef(function FixtureElement({ children, ...props }, ref) {
  return React.createElement(tag, { ...props, ref }, children);
});
const motion = new Proxy({}, { get: (_, tag) => motionComponents[tag] ??= element(tag) });
const motionComponents = {};
const modules = {
  react: React,
  'react/jsx-runtime': require(path.join(deps, 'react/jsx-runtime')),
  'next/navigation': { useRouter: () => ({ push: url => navigations.push(url), refresh() {} }) },
  'framer-motion': { AnimatePresence: ({ children }) => children, motion, useReducedMotion: () => true },
  '@vercel/blob/client': { upload: async () => { throw new Error('Uploads are forbidden in this fixture'); } },
  '@/components/ui/liquid-glass-button': { LiquidButton: element('button') },
};
function load(relative) {
  const { outputText } = ts.transpileModule(fs.readFileSync(path.join(site, relative), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2022 },
    fileName: relative,
  });
  const exports = {};
  vm.runInNewContext(outputText, {
    exports, URL, console, window: browser,
    requestAnimationFrame: fn => { fn(); return 1; },
    require: name => {
      if (!Object.hasOwn(modules, name)) throw new Error(`Unexpected dependency ${name}`);
      return modules[name];
    },
    fetch: async (url, options) => {
      assert.equal(url, '/api/releases');
      requests.push(JSON.parse(options.body));
      return { ok: response.status === 200, status: response.status, json: async () => response.body };
    },
  }, { filename: relative });
  return exports;
}
modules['@/lib/release-draft'] = load('src/lib/release-draft.ts');
const { ReleaseComposer } = load('src/components/release-composer.tsx');
let view;
function text(node) {
  if (typeof node === 'string') return node;
  if (Array.isArray(node)) return node.map(text).join('');
  return node?.children ? text(node.children) : '';
}
function button(label) {
  return view.root.findAllByType('button').find(node => text(node) === label);
}
async function mount(key, initial) {
  await act(async () => {
    view = create(React.createElement(ReleaseComposer, {
      draftKey: key, initial, initialVersion: initial ? 'a'.repeat(64) : 'missing',
    }), { createNodeMock: el => ({ focus() { focused = el.props.id; } }) });
  });
}
async function edit(id, value) {
  await act(async () => view.root.findByProps({ id }).props.onChange({ target: { value } }));
}
async function click(label) {
  const target = button(label);
  assert(target, `Missing button ${label}`);
  await act(async () => target.props.onClick());
}
async function unmount() { await act(async () => view.unmount()); }
function unloadIsGuarded() {
  let prevented = false;
  listeners.get('beforeunload')?.({ preventDefault() { prevented = true; }, returnValue: undefined });
  return prevented;
}

async function run() {
  const key = 'fixture:new';
  await mount(key);
  await click('Save draft');
  assert.equal(focused, 'tag');
  assert.equal(requests.length, 0);
  assert.equal(view.root.findByProps({ id: 'tag' }).props['aria-invalid'], true);
  await edit('tag', 'not-a-version');
  await edit('name', 'Fixture release');
  await click('Save draft');
  assert.equal(focused, 'tag');
  assert.equal(requests.length, 0);
  await edit('tag', '1.2.3');
  await edit('date', '');
  await click('Save draft');
  assert.equal(focused, 'date');
  assert.equal(requests.length, 0);
  await edit('date', '2026-09-18');
  await edit('body', 'Notes retained through a conflict.');
  assert(unloadIsGuarded());
  await click('Save draft');
  assert.equal(requests.length, 1);
  assert.equal(requests[0].expectedVersion, 'missing');
  assert.equal(navigations.length, 0);
  assert.equal(view.root.findByProps({ id: 'body' }).props.value, 'Notes retained through a conflict.');
  assert(memory.get(key).includes('Notes retained through a conflict.'));
  await unmount();
  assert.equal(listeners.size, 0);

  await mount(key);
  assert(button('Restore draft'));
  assert.equal(view.root.findByProps({ id: 'body' }).props.value, '');
  assert.equal(view.root.findByType('fieldset').props.disabled, true);
  assert(unloadIsGuarded());
  await click('Restore draft');
  assert.equal(view.root.findByProps({ id: 'body' }).props.value, 'Notes retained through a conflict.');
  assert.equal(view.root.findByType('fieldset').props.disabled, false);
  response = { status: 200, body: { tag: 'wrong-tag' } };
  await click('Save draft');
  assert(memory.has(key));
  assert.equal(navigations.length, 0);
  response = { status: 200, body: { tag: '1.2.3' } };
  await click('Save draft');
  assert.equal(memory.has(key), false);
  assert.equal(navigations.at(-1), '/admin');
  assert.equal(unloadIsGuarded(), false);
  await unmount();

  unavailable = true;
  await mount('fixture:blocked');
  assert(text(view.toJSON()).includes('recovery'));
  await edit('tag', '1.0');
  assert(unloadIsGuarded());
  await unmount();
  unavailable = false;
  console.log('PASS: mounted release validation, focus, zero invalid requests, conflict retention, explicit recovery, response confirmation, save cleanup, and blocked-storage unload protection');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
