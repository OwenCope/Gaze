const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '../../..');
const site = path.resolve(root, '../gaze-site');
const fixture = path.join(root, 'build/gaze-full-ux-20260917/react-fixture/node_modules');
const React = require(path.join(fixture, 'react'));
const { act, create } = require(path.join(fixture, 'react-test-renderer'));
const ts = require(path.join(site, 'node_modules/typescript'));
global.IS_REACT_ACT_ENVIRONMENT = true;

const empty = () => null;
const base = {
  react: React,
  'react/jsx-runtime': require(path.join(fixture, 'react/jsx-runtime')),
  'next/link': ({ children, ...props }) => React.createElement('a', props, children),
  '@/components/app-icon': { AppIcon: empty },
  '@/components/email-sign-in': { EmailSignIn: empty },
};

function load(relative, mocks) {
  const source = fs.readFileSync(path.join(site, relative), 'utf8');
  const { outputText } = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX,
      target: ts.ScriptTarget.ES2022, esModuleInterop: true },
    fileName: relative,
  });
  const module = { exports: {} };
  vm.runInNewContext(outputText, {
    module, exports: module.exports, console,
    require(name) {
      if (Object.hasOwn(mocks, name)) return mocks[name];
      if (Object.hasOwn(base, name)) return base[name];
      throw new Error(`Unexpected dependency: ${name}`);
    },
  }, { filename: relative });
  return module.exports;
}

async function run() {
  let resolveRequest;
  let rejectRequest;
  const requests = [];
  const { SignInPage } = load('src/components/ui/sign-in.tsx', {
    'next-auth/react': { signIn: (provider, options) => {
      requests.push({ provider, options });
      return new Promise((resolve, reject) => {
        resolveRequest = resolve;
        rejectRequest = reject;
      });
    } },
  });
  let view;
  await act(async () => {
    view = create(React.createElement(SignInPage, {
      providers: { google: true, github: true, email: false },
      callbackUrl: '/admin/testers',
    }));
  });
  let first;
  await act(async () => {
    const button = view.root.findAllByType('button')[0];
    first = button.props.onClick();
    button.props.onClick();
  });
  assert.equal(requests.length, 1, 'rapid double click starts one OAuth request');
  assert(view.root.findAllByType('button').every(button => button.props.disabled));
  await act(async () => {
    rejectRequest(new Error('Simulated provider failure'));
    await first;
  });
  assert(view.root.findAllByType('button').every(button => !button.props.disabled));
  assert.equal(view.root.findByProps({ role: 'alert' }).children.join(''),
    'Couldn’t open sign-in. Try again.');
  let retry;
  await act(async () => { retry = view.root.findAllByType('button')[1].props.onClick(); });
  assert.equal(requests.length, 2);
  assert.equal(requests[1].provider, 'github');
  assert.equal(requests[1].options.callbackUrl, '/admin/testers');
  assert.equal(view.root.findAllByProps({ role: 'alert' }).length, 0);
  await act(async () => { resolveRequest(); await retry; });
  assert(view.root.findAllByType('button').every(button => !button.props.disabled));
  await act(async () => { view.unmount(); });
  console.log('PASS: mounted OAuth duplicate guard, visible failure, retry, callback preservation and settled busy state');

  let privateReads = 0;
  let signedIn = true;
  const privateRead = async () => { privateReads++; throw new Error('Private data must not be fetched'); };
  const { default: TestersPage } = load('src/app/testers/page.tsx', {
    '@/auth': { auth: async () => signedIn ? { user: { isAdmin: false } } : null },
    'next/navigation': { redirect: destination => { throw new Error(`redirect:${destination}`); } },
    '@/lib/viewer': { getViewer: async () => ({ can: () => false }) },
    '@/lib/releases': { getReleases: privateRead },
    '@/lib/storage': { readReadme: privateRead },
    '@/lib/commits': { getCommits: privateRead, getTree: privateRead },
    '@/lib/render-markdown': { renderMarkdown: () => { throw new Error('No private markdown'); } },
    '@/components/top-nav': { TopNav: empty },
    '@/components/ui/liquid-glass-button': { LiquidButton: ({ children }) => children },
    '@/components/icons': { Tag: empty, Cards: empty },
  });
  const page = await TestersPage();
  await act(async () => { view = create(page); });
  assert.equal(view.root.findByType('h1').children.join(''), 'Tester access required');
  assert.equal(privateReads, 0);
  await act(async () => { view.unmount(); });
  signedIn = false;
  await assert.rejects(TestersPage(), /redirect:\/signin\?callbackUrl=\/testers/);
  assert.equal(privateReads, 0);
  console.log('PASS: denied tester sees an explanation; signed-out redirect and zero private-data reads preserved');
}

run().catch(error => { console.error(error); process.exitCode = 1; });
