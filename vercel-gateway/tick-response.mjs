import {gzip} from 'node:zlib';
import {promisify} from 'node:util';

const compress=promisify(gzip);

/** Read-only historical BID tick JSON is especially repetitive and can be
 * several megabytes per request. OkHttp transparently requests/decodes gzip;
 * leave small responses uncompressed to save CPU and latency. */
export async function encodeTickResponse(body,acceptEncoding='') {
  const plain=Buffer.from(JSON.stringify(body),'utf8');
  const headers={'Vary':'Accept-Encoding'};
  const acceptsGzip=String(acceptEncoding).split(',').some(item=>{
    const [name,...parameters]=item.trim().split(';');
    if(name.trim().toLowerCase()!=='gzip')return false;
    const quality=parameters.map(p=>p.trim()).find(p=>p.toLowerCase().startsWith('q='));
    return quality==null || (Number(quality.slice(2))>0 && Number(quality.slice(2))<=1);
  });
  if(!acceptsGzip || plain.length<64*1024)
    return {bytes:plain,headers};
  const zipped=await compress(plain,{level:1});
  return {bytes:zipped,headers:{...headers,'Content-Encoding':'gzip'}};
}
