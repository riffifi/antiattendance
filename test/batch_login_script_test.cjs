const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../lib/batch_login_page.dart'), 'utf8');
const extract = name => source.match(new RegExp(`const ${name} = r'''([\\s\\S]*?)'''`))[1];
const hold = extract('_holdApprovalScript'), poll = extract('_batchPollScript');
const flush = () => new Promise(resolve => setImmediate(resolve));
function page(result) {
  const nodes = [], forms = [];
  const context = {
    URL, URLSearchParams, Response, AbortSignal,
    location: {origin:'https://sso.mirea.ru',href:'https://sso.mirea.ru/realms/mirea/login-actions/authenticate?tab_id=tab',search:'?tab_id=tab'},
    kcContext: {pageId:'qr-login.ftl',sessionId:'session',QRauthExecId:'execution',QRauthToken:'https://sso.mirea.ru/realms/mirea/qr-code-auth/scan?qrToken=test',url:{loginAction:'https://sso.mirea.ru/realms/mirea/login-actions/authenticate?execution=test'}},
    document: {
      documentElement:{lang:'en'},getElementById:id=>nodes.find(node=>node.id===id),
      createElement:tag=>{const node={tag,style:{},children:[],append(...children){this.children.push(...children);}};nodes.push(node);return node;},
      body:{prepend:form=>forms.push(form)},
    },
    fetch:async()=>new Response(JSON.stringify(result),{headers:{'content-type':'application/json'}}),
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(hold,context);
  return {context,nodes,forms,read:()=>vm.runInContext(poll,context),poll:()=>JSON.parse(vm.runInContext(poll,context))};
}

test('approval turns preview green but leaves completion to a real form button',async()=>{
  const p=page({authenticated:true});
  // Even the university's own poller must not receive the auto-submit signal.
  const native=await p.context.fetch('https://sso.mirea.ru/realms/mirea/qr-code-auth/check-status?sessionId=session');
  assert.equal((await native.json()).authenticated,false);
  const state=await p.poll();assert.equal(state.approved,true);
  assert.equal(p.forms.length,1);assert.equal(p.forms[0].method,'post');
  assert.equal(p.forms[0].children[1].type,'submit');
  assert.equal(p.forms[0].children[1].textContent,'Continue');
  assert.equal(p.forms[0].children[0].name,'authenticationExecution');
  await p.poll();assert.equal(p.forms.length,1);
  assert.ok(!poll.includes('.submit(')); // Approval itself never submits.
});

test('waiting and rejected challenges do not offer Continue',async()=>{
  for(const status of ['waiting','rejected','timeout']){
    const p=page({authenticated:false,status});p.poll();await flush();const state=p.poll();
    assert.equal(state.approved,false);assert.equal(state.status,status);assert.equal(p.forms.length,0);
  }
});

test('different browser contexts cannot share approval state',async()=>{
  const first=page({authenticated:true}),second=page({authenticated:false,status:'waiting'});
  first.poll();await flush();
  assert.equal(first.poll().approved,true);
  assert.equal((await second.poll()).approved,false);
  assert.equal(second.forms.length,0);
});

test('untrusted submission destinations and foreign pages are ignored',async()=>{
  const p=page({authenticated:true});p.context.kcContext.url.loginAction='https://other.example/steal';
  p.poll();await flush();p.poll();assert.equal(p.forms.length,0);
  p.context.location.origin='https://other.example';
  assert.equal(await p.poll(),null);
});

// Android evaluateJavascript serializes the immediate value, not Promise results.
test('QR is returned synchronously even while approval HTTP request is stalled',()=>{
  const p=page({authenticated:false,status:'waiting'});let calls=0;
  p.context.__aaBatchFetch=()=>{calls++;return new Promise(()=>{});};
  const raw=p.read();assert.equal(typeof raw,'string');
  assert.ok(JSON.parse(raw).qr.includes('qrToken='));
  assert.equal(JSON.parse(raw).approved,false);
  p.read();assert.equal(calls,1);assert.equal(p.forms.length,0);
});

test('offline approval polling retries without hiding the QR',async()=>{
  const p=page({authenticated:true});let calls=0;
  const original=p.context.__aaBatchFetch;
  p.context.__aaBatchFetch=(...args)=>{calls++;return calls===1?Promise.reject(Error('offline')):original(...args);};
  assert.ok(p.poll().qr);await flush();
  assert.ok(p.poll().qr);await flush();
  assert.equal(p.poll().approved,true);assert.equal(calls,2);
});
