import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('../BrowserExtension/background.js', import.meta.url), 'utf8');
function event() {
  const callbacks = [];
  return { addListener: callback => callbacks.push(callback), emit: (...args) => callbacks.forEach(callback => callback(...args)) };
}
function fixture(modifyReply = value => value, options = {}) {
  let fills = 0;
  let requests = 0;
  let lastRequest;
  let lastReply;
  let failFill = false;
  let navigationBeforeNative = false;
  let delayed = false;
  const badge = [];
  const title = [];
  const onMessage = event();
  const onDisconnect = event();
  const onUpdated = event();
  const onRemoved = event();
  const inbound = event();
  const port = {
    onMessage, onDisconnect,
    disconnect() { onDisconnect.emit(); },
    postMessage(request) {
      requests += 1;
      lastRequest = request;
      if (!delayed) queueMicrotask(() => {
        lastReply = modifyReply(request.operation === 'save'
        ? { version: 1, origin: request.origin, requestID: request.requestID, operation: 'saved', approved: true }
        : request.operation === 'status' ? { ...request }
        : { ...request, operation: 'filled', approved: true, username: 'synthetic-user', password: 'synthetic-secret' });
        onMessage.emit(lastReply);
      });
    }
  };
  const chrome = {
    tabs: { query: async () => options.noTab ? [] : [{ id: 42, url: 'tabUrl' in options ? options.tabUrl : 'https://example.test/login' }], onUpdated, onRemoved },
    runtime: { id: 'extension-id', getURL: path => `chrome-extension://extension-id/${path}`, onMessage: inbound,
      connectNative: options.connectError ? () => { throw new Error(options.connectError); } : () => port },
    action: { setBadgeText: async args => { badge.push(args); }, setTitle: async args => { title.push(args); } },
    scripting: { executeScript: async parameters => {
      if (parameters.files) return [{ documentId: 'document-1' }];
      assert.deepEqual([...parameters.target.documentIds], ['document-1']);
      const text = parameters.func.toString();
      if (options.missingHelper && (text.includes('.prepare(') || text.includes('.capture(') || text.includes('.fill('))) {
        parameters.func(...(parameters.args ?? []));
      }
      if (text.includes('.capture(')) {
        if (navigationBeforeNative) onUpdated.emit(42, { status: 'loading' });
        return [{ result: { origin: 'https://example.test', username: 'synthetic-user', password: 'synthetic-secret' } }];
      }
      if (text.includes('.prepare(')) {
        if (navigationBeforeNative) onUpdated.emit(42, { status: 'loading' });
        return [{ result: { origin: 'https://example.test' } }];
      }
      if (text.includes('.fill(')) {
        if (failFill) throw new Error('Document disappeared');
        fills += 1; return [{ result: { filled: true } }];
      }
      return [{ result: null }];
    } }
  };
  const context = vm.createContext({ chrome, crypto: webcrypto, URL, TextEncoder, setTimeout, clearTimeout });
  vm.runInContext(source, context);
  return { run: () => context.fillActiveTab(), save: () => context.saveActiveTab(), check: () => context.checkConnection(), state: () => context.currentActionState(), fills: () => fills, requests: () => requests,
    badge: () => badge, title: () => title,
    navigate: () => onUpdated.emit(42, { url: 'https://evil.test' }), close: () => onRemoved.emit(42),
    disconnect: () => port.disconnect(), beforeNative: () => { navigationBeforeNative = true; },
    delay: () => { delayed = true; }, lastRequest: () => lastRequest, lastReply: () => lastReply,
    failFill: () => { failFill = true; }, cancel: () => context.cancelActiveTab(), inbound };
}
test('worker uses a document-bound fill and secret-free request', async () => {
  const setup = fixture();
  assert.equal((await setup.run()).ok, true);
  assert.equal(setup.fills(), 1);
  assert.equal(setup.lastRequest().password, undefined);
  assert.equal(setup.lastRequest().username, undefined);
  assert.equal(setup.lastReply().username, undefined);
  assert.equal(setup.lastReply().password, undefined);
});
test('failed page injection drops received credential references', async () => {
  const setup = fixture(); setup.failFill();
  await assert.rejects(setup.run(), /Document disappeared/);
  assert.equal(setup.lastReply().username, undefined);
  assert.equal(setup.lastReply().password, undefined);
  assert.equal((await setup.state()).state, 'failed');
});
for (const [name, change] of [
  ['different origin', reply => ({ ...reply, origin: 'https://evil.test' })],
  ['different nonce', reply => ({ ...reply, requestID: webcrypto.randomUUID() })],
  ['unapproved result', reply => ({ ...reply, approved: false })],
  ['error result', reply => ({ ...reply, error: 'cancelled' })],
  ['unknown version', reply => ({ ...reply, version: 2 })],
  ['wrong operation', reply => ({ ...reply, operation: 'verify' })],
  ['null response', () => null],
  ['nonstring nonce', reply => ({ ...reply, requestID: 42 })],
  ['empty password', reply => ({ ...reply, password: '' })],
  ['oversized UTF-8 password', reply => ({ ...reply, password: '密'.repeat(5500) })],
  ['oversized UTF-8 username', reply => ({ ...reply, username: '名'.repeat(1400) })]
]) {
  test(`worker denies ${name}`, async () => {
    const setup = fixture(change);
    await assert.rejects(setup.run());
    assert.equal(setup.fills(), 0);
    if (setup.lastReply()) {
      assert.equal(setup.lastReply().password, undefined);
      assert.equal(setup.lastReply().username, undefined);
    }
  });
}
test('navigation during preparation never reaches the vault', async () => {
  const setup = fixture(); setup.beforeNative();
  await assert.rejects(setup.run());
  assert.equal(setup.requests(), 0);
});
for (const action of ['navigate', 'close', 'disconnect']) {
  test(`${action} cancels native approval before filling`, async () => {
    const setup = fixture(); setup.delay();
    const pending = setup.run();
    await new Promise(resolve => setImmediate(resolve));
    setup[action]();
    await assert.rejects(pending);
    assert.equal(setup.fills(), 0);
  });
}
test('a second request cannot replace the first', async () => {
  const setup = fixture(); setup.delay();
  const first = setup.run();
  await new Promise(resolve => setImmediate(resolve));
  await assert.rejects(setup.run());
  assert.equal(setup.requests(), 1);
  setup.disconnect();
  await assert.rejects(first);
});
test('webpage senders cannot request a fill', () => {
  const setup = fixture();
  setup.inbound.emit({ operation: 'fill' }, { id: 'extension-id', tab: { id: 42 }, url: 'https://example.test' }, () => assert.fail('webpage request answered'));
  assert.equal(setup.requests(), 0);
});

