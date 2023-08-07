import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import url from 'node:url';
import util from 'node:util';

import ejs from 'ejs';
import express from 'express';
import helmet from 'helmet';
import OidcProvider from 'oidc-provider';
import type { Account } from 'oidc-provider';
interface Client { readonly clientId: string; }

const { shimmer_domain, shimmer_hostname, shimmer_contact } = process.env;

assert(shimmer_domain && shimmer_domain.match(/^\w+(\.\w+)+$/), `invalid shimmer_domain config`);
assert(shimmer_hostname && shimmer_hostname.match(/^\w+(\.\w+)+$/), `invalid shimmer_hostname config`);
assert(shimmer_contact && shimmer_contact.match(/^\w+@\w+(\.\w+)+$/), `invalid shimmer_contact config`);

function encodeAccount(email: string, name: string) {
  assert(email.endsWith(`@${shimmer_domain}`));
  return '0' + Buffer.from([ email, name ].join('\n')).toString('base64');
}

function decodeAccount(sub: string) {
  const [ email, name ] = Buffer.from(sub.substring(1), 'base64').toString().split('\n');
  assert(email && email.endsWith(`@${shimmer_domain}`));
  return { email, name };
}

const clients = await Promise.all((await fs.readdir('../config/clients'))
                  .filter(f => f.endsWith('.json'))
                  .map(f => fs.readFile(`../config/clients/${f}`, { encoding: 'utf-8' }))
                  .map(async json => JSON.parse(await json)));

const claims = { openid: [ 'sub' ], profile: [ 'name' ], email: [ 'email' ] };

const templates = Object.fromEntries(await Promise.all([
  'error',
].map(async f => [ f, ejs.compile(await fs.readFile(`./views/${f}.ejs`, { encoding: 'utf-8' })) ])));

const provider = new OidcProvider(`https://${shimmer_hostname}`, {
  clients,
  async findAccount(ctx, sub, token) {
    const { email, name } = decodeAccount(sub);
    return {
      accountId: sub,
      claims(use, scope, claims, rejected) {
        return { sub, email, name };
      },
    };
  },
  jwks: JSON.parse(await fs.readFile('../config/idp-jwks.json', { encoding: 'utf-8' })),
  features: {
    devInteractions: { enabled: false },
  },
  claims,
  cookies: {
    short: { signed: true, secure: true },
    long: { signed: true, secure: true },
    keys: [ crypto.createHash('sha256').update(JSON.stringify(clients)).digest('hex') ],
  },
  pkce: {
    required(ctx, client) { return false; },
  },
  async renderError(ctx, out, error) {
    logEvent('render_error', ctx.oidc?.account, ctx.oidc?.client, error);
    ctx.type = 'html';
    ctx.body = templates.error({ out });
  },
});
provider.proxy = true;

function logEvent(event: string, accountable?: Account, clientable?: Client, err?: Error) {
  const email = accountable && decodeAccount(accountable.accountId).email;
  const client = clientable && clientable.clientId;
  if (err) {
    const error = util.inspect(Object.assign({}, err), { breakLength: Infinity, compact: Infinity });
    console.error(event, JSON.stringify({ email, client, error }));
  } else {
    console.log(event, JSON.stringify({ email, client }));
  }
}

for (const event of [ 'access_token.saved', 'authorization_code.saved', 'authorization_code.consumed' ]) {
  provider.on(event, (obj) => logEvent(event, obj, obj));
}
for (const event of [ 'authorization.success', 'grant.success' ]) {
  provider.on(event, (ctx) => logEvent(event, ctx.oidc.account, ctx.oidc.client));
}
for (const event of [ 'authorization.error', 'grant.error', 'userinfo.error' ]) {
  provider.on(event, (ctx, err) => logEvent(event, ctx.oidc.account, ctx.oidc.client, err));
}

const app = express();
app.set('view engine', 'ejs');
app.use(helmet());

app.get('/', (req, res, next) => res.render('index'));
app.get('/favicon.ico', (req, res, next) => {
  const dir = path.dirname(url.fileURLToPath(import.meta.url));
  res.sendFile(path.join(dir, 'views/favicon.png'), { maxAge: 1000*60*60*24*7 });
});
app.get('/robots.txt', (req, res, next) => res.end('User-agent: *\nDisallow: /\n'));

app.get('/interaction/:uid', async (req, res, next) => {
  try {
    const { 'x-shibboleth-eppn': email, 'x-shibboleth-displayname': name } = req.headers;
    if (typeof email !== 'string') { throw new Error('Missing asserted ePPN'); }
    if (typeof name !== 'string') { throw new Error('Missing asserted displayName'); }
    if ( ! email.endsWith(`@${shimmer_domain}`)) {
      let err = { error: 'access_denied', error_description: `${shimmer_domain} required` };
      return await provider.interactionFinished(req, res, err);
    }
    const accountId = encodeAccount(email, name);
    const details = await provider.interactionDetails(req, res);
    const clientId = details.params.client_id;
    if (typeof clientId !== 'string') { throw new Error('Missing interaction client ID'); }
    const grant = new provider.Grant({ accountId, clientId });
    grant.addOIDCScope(Object.keys(claims).join(' '));
    const grantId = await grant.save();
    await provider.interactionFinished(req, res, { login: { accountId }, consent: { grantId } });
  } catch (err) { next(err); }
});

app.use(provider.callback());

const server = http.createServer(app);
server.listen(8008, 'localhost', () => console.log({ address: server.address() }));
