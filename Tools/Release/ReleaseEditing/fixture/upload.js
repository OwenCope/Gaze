export function upload(name,file,options){return new Promise((resolve,reject)=>window.__releaseFixture.uploads.push({name,size:file.size,options,resolve,reject}));}
