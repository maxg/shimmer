const fs = require('fs');
const jose = require('@panva/jose');

const keystore = new jose.JWKS.KeyStore();

Promise.all([
  keystore.generate('RSA', 2048, { use: 'sig' }),
  keystore.generate('EC', 'P-256', { use: 'sig' }),
  keystore.generate('OKP', 'Ed25519', { use: 'sig' }),
]).then(() => {
  fs.writeFileSync('jwks.json', JSON.stringify(keystore.toJWKS(true), null, 2));
});
