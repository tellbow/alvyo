// The App Store pictures from work/raw/ (capture.sh) and the website's map:
// six iPhone screenshots with a headline (1206 × 2622), the product page
// header (21:9, 3840 × 1646) and the search result (3:2, 3840 × 2560), in
// <language>/. The header and search result are PNG: App Store Connect
// refuses a JPEG header, although Apple's specification lists it. Needs the
// web dev server and seed.sh's account.
// Usage: bun app/store/render.mjs [de,en,fr,it]
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const store = dirname(fileURLToPath(import.meta.url));
// The web app's Playwright: imports resolve from this file's folder.
const { chromium } = await import(join(store, '../../web/node_modules/playwright/index.mjs'));
const work = join(store, 'work');
const fonts = join(store, '../assets/fonts');
const web = 'http://localhost:5173';
mkdirSync(join(work, 'web'), { recursive: true });
const langs = (process.argv[2] ?? 'de,en,fr,it').split(',');

// In App Store order: the first three also show in search results.
const shots = [
	['01-route', 'route'],
	['02-nav', 'nav'],
	['03-reach', 'reach'],
	['04-journey', 'journey'],
	['05-weather', 'weather'],
	['06-discover', 'discover']
];

// The headlines, in the order of shots; then the header's and search
// result's title and line below. The orange part in <em>.
const texts = {
	de: {
		shots: [
			'Wanderzeit wie auf dem <em>gelben Wegweiser</em>',
			'Navigation mit Ansagen&nbsp;– <em>auch ohne Netz</em>',
			'Wie weit kommst du in <em>2, 4 oder 8&nbsp;Stunden?</em>',
			'Mehrtägige Touren, <em>Etappe für Etappe</em>',
			'<em>Wetter und Wege</em> für deine Tour',
			'<em>Offizielle Wanderrouten</em> der Schweiz entdecken'
		],
		title: 'Deine nächste<br>Wanderung<br><em>einfach geplant</em>',
		text: 'Offline navigieren, aufzeichnen, teilen'
	},
	en: {
		shots: [
			'Hiking times as on the <em>yellow signposts</em>',
			'Spoken directions&nbsp;– <em>even without a signal</em>',
			'How far do you get in <em>2, 4 or 8&nbsp;hours?</em>',
			'Multi-day hikes, <em>stage by stage</em>',
			'<em>Weather and trails</em> for your hike',
			'Discover Switzerland’s <em>official hiking routes</em>'
		],
		title: 'Your next hike,<br><em>simply planned</em>',
		text: 'Navigate offline, record, share'
	},
	fr: {
		shots: [
			'Temps de marche comme sur les <em>indicateurs jaunes</em>',
			'Navigation vocale&nbsp;– <em>même sans réseau</em>',
			'Jusqu’où vas-tu en <em>2, 4 ou 8&nbsp;heures&nbsp;?</em>',
			'Randonnées de plusieurs jours, <em>étape par étape</em>',
			'<em>Météo et chemins</em> pour ta randonnée',
			'Découvre les <em>itinéraires officiels</em> de Suisse'
		],
		title: 'Ta prochaine<br>randonnée,<br><em>simplement planifiée</em>',
		text: 'Navigation hors ligne, enregistrement, partage'
	},
	it: {
		shots: [
			'Tempi di marcia come sui <em>cartelli gialli</em>',
			'Navigazione vocale&nbsp;– <em>anche senza rete</em>',
			'Fin dove arrivi in <em>2, 4 o 8&nbsp;ore?</em>',
			'Escursioni di più giorni, <em>tappa per tappa</em>',
			'<em>Meteo e sentieri</em> per la tua escursione',
			'Scopri i <em>percorsi ufficiali</em> della Svizzera'
		],
		title: 'La tua prossima<br>escursione,<br><em>pianificata facilmente</em>',
		text: 'Naviga offline, registra, condividi'
	}
};

// Safe areas (in CSS pixels, half the image) from Apple's templates: header
// 1646 × 661, search 2168 × 1030, centred. The rest may be cut off.
const heroes = [
	{ name: 'header', w: 1920, h: 823, safe: { w: 823, h: 331 }, font: 46, phoneH: 400 },
	{ name: 'search', w: 1920, h: 1280, safe: { w: 1084, h: 515 }, font: 60, phoneH: 560 }
];
const heroPhones = ['route', 'nav'];

const fontFaces = `
@font-face { font-family: Bricolage; src: url(file://${fonts}/BricolageGrotesque-Bold.ttf); font-weight: 700; }
@font-face { font-family: Figtree; src: url(file://${fonts}/Figtree-Medium.ttf); font-weight: 500; }`;
const raw = (lang, n) => `file://${work}/raw/${lang}/${n}.png`;

const framed = (img, text) => `<!doctype html><html><head><meta charset="utf-8"><style>${fontFaces}
html, body { margin: 0; width: 1206px; height: 2622px; overflow: hidden; }
body { background: radial-gradient(120% 60% at 50% 0%, #24312A 0%, #14201A 55%, #0E1512 100%); }
h1 { position: absolute; left: 90px; right: 90px; top: 150px; margin: 0; font: 700 104px/1.08 Bricolage, sans-serif;
	letter-spacing: -2px; color: #F2F4EF; text-wrap: balance; }
em { font-style: normal; color: #FFA66B; }
.shot { position: absolute; left: 103px; top: 640px; width: 1000px; border-radius: 64px; overflow: hidden;
	box-shadow: 0 0 0 10px #2E3D35, 0 40px 120px rgba(0,0,0,.45); }
.shot img { display: block; width: 100%; }
</style></head><body><h1>${text}</h1><div class="shot"><img src="${img}"></div></body></html>`;

