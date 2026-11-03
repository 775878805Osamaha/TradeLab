import { createHash, randomBytes, createCipheriv, createDecipheriv, timingSafeEqual } from 'node:crypto';

export const randomToken = () => randomBytes(32).toString('base64url');
export const tokenHash = value => createHash('sha256').update(value).digest('base64url');
export function constantTimeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const left = Buffer.from(a), right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}
export function makeCipher(keyString) {
  const key = Buffer.from(keyString || '', 'base64');
  if (key.length !== 32) throw new Error('TOKEN_ENCRYPTION_KEY must be a random 32-byte base64 key');
  return {
    encrypt(value) {
      const iv = randomBytes(12);
      const cipher = createCipheriv('aes-256-gcm', key, iv);
      const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
      return [iv, cipher.getAuthTag(), encrypted].map(b => b.toString('base64url')).join('.');
    },
    decrypt(packed) {
      const parts = packed.split('.');
      if (parts.length !== 3) throw new Error('Invalid ciphertext');
      const [iv, tag, data] = parts.map(v => Buffer.from(v, 'base64url'));
      const decipher = createDecipheriv('aes-256-gcm', key, iv);
      decipher.setAuthTag(tag);
      return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
    }
  };
}
