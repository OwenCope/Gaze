import React from 'react';
import { createRoot } from 'react-dom/client';
import { SettingsPanel } from '@/components/settings-panel';
import { TestersManager } from '@/components/testers-manager';
import { RolesManager } from '@/components/roles-manager';
const roles=[{id:'tester',name:'Tester',color:'#34C759',permissions:['viewPrivate']},{id:'reviewer',name:'Reviewer',color:'#007AFF',permissions:['viewPrivate','publishReleases']}];
const people=[{email:'case@example.test',roles:['tester'],note:'Synthetic fixture',addedAt:'2026-01-01T00:00:00.000Z'}];
window.__admin={calls:[],pending:[],refreshes:0,confirmNext:false,confirmCalls:[],roles,people,
  reply(status,body,raw=false){const p=this.pending.shift();if(!p)throw new Error('No pending request');p.resolve(new Response(raw?body:JSON.stringify(body),{status,headers:{'Content-Type':raw?'text/html':'application/json'}}));},
  fail(){const p=this.pending.shift();if(!p)throw new Error('No pending request');p.reject(new TypeError('Synthetic offline'));}
};
window.fetch=(input,init={})=>{
  const url=String(input);
  if(!/^\/api\/(settings|testers|roles)(\?|$)/.test(url))return Promise.reject(new Error('Fixture blocked unexpected fetch'));
  window.__admin.calls.push({url,method:init.method,body:init.body?JSON.parse(init.body):null});
  return new Promise((resolve,reject)=>window.__admin.pending.push({resolve,reject}));
};
window.confirm=(text)=>{window.__admin.confirmCalls.push(text);return window.__admin.confirmNext;};
createRoot(document.getElementById('root')).render(<React.StrictMode>
  <main className="mx-auto max-w-3xl space-y-8 p-8">
    <h1 className="text-2xl font-semibold">Synthetic admin interaction fixture</h1>
    <section id="settings-fixture"><SettingsPanel initial={{releasesRequireSignIn:false}} /></section>
    <section id="testers-fixture"><TestersManager initial={people} roles={roles} /></section>
    <section id="roles-fixture"><RolesManager initial={roles} /></section>
  </main>
</React.StrictMode>);
