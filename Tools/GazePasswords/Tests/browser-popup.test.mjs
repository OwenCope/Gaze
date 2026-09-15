import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('../BrowserExtension/popup.js', import.meta.url), 'utf8');
function fixture({ url = 'https://example.invalid/login', state = { ok: true, state: 'idle' }, run } = {}) {
  const elements = new Map();
  for (const id of ['fill', 'save', 'cancel', 'site', 'status', 'connection', 'connection-status']) elements.set(`#${id}`, {
    disabled: false, textContent: '', focused: false, handlers: {}, addEventListener(name, handler) { this.handlers[name] = handler; },
    focus() { this.focused = true; }
  });
  const requests = [];
  const scheduled = [];
  const chrome = {
    tabs: { query: async () => [{ id: 1, url }] },
    runtime: { sendMessage: async message => {
      requests.push(message);
      if (message.operation === 'state') return typeof state === 'function' ? await state() : state;
      return run ? await run(message) : { ok: true };
    } }
  };
  vm.runInNewContext(source, { chrome, document: { querySelector: selector => elements.get(selector) }, URL,
    setTimeout: callback => scheduled.push(callback) });
  return { elements, requests, scheduled, click: id => elements.get(`#${id}`).handlers.click(),
    flush: async () => { await new Promise(resolve => setImmediate(resolve)); } };
}

test('initial popup reads only generic state and does not open the vault', async () => {
  const setup = fixture(); await setup.flush();
  assert.deepEqual(setup.requests.map(request => request.operation), ['state']);
  assert.equal(setup.elements.get('#site').textContent, 'example.invalid');
  assert.equal(setup.elements.get('#fill').disabled, false);
});
for (const url of ['http://example.invalid', 'about:blank', 'https://user:synthetic@example.invalid/login']) {
  test(`unsafe page disables save and fill: ${url.split(':')[0]}`, async () => {
    const setup = fixture({ url }); await setup.flush();
    assert.equal(setup.elements.get('#fill').disabled, true);
    assert.equal(setup.elements.get('#save').disabled, true);
    assert.equal(setup.elements.get('#connection').disabled, false);
  });
}
test('reopened pending popup disables both actions and schedules a status refresh', async () => {
  const setup = fixture({ state: { ok: true, state: 'pending', operation: 'save' } }); await setup.flush();
  assert.equal(setup.elements.get('#fill').disabled, true);
  assert.equal(setup.elements.get('#save').disabled, true);
  assert.equal(setup.scheduled.length, 1);
  assert.match(setup.elements.get('#status').textContent, /Waiting/);
});
test('reopened popup reports confirmed save and does not repeat it', async () => {
  const setup = fixture({ state: { ok: true, state: 'complete', operation: 'save' } }); await setup.flush();
  assert.equal(setup.elements.get('#status').textContent, 'Saved in Passwords.');
  assert.equal(setup.requests.length, 1);
});
test('unconfirmed save result tells user to check vault rather than declaring nothing saved', async () => {
  const setup = fixture({ state: { ok: true, state: 'failed', operation: 'save' } }); await setup.flush();
  assert.match(setup.elements.get('#status').textContent, /Check Passwords/);
});
test('late idle response cannot enable buttons during newly started approval', async () => {
  let finishState;
  let finishFill;
  const setup = fixture({ state: () => new Promise(resolve => { finishState = resolve; }),
    run: () => new Promise(resolve => { finishFill = resolve; }) });
  await setup.flush();
  const action = setup.click('fill');
  finishState({ ok: true, state: 'idle' });
  await setup.flush();
  assert.equal(setup.elements.get('#fill').disabled, true);
  finishFill({ ok: true });
  await action;
  assert.equal(setup.elements.get('#fill').disabled, false);
  assert.match(setup.elements.get('#status').textContent, /^Filled/);
});
test('connection check sends no page address or fields', async () => {
  const setup = fixture(); await setup.flush();
  await setup.click('connection');
  assert.deepEqual(JSON.parse(JSON.stringify(setup.requests.at(-1))), { operation: 'status' });
  assert.match(setup.elements.get('#connection-status').textContent, /No credentials accessed/);
  assert.equal(setup.elements.get('#connection').disabled, false);
});
test('malformed fill response recovers without leaving buttons disabled', async () => {
  const setup = fixture({ run: async () => null }); await setup.flush();
  await setup.click('fill');
  assert.match(setup.elements.get('#status').textContent, /request closed/);
  assert.equal(setup.elements.get('#fill').disabled, false);
});
test('connection check preserves the previous action result', async () => {
  const setup = fixture({ state: { ok: true, state: 'complete', operation: 'save' } }); await setup.flush();
  await setup.click('connection');
  assert.equal(setup.elements.get('#status').textContent, 'Saved in Passwords.');
  assert.match(setup.elements.get('#connection-status').textContent, /Connected/);
});
test('connection check cannot interrupt pending approval', async () => {
  const setup = fixture({ state: { ok: true, state: 'pending', operation: 'fill' } }); await setup.flush();
  assert.equal(setup.elements.get('#connection').disabled, true);
  await setup.click('connection');
  assert.equal(setup.requests.length, 1);
  assert.match(setup.elements.get('#status').textContent, /Waiting/);
});
test('actions wait for the connection check to finish', async () => {
  let finish;
  const setup = fixture({ run: () => new Promise(resolve => { finish = resolve; }) }); await setup.flush();
  const checking = setup.click('connection');
  await setup.flush();
  assert.equal(setup.elements.get('#fill').disabled, true);
  assert.equal(setup.elements.get('#save').disabled, true);
  await setup.click('save');
  assert.deepEqual(setup.requests.map(request => request.operation), ['state', 'status']);
  finish({ ok: true }); await checking;
  assert.equal(setup.elements.get('#fill').disabled, false);
  assert.equal(setup.elements.get('#connection').disabled, false);
});

