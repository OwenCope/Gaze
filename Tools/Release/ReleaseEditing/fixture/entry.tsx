import React from 'react';
import { createRoot } from 'react-dom/client';
import { ReleaseComposer } from '@fixture/release-composer';
const calls: { url: string; init: RequestInit; body: unknown }[] = [];
const pending: { resolve: (value: Response) => void; reject: (reason: Error) => void }[] = [];
window.__releaseFixture = { calls, pending, uploads: [], navigations: [], refreshes: 0 };
window.fetch = async (url, init) => {
  if (url !== '/api/releases') throw new Error('Unexpected fixture request');
  calls.push({ url: String(url), init: init ?? {}, body: JSON.parse(String(init?.body)) });
  return new Promise((resolve, reject) => pending.push({ resolve, reject }));
};
const root = createRoot(document.getElementById('root')!);
let generation = 0;
function mount() {
  generation++;
  root.render(<ReleaseComposer key={generation} initial={{tag:'1.0',name:'Synthetic release',date:'2026-09-16T00:00:00.000Z',body:'Original synthetic notes',images:[],videos:[],contributors:[],draft:true,prerelease:false}} />);
}
window.__releaseFixture.mount = mount;
window.__releaseFixture.resolve = (status, body) => pending.shift()!.resolve(new Response(JSON.stringify(body), {status,headers:{'Content-Type':'application/json'}}));
window.__releaseFixture.state = () => ({
  calls: calls.map(c=>({url:c.url,method:c.init.method,body:c.body})),
  pending: pending.length,
  tag: document.querySelector<HTMLInputElement>('#tag')?.value,
  disabled: document.querySelector<HTMLInputElement>('#tag')?.matches(':disabled'),
  error: document.querySelector('[role="alert"]')?.textContent,
  navigations: window.__releaseFixture.navigations,
  uploads: window.__releaseFixture.uploads.length,
});
mount();
