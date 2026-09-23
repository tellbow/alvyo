// A minimal OpenID Connect provider for end-to-end tests: its login page is
// a form where the test types who signs in. Started by playwright.config.ts.
import { createHash, generateKeyPairSync, randomBytes, sign } from 'node:crypto';
import { createServer } from 'node:http';

const PORT = 18090;
const ISSUER = `http://localhost:${PORT}`;
const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'k1', alg: 'RS256', use: 'sig' };
const codes = new Map();

const b64 = (b) => Buffer.from(b).toString('base64url');
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => `&#${c.charCodeAt(0)};`);

function jwt(claims) {
	const input = `${b64(JSON.stringify({ alg: 'RS256', kid: 'k1', typ: 'JWT' }))}.${b64(JSON.stringify(claims))}`;
	return `${input}.${b64(sign('sha256', Buffer.from(input), privateKey))}`;
}

async function body(req) {
	let s = '';
	for await (const chunk of req) s += chunk;
	return new URLSearchParams(s);
}

createServer(async (req, res) => {
	const url = new URL(req.url, ISSUER);
	const json = (v, status = 200) => {
		res.writeHead(status, { 'content-type': 'application/json' });
		res.end(JSON.stringify(v));
	};
	if (url.pathname === '/.well-known/openid-configuration') {
		return json({
			issuer: ISSUER,
			authorization_endpoint: `${ISSUER}/authorize`,
			token_endpoint: `${ISSUER}/token`,
			jwks_uri: `${ISSUER}/jwks`,
			id_token_signing_alg_values_supported: ['RS256']
		});
	}
	if (url.pathname === '/jwks') return json({ keys: [jwk] });
	if (url.pathname === '/authorize' && req.method === 'GET') {
		const hidden = [...url.searchParams]
			.map(([k, v]) => `<input type="hidden" name="${esc(k)}" value="${esc(v)}">`)
			.join('');
		res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
		return res.end(`<!doctype html><title>Test-ID</title><form method="post">${hidden}
			<label>E-Mail <input name="email"></label>
			<label>Name <input name="name"></label>
			<button>Anmelden bei Test-ID</button></form>`);
	}
	if (url.pathname === '/authorize' && req.method === 'POST') {
		const f = await body(req);
		const code = b64(randomBytes(16));
		codes.set(code, {
			challenge: f.get('code_challenge'),
			claims: {
				iss: ISSUER,
				aud: f.get('client_id'),
				sub: `sub-${f.get('email')}`,
				email: f.get('email'),
				email_verified: true,
				name: f.get('name'),
				nonce: f.get('nonce'),
				iat: Math.floor(Date.now() / 1000),
				exp: Math.floor(Date.now() / 1000) + 600
			}
		});
		const back = new URL(f.get('redirect_uri'));
		back.searchParams.set('code', code);
		back.searchParams.set('state', f.get('state'));
		res.writeHead(302, { location: back.toString() });
		return res.end();
	}
	if (url.pathname === '/token' && req.method === 'POST') {
		const f = await body(req);
		const grant = codes.get(f.get('code'));
		codes.delete(f.get('code'));
		const challenge = createHash('sha256')
			.update(f.get('code_verifier') ?? '')
			.digest('base64url');
		if (!grant || grant.challenge !== challenge) return json({ error: 'invalid_grant' }, 400);
		return json({ access_token: 'at', token_type: 'Bearer', id_token: jwt(grant.claims) });
	}
	res.writeHead(404);
	res.end();
}).listen(PORT, () => console.log(`fake IdP on ${ISSUER}`));
