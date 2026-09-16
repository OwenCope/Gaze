export function useRouter() { return { push(url){window.__releaseFixture.navigations.push(url);},refresh(){window.__releaseFixture.refreshes++;} }; }