// The national map, darker in the middle for the text; © swisstopo is a
// condition of its free use, also here.
const hero = (a, lang) => `<!doctype html><html><head><meta charset="utf-8"><style>${fontFaces}
html, body { margin: 0; width: ${a.w}px; height: ${a.h}px; overflow: hidden; background: #0E1512; }
.map { position: absolute; inset: 0; background: url(file://${work}/web/${a.name}.png) center / cover; }
.shade { position: absolute; inset: 0; background: radial-gradient(ellipse ${a.safe.w * 0.95}px ${a.safe.h * 1.25}px at 50% 50%,
	rgba(14,21,18,.94) 0%, rgba(14,21,18,.86) 55%, rgba(14,21,18,.12) 100%); }
.safe { position: absolute; left: ${(a.w - a.safe.w) / 2}px; top: ${(a.h - a.safe.h) / 2}px; width: ${a.safe.w}px;
	height: ${a.safe.h}px; display: flex; align-items: center; gap: ${a.safe.w * 0.04}px; }
.text { flex: 1; min-width: 0; }
h1 { white-space: nowrap; margin: 0; font: 700 ${a.font}px/1.05 Bricolage, sans-serif; letter-spacing: -1px; color: #F2F4EF; }
em { font-style: normal; color: #FFA66B; }
p { white-space: nowrap; margin: ${a.font * 0.35}px 0 0; font: 500 ${a.font * 0.42}px/1.3 Figtree, sans-serif; color: #C9D3CC; }
.phones { display: flex; gap: ${a.phoneH * 0.05}px; align-items: center; }
.phone { height: ${a.phoneH}px; aspect-ratio: 1206 / 2622; border-radius: ${a.phoneH * 0.06}px; overflow: hidden;
	box-shadow: 0 0 0 ${a.phoneH * 0.008}px #2E3D35, 0 ${a.phoneH * 0.04}px ${a.phoneH * 0.12}px rgba(0,0,0,.5); }
.phone img { width: 100%; display: block; }
.credit { position: absolute; right: 14px; bottom: 10px; font: 500 11px Figtree, sans-serif; color: rgba(20,32,26,.8);
	background: rgba(255,255,255,.75); padding: 2px 6px; border-radius: 4px; }
</style></head><body>
<div class="map"></div><div class="shade"></div>
<div class="safe"><div class="text"><h1>${texts[lang].title}</h1><p>${texts[lang].text}</p></div>
<div class="phones">${heroPhones.map((n) => `<div class="phone"><img src="${raw(lang, n)}"></div>`).join('')}</div></div>
<div class="credit">© swisstopo</div>
</body></html>`;

// Renders a page from a file (file:// images and fonts load only so).
async function render(browser, html, w, h, scale, path) {
	const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: scale });
	const file = join(work, 'page.html');
	writeFileSync(file, html);
	await page.goto(`file://${file}`, { waitUntil: 'load' });
	await page.evaluate(() => document.fonts.ready);
	// Longer languages: smaller type until the headline ends above the
	// screenshot, and the header's lines fit beside the phones.
	await page.evaluate(() => {
		const shrink = (el, fits) => {
			while (!fits()) el.style.fontSize = `${parseFloat(getComputedStyle(el).fontSize) * 0.97}px`;
		};
		const shot = document.querySelector('.shot');
		const h1 = document.querySelector('h1');
		if (shot) shrink(h1, () => h1.getBoundingClientRect().bottom <= shot.getBoundingClientRect().top - 50);
		const text = document.querySelector('.text');
		if (text) for (const el of text.children) shrink(el, () => el.scrollWidth <= text.clientWidth);
	});
	await page.screenshot(path.endsWith('.png') ? { path } : { path, type: 'jpeg', quality: 95 });
	await page.close();
}

const browser = await chromium.launch();

// The website's map of the Eiger Trail, without the page around it.
for (const a of heroes) {
	const page = await browser.newPage({ viewport: { width: a.w, height: a.h }, deviceScaleFactor: 2, locale: 'de-CH' });
	await page.goto(`${web}/login`);
	await page.getByLabel(/Benutzername|E-Mail/).first().fill('storeshots');
	await page.getByLabel('Passwort').fill('store-shots-2026');
	await page.getByRole('button', { name: 'Anmelden' }).click();
	await page.waitForURL((u) => !u.pathname.includes('login'));
	const { routes } = await (await page.request.get(`${web}/api/v1/routes`)).json();
	await page.goto(`${web}/routes/${routes.find((r) => r.title === 'Eiger Trail').id}`);
	await page.waitForSelector('.maplibregl-canvas');
	await page.waitForTimeout(3000);
	await page.addStyleTag({
		content: `.maplibregl-map { position: fixed !important; inset: 0 !important; width: 100vw !important;
			height: 100vh !important; z-index: 2147483000; }
		.maplibregl-control-container { display: none !important; }`
	});
	await page.evaluate(() => window.dispatchEvent(new Event('resize')));
	await page.waitForTimeout(10000);
	await page.screenshot({ path: join(work, 'web', `${a.name}.png`) });
	await page.close();
}

for (const lang of langs) {
	const out = join(store, lang);
	mkdirSync(out, { recursive: true });
	for (const [i, [name, shot]] of shots.entries()) {
		await render(browser, framed(raw(lang, shot), texts[lang].shots[i]), 1206, 2622, 1, join(out, `${name}.jpg`));
	}
	for (const a of heroes) {
		await render(browser, hero(a, lang), a.w, a.h, 2, join(out, `${a.name}.png`));
	}
}
await browser.close();
