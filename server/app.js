const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const path = require('path');
const util = require('util');

const ejs = require('ejs');
const express = require('express');
const helmet = require('helmet');

const OidcProvider = require('oidc-provider');

const { shimmer_domain, shimmer_hostname, shimmer_contact } = process.env;

assert(shimmer_domain.match(/^\w+(\.\w+)+$/));
assert(shimmer_hostname.match(/^\w+(\.\w+)+$/));
assert(shimmer_contact.match(/^\w+@\w+(\.\w+)+$/));

function encodeAccount(email, name) {
  assert(email.endsWith(`@${shimmer_domain}`));
  return '0' + Buffer.from([ email, name ].join('\n')).toString('base64');
}

function decodeAccount(sub) {
  let [ email, name ] = Buffer.from(sub.substr(1), 'base64').toString().split('\n');
  assert(email.endsWith(`@${shimmer_domain}`));
  return { email, name };
}

const clients = fs.readdirSync('../config/idp-clients')
                  .filter(f => f.endsWith('.json'))
                  .map(f => require(`../config/idp-clients/${f}`));

const templates = Object.fromEntries([
  'error',
].map(f => [ f, ejs.compile(fs.readFileSync(`./views/${f}.ejs`, { encoding: 'utf-8' })) ]));

const provider = new OidcProvider(`https://${shimmer_hostname}`, {
  clients,
  async findAccount(ctx, sub, token) {
    let { email, name } = decodeAccount(sub);
    return {
      accountId: sub,
      claims(use, scope, claims, rejected) {
        return { sub, email, name };
      },
    };
  },
  jwks: require('../config/idp-jwks.json'),
  features: {
    devInteractions: { enabled: false },
  },
  claims: { openid: [ 'sub' ], profile: [ 'name' ], email: [ 'email' ] },
  cookies: {
    short: { signed: true, secure: true, },
    long: { signed: true, secure: true, },
    keys: [ crypto.createHash('sha256').update(JSON.stringify(clients)).digest('hex') ],
  },
  async renderError(ctx, out, error) {
    logEvent('render_error', ctx.oidc && ctx.oidc.account, ctx.oidc && ctx.oidc.client, error);
    ctx.type = 'html';
    ctx.body = templates.error({ out });
  },
});
provider.proxy = true;

function logEvent(event, accountable, clientable, err) {
  let email = accountable && decodeAccount(accountable.accountId).email;
  let client = clientable && clientable.clientId;
  if (err) {
    let error = util.inspect(Object.assign({}, err), { breakLength: Infinity, compact: Infinity });
    console.error(event, JSON.stringify({ email, client, error }));
  } else {
    console.log(event, JSON.stringify({ email, client }));
  }
}

for (let event of [ 'access_token.saved', 'authorization_code.saved', 'authorization_code.consumed' ]) {
  provider.on(event, (obj) => logEvent(event, obj, obj));
}
for (let event of [ 'authorization.success', 'grant.success' ]) {
  provider.on(event, (ctx) => logEvent(event, ctx.oidc.account, ctx.oidc.client));
}
for (let event of [ 'authorization.error', 'grant.error', 'userinfo.error' ]) {
  provider.on(event, (ctx, err) => logEvent(event, ctx.oidc.account, ctx.oidc.client, err));
}

const app = express();
app.set('view engine', 'ejs');
app.use(helmet());

app.get('/', (req, res, next) => res.render('index'));
app.get('/favicon.ico', (req, res, next) => {
  res.sendFile(path.join(__dirname, 'views/favicon.png'), { maxAge: 1000*60*60*24*7 });
});
app.get('/robots.txt', (req, res, next) => res.end('User-agent: *\nDisallow: /\n'));

app.get('/interaction/:uid', async (req, res, next) => {
  try {
    let { 'x-shibboleth-eppn': email, 'x-shibboleth-displayname': name } = req.headers;
    if ( ! email.endsWith(`@${shimmer_domain}`)) {
      let err = { error: 'access_denied', error_description: `${shimmer_domain} required` };
      return await provider.interactionFinished(req, res, err);
    }
    let account = encodeAccount(email, name);
    await provider.interactionFinished(req, res, { login: { account }, consent: { } });
  } catch (err) { next(err); }
});

app.use(provider.callback);

const server = http.createServer(app);
server.listen(8008, 'localhost', () => console.log({ address: server.address() }));
