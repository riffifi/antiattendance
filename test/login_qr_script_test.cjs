const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const script = fs.readFileSync(path.join(__dirname, '../lib/login_qr.dart'), 'utf8')
  .match(/const mireaLoginQrScript = r"""([\s\S]*?)"""/)[1];

function page(fetch) {
  const calls = [];
  const form = {
    action: 'https://sso.mirea.ru/realms/mirea/login-actions/authenticate?execution=test',
    method: 'post',
  };
  const context = {
    URL, URLSearchParams, fetch, window: {},
    location: {origin: 'https://sso.mirea.ru', search: '?tab_id=tab'},
    kcContext: {
      pageId: 'qr-login.ftl', sessionId: 'session', QRauthExecId: 'test',
      QRauthToken: 'https://sso.mirea.ru/realms/mirea/qr-code-auth/scan?qrToken=test',
      url: {loginAction: form.action},
    },
    document: {getElementById: () => form},
    HTMLFormElement: {prototype: {submit() {calls.push(this);}}},
  };
  vm.createContext(context);
  return {context, calls, form, read: () => vm.runInContext(script, context)};
}
const flush = () => new Promise(resolve => setImmediate(resolve));

test('approval completes the university POST even if its own poller stalls', async () => {
  let requests = 0;
  const p = page(async (url, options) => {
    requests++;
    assert.equal(new URL(url).pathname, '/realms/mirea/qr-code-auth/check-status');
    assert.equal(new URL(url).searchParams.get('tabId'), 'tab');
    assert.equal(options.credentials, 'same-origin');
    return {ok: true, json: async () => ({authenticated: true})};
  });
  assert.ok(JSON.parse(p.read()).qr);
  await flush();
  assert.equal(p.calls.length, 1);
  assert.equal(p.calls[0], p.form);
  p.read();
  await flush();
  assert.equal(requests, 1);
  assert.equal(p.calls.length, 1);
});

test('waiting and transient failures retry without submitting login', async () => {
  let requests = 0;
  const p = page(async () => {
    requests++;
    if (requests === 1) throw Error('offline');
    return {ok: true, json: async () => ({authenticated: false, status: 'waiting'})};
  });
  p.read(); await flush();
  assert.ok(JSON.parse(p.read()).qr); await flush();
  assert.equal(requests, 2);
  assert.equal(p.calls.length, 0);
});

test('pending requests cannot overlap', async () => {
  let requests = 0;
  const p = page(() => {requests++; return new Promise(() => {});});
  p.read(); p.read(); p.read();
  assert.equal(requests, 1);
});

test('expired challenges stop showing the QR without submitting', async () => {
  const p = page(async () => ({ok: true,
    json: async () => ({authenticated: false, status: 'timeout'})}));
  p.read(); await flush();
  assert.equal(p.read(), null);
  assert.equal(p.calls.length, 0);
});

test('untrusted origins and submission targets are rejected', async () => {
  const p = page(async () => ({ok: true, json: async () => ({authenticated: true})}));
  p.context.location.origin = 'https://example.com';
  assert.equal(p.read(), null);
  p.context.location.origin = 'https://sso.mirea.ru';
  p.context.kcContext.url.loginAction = 'https://example.com/steal';
  p.read(); await flush();
  assert.equal(p.calls.length, 0);
});


test('approved login creates the official form if the hidden page did not render it', async () => {
  const p = page(async () => ({ok: true, json: async () => ({authenticated: true})}));
  const created = [];
  p.context.document = {
    getElementById: () => null,
    createElement: tag => {
      const element = {tag, style: {}, children: [], appendChild(child) {this.children.push(child);}};
      created.push(element);
      return element;
    },
    body: {appendChild() {}},
  };
  p.read(); await flush();
  assert.equal(p.calls.length, 1);
  const form = p.calls[0];
  assert.equal(form.method, 'post');
  assert.equal(form.action, p.context.kcContext.url.loginAction);
  assert.equal(form.children[0].name, 'authenticationExecution');
  assert.equal(form.children[0].value, 'test');
});
