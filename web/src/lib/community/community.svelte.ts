import { api } from '$lib/api/client';
import type { components } from '$lib/api/schema';
import { m } from '$lib/paraglide/messages';

export type SocialBody = components['schemas']['SocialBody'];

/**
 * The likes and comments of a route or journey, shared by the parts of its
 * page that show them (the like in the header, the comments below).
 */
export class Community {
	social = $state<SocialBody>();
	busy = $state(false);
	error = $state('');

	constructor(
		readonly kind: 'routes' | 'journeys',
		readonly id: string,
		/** Share token of an unlisted item. */
		readonly token?: string
	) {}

	// Routes and journeys have the same endpoints; the paths differ only in
	// the first segment.
	at<S extends string>(suffix: S) {
		return `/${this.kind}/{id}${suffix}` as `/routes/{id}${S}`;
	}

	params() {
		return { path: { id: this.id }, query: this.token ? { t: this.token } : {} };
	}

	async run(call: Promise<{ data?: SocialBody; response: Response }>) {
		this.busy = true;
		this.error = '';
		const { data, response } = await call;
		this.busy = false;
		if (data) this.social = data;
		else this.error = response.status === 429 ? m.community_rate() : m.error_generic();
		return !!data;
	}

	load() {
		return this.run(api().GET(this.at('/social'), { params: this.params() }));
	}

	like() {
		return this.run(
			this.social?.liked
				? api().DELETE(this.at('/like'), { params: this.params() })
				: api().PUT(this.at('/like'), { params: this.params() })
		);
	}

	toggle(on: boolean) {
		return this.run(
			api().PATCH(this.at('/social'), {
				params: { path: { id: this.id } },
				body: { comments_enabled: on }
			})
		);
	}
}
