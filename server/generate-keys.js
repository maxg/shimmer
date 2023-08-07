import crypto from 'node:crypto';
import fs from 'node:fs/promises';

const keypairs = [
  crypto.generateKeyPairSync('ed25519'),
  crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' }),
  crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }),
];

const keys = keypairs.map(kp => kp.privateKey.export({ format: 'jwk' }));
keys.forEach(jwk => jwk.use = 'sig');

await fs.writeFile('jwks.json', JSON.stringify({ keys }, null, 2));
