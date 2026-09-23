const MAILPIT = process.env.MAILPIT_URL ?? 'http://localhost:8025';

/** Waits for the newest e-mail to `to` whose text matches `pattern`; returns the match. */
export async function mailMatching(to: string, pattern: RegExp): Promise<RegExpMatchArray> {
	for (let attempt = 0; attempt < 20; attempt++) {
		const res = await fetch(`${MAILPIT}/api/v1/search?query=${encodeURIComponent(`to:"${to}"`)}`);
		const { messages } = (await res.json()) as { messages: { ID: string }[] };
		if (messages.length > 0) {
			const msg = (await (await fetch(`${MAILPIT}/api/v1/message/${messages[0].ID}`)).json()) as {
				Text: string;
			};
			const match = msg.Text.match(pattern);
			if (match) return match;
		}
		await new Promise((r) => setTimeout(r, 250));
	}
	throw new Error(`no mail matching ${pattern} for ${to}`);
}

/** Waits for the newest e-mail to `to` and returns its first odysgeh link with a token. */
export async function linkFromMail(to: string, path: string): Promise<string> {
	return (await mailMatching(to, new RegExp(`https?://\\S+${path}\\?token=[\\w-]+`)))[0];
}