test('pending popup can cancel without sending a website or credentials', async () => {
  const setup = fixture({ state: { ok: true, state: 'pending', operation: 'fill' } }); await setup.flush();
  assert.equal(setup.elements.get('#cancel').hidden, false);
  await setup.click('cancel');
  assert.deepEqual(JSON.parse(JSON.stringify(setup.requests.at(-1))), { operation: 'cancel' });
  assert.equal(setup.elements.get('#cancel').hidden, true);
  assert.equal(setup.elements.get('#fill').disabled, false);
  assert.match(setup.elements.get('#status').textContent, /already saved or filled is unchanged/);
});
test('late fill completion cannot overwrite cancellation feedback', async () => {
  let finish;
  const setup = fixture({ run: message => message.operation === 'fill' ? new Promise(resolve => { finish = resolve; }) : { ok: true } });
  await setup.flush();
  const filling = setup.click('fill');
  await setup.flush();
  await setup.click('cancel');
  finish({ ok: true }); await filling;
  assert.match(setup.elements.get('#status').textContent, /^Request cancelled/);
  assert.equal(setup.elements.get('#fill').disabled, false);
});
test('cancelled popup restores honest result without repeating actions', async () => {
  const setup = fixture({ state: { ok: true, state: 'cancelled', operation: 'save' } }); await setup.flush();
  assert.match(setup.elements.get('#status').textContent, /already saved or filled is unchanged/);
  assert.equal(setup.elements.get('#cancel').hidden, true);
  assert.equal(setup.requests.length, 1);
});
test('pending then idle reports the request closed', async () => {
  const states = [{ ok: true, state: 'pending', operation: 'fill' }, { ok: true, state: 'idle' }];
  let calls = 0;
  const setup = fixture({ state: () => states[Math.min(calls++, states.length - 1)] });
  await setup.flush();
  assert.match(setup.elements.get('#status').textContent, /Waiting/);
  await setup.scheduled[0]();
  await setup.flush();
  assert.match(setup.elements.get('#status').textContent, /request closed/);
  assert.equal(setup.elements.get('#fill').disabled, false);
  assert.equal(setup.elements.get('#cancel').hidden, true);
});
test('unanswered state poll keeps waiting instead of wedging', async () => {
  const states = [{ ok: true, state: 'pending', operation: 'fill' }, { ok: false }, { ok: true, state: 'pending', operation: 'fill' }];
  let calls = 0;
  const setup = fixture({ state: () => states[Math.min(calls++, states.length - 1)] });
  await setup.flush();
  await setup.scheduled[0]();
  await setup.flush();
  assert.equal(setup.scheduled.length, 2);
  await setup.scheduled[1]();
  await setup.flush();
  assert.match(setup.elements.get('#status').textContent, /Waiting/);
  assert.equal(setup.elements.get('#fill').disabled, true);
  assert.equal(setup.requests.length, 3);
});
test('reopened failure repeats the underlying message', async () => {
  const setup = fixture({ state: { ok: true, state: 'failed', operation: 'fill', error: 'Approval unavailable or cancelled.' } });
  await setup.flush();
  assert.equal(setup.elements.get('#status').textContent, 'Approval unavailable or cancelled.');
});
test('focus follows the actionable control', async () => {
  const setup = fixture(); await setup.flush();
  const filling = setup.click('fill');
  await setup.flush();
  assert.equal(setup.elements.get('#cancel').focused, true);
  await filling;
  assert.equal(setup.elements.get('#fill').focused, true);
  assert.match(setup.elements.get('#status').textContent, /^Filled/);
  await setup.click('connection');
  assert.equal(setup.elements.get('#connection').focused, true);
});