for (const operation of ['run', 'save']) test(`popup cancellation disconnects pending ${operation}`, async () => {
  const setup = fixture(); setup.delay();
  const pending = setup[operation]();
  const rejected = assert.rejects(pending);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal((await setup.cancel()).ok, true);
  await rejected;
  assert.equal(setup.fills(), 0);
  assert.equal((await setup.state()).state, 'cancelled');
  assert.equal(setup.requests(), 1);
});
test('cancelling completed request does not pretend to undo it', async () => {
  const setup = fixture(); await setup.run();
  assert.equal((await setup.cancel()).ok, false);
  assert.equal((await setup.state()).state, 'complete');
  assert.equal(setup.fills(), 1);
});
test('webpage cannot cancel native approval', async () => {
  const setup = fixture(); setup.delay();
  const pending = setup.run(); const rejected = assert.rejects(pending);
  await new Promise(resolve => setImmediate(resolve));
  setup.inbound.emit({ operation: 'cancel' }, { id: 'extension-id', tab: { id: 42 }, url: 'https://example.test' }, () => assert.fail('webpage cancellation answered'));
  assert.equal((await setup.state()).state, 'pending');
  setup.disconnect(); await rejected;
});

test('explicit save captures only the bound document and never fills', async () => {
  const setup = fixture();
  assert.equal(setup.requests(), 0);
  assert.equal((await setup.save()).ok, true);
  assert.equal(setup.lastRequest().operation, 'save');
  assert.equal(setup.lastRequest().password, 'synthetic-secret');
  assert.equal(setup.fills(), 0);
});
for (const [name, change] of [
  ['wrong origin', reply => ({ ...reply, origin: 'https://evil.test' })],
  ['wrong nonce', reply => ({ ...reply, requestID: webcrypto.randomUUID() })],
  ['secret in response', reply => ({ ...reply, password: 'unexpected' })],
  ['username in response', reply => ({ ...reply, username: 'unexpected' })],
  ['not approved', reply => ({ ...reply, approved: false })],
  ['wrong operation', reply => ({ ...reply, operation: 'filled' })],
  ['unsupported version', reply => ({ ...reply, version: 2 })],
  ['nonstring nonce', reply => ({ ...reply, requestID: 42 })],
  ['null response', () => null]
]) test(`save rejects ${name}`, async () => {
  const setup = fixture(change);
  await assert.rejects(setup.save(), /Save was not confirmed/);
  if (setup.lastReply()) {
    assert.equal(setup.lastReply().username, undefined);
    assert.equal(setup.lastReply().password, undefined);
  }
});
for (const action of ['navigate', 'close', 'disconnect']) {
  test(`${action} cancels save`, async () => {
    const setup = fixture(); setup.delay();
    const saving = setup.save();
    await new Promise(resolve => setImmediate(resolve));
    setup[action]();
    await assert.rejects(saving);
  });
}
test('navigation during capture sends no secret to native app', async () => {
  const setup = fixture(); setup.beforeNative();
  await assert.rejects(setup.save());
  assert.equal(setup.requests(), 0);
});
test('website cannot request saving credentials', () => {
  const setup = fixture();
  setup.inbound.emit({ operation: 'save' }, { id: 'extension-id', tab: { id: 42 }, url: 'https://example.test' }, () => assert.fail('webpage request answered'));
  assert.equal(setup.requests(), 0);
});
test('connection check contains no page URL or credentials and does not fill', async () => {
  const setup = fixture();
  assert.equal((await setup.check()).ok, true);
  assert.equal(setup.lastRequest().operation, 'status');
  assert.equal(setup.lastRequest().origin, 'https://gaze.invalid');
  assert.equal(setup.lastRequest().password, undefined);
  assert.equal(setup.lastRequest().username, undefined);
  assert.equal(setup.fills(), 0);
});
for (const [name, change] of [
  ['unexpected approval', reply => ({ ...reply, approved: true })],
  ['unexpected credentials', reply => ({ ...reply, password: 'synthetic' })],
  ['different nonce', reply => ({ ...reply, requestID: webcrypto.randomUUID() })],
  ['different origin', reply => ({ ...reply, origin: 'https://other.test' })],
  ['wrong response type', reply => ({ ...reply, operation: 'filled' })],
  ['null response', () => null],
  ['nonstring nonce', reply => ({ ...reply, requestID: 42 })]
]) test(`connection check rejects ${name}`, async () => {
  const setup = fixture(change);
  await assert.rejects(setup.check(), /Connection was not confirmed/);
  if (setup.lastReply()) {
    assert.equal(setup.lastReply().username, undefined);
    assert.equal(setup.lastReply().password, undefined);
  }
});
test('overlapping connection checks are rejected and can retry after cancel', async () => {
  const setup = fixture(); setup.delay();
  const first = setup.check();
  await assert.rejects(setup.check());
  setup.disconnect();
  await assert.rejects(first);
  const next = setup.check();
  setup.disconnect();
  await assert.rejects(next);
  assert.equal(setup.requests(), 2);
});
test('reopened popup can see completed save without credentials or nonce', async () => {
  const setup = fixture();
  await setup.save();
  const result = await setup.state();
  assert.deepEqual(JSON.parse(JSON.stringify(result)), { ok: true, state: 'complete', operation: 'save' });
  setup.navigate();
  assert.equal((await setup.state()).state, 'idle');
});
test('pending approval and cancellation are reflected without exposing fields', async () => {
  const setup = fixture(); setup.delay();
  const pending = setup.run();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal((await setup.state()).state, 'pending');
  setup.disconnect();
  await assert.rejects(pending);
  assert.equal((await setup.state()).state, 'failed');
});
test('starting a request clears a stale success badge and title', async () => {
  const setup = fixture();
  await setup.run();
  setup.failFill();
  await assert.rejects(setup.run());
  assert.equal(setup.badge().at(-1).text, '');
  assert.equal(setup.title().at(-1).title, 'Fill with Gaze Passwords');
});
test('navigation resets the success badge and title', async () => {
  const setup = fixture();
  await setup.run();
  setup.navigate();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(setup.badge().at(-1).text, '');
  assert.equal(setup.title().at(-1).title, 'Fill with Gaze Passwords');
});
test('missing native helper reports setup guidance', async () => {
  const setup = fixture(value => value, { connectError: 'No such native application com.gazeunlock.passwords' });
  await assert.rejects(setup.run(), /browser helper/);
  await assert.rejects(setup.check(), /Connect browser|browser helper/);
  const status = await setup.state();
  assert.equal(status.state, 'failed');
  assert.match(status.error, /browser helper/);
});
test('missing page helper reports a retryable page message', async () => {
  const setup = fixture(value => value, { missingHelper: true });
  await assert.rejects(setup.run(), /page changed/);
  await assert.rejects(setup.save(), /login changed/);
  assert.equal(setup.requests(), 0);
});
test('native error reply surfaces its message without credentials', async () => {
  const setup = fixture(reply => ({ ...reply, operation: 'error', approved: undefined,
    username: undefined, password: undefined, error: 'Approval unavailable or cancelled.' }));
  await assert.rejects(setup.run(), /unavailable or cancelled/);
  assert.equal(setup.fills(), 0);
  assert.equal((await setup.state()).error, 'Approval unavailable or cancelled.');
});
test('duplicate and missing-tab requests have distinct guidance', async () => {
  const setup = fixture(); setup.delay();
  const first = setup.run();
  const rejected = assert.rejects(first);
  await new Promise(resolve => setImmediate(resolve));
  const second = await setup.run().then(() => assert.fail('second request answered'), error => error);
  assert.match(second.message, /already open/);
  assert.doesNotMatch(second.message, /no tab/i);
  setup.disconnect();
  await rejected;
});
test('missing tab asks for a login page', async () => {
  const setup = fixture(value => value, { noTab: true });
  await assert.rejects(setup.run(), /No tab/);
});
test('unreadable tab URL asks for an HTTPS page', async () => {
  const setup = fixture(value => value, { tabUrl: undefined });
  await assert.rejects(setup.run(), /HTTPS login page/);
  assert.equal(setup.requests(), 0);
});
