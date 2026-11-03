import { randomBytes, createHash, createCipheriv, createDecipheriv, timingSafeEqual } from 'node:crypto';

export const randomToken = () => randomBytes(32).toString('base64url');
export const hash = value => createHash('sha256').update(value).digest('base64url');
export function constantTimeMatch(left,right) {
  if(typeof left!=='string'||typeof right!=='string')return false;
  const a=Buffer.from(left),b=Buffer.from(right);
  return a.length===b.length && timingSafeEqual(a,b);
}
export function sealedCodec(base64Key) {
  const key=Buffer.from(base64Key||'','base64');
  if(key.length!==32)throw new Error('SESSION_ENCRYPTION_KEY must decode to exactly 32 bytes');
  return {
    seal(data) {
      const iv=randomBytes(12);
      const cipher=createCipheriv('aes-256-gcm',key,iv);
      const ciphertext=Buffer.concat([cipher.update(JSON.stringify(data)),cipher.final()]);
      return [iv,cipher.getAuthTag(),ciphertext].map(buf=>buf.toString('base64url')).join('.');
    },
    open(serialized) {
      if(typeof serialized!=='string'||serialized.length>6144)throw new Error('Invalid sealed credential');
      const parts=serialized.split('.');
      if(parts.length!==3)throw new Error('Invalid sealed credential');
      const [iv,tag,ciphertext]=parts.map(v=>Buffer.from(v,'base64url'));
      if(iv.length!==12||tag.length!==16)throw new Error('Invalid sealed credential');
      const decipher=createDecipheriv('aes-256-gcm',key,iv);
      decipher.setAuthTag(tag);
      const json=Buffer.concat([decipher.update(ciphertext),decipher.final()]).toString('utf8');
      return JSON.parse(json);
    },
  };
}
