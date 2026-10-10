import { api } from '#lib/api/client.js';
import type { components } from '#lib/api/schema.js';

export type Photo = components['schemas']['Photo'];
type Photos = components['schemas']['PhotosBody'];

/** Why an upload failed, for the message shown. */
export type UploadProblem = 'format' | 'size' | 'limit' | 'rate' | 'other';

/**
 * The photos of a route or journey, shared by the gallery, the lightbox and
 * the pins on the map. Every change returns the whole list, which replaces
 * the one shown.
 */
export class Gallery {
	photos = $state<Photo[]>([]);
	canEdit = $state(false);
	/** The photo shown large, if any. */
	open = $state<string>();
	busy = $state(false);

	constructor(
		private kind: 'routes' | 'journeys',
		private id: string,
		private token?: string
	) {}

	// Routes and journeys have the same endpoints.
	private at<S extends string>(suffix: S) {
		return `/${this.kind}/{id}${suffix}` as `/routes/{id}${S}`;
	}

	private take(data: Photos | undefined) {
		if (!data) return false;
		this.photos = data.photos;
		this.canEdit = data.can_edit;
		if (this.open && !data.photos.some((p) => p.id === this.open)) this.open = undefined;
		return true;
	}

	/** URL of a photo file; the share token opens unlisted items. */
	src(p: Photo, size: 'large' | 'thumb') {
		return `/api/v1/photos/${p.id}/${size}${this.token ? `?t=${encodeURIComponent(this.token)}` : ''}`;
	}

	async load() {
		const { data } = await api().GET(this.at('/photos'), {
			params: { path: { id: this.id }, query: this.token ? { t: this.token } : {} }
		});
		this.take(data);
	}

	/** Uploads one file; returns why it failed, if it did. */
	async upload(file: File, caption = ''): Promise<UploadProblem | undefined> {
		const { data, response } = await api().POST(this.at('/photos'), {
			params: { path: { id: this.id } },
			body: { file: '', caption },
			bodySerializer: () => {
				const fd = new FormData();
				fd.append('file', file);
				if (caption) fd.append('caption', caption);
				return fd;
			}
		});
		if (this.take(data)) return undefined;
		return (
			({ 413: 'size', 415: 'format', 422: 'limit', 429: 'rate' } as Record<number, UploadProblem>)[
				response.status
			] ?? 'other'
		);
	}

	async update(p: Photo, body: { caption?: string; unpin?: boolean }) {
		const { data } = await api().PATCH(this.at('/photos/{photo}'), {
			params: { path: { id: this.id, photo: p.id } },
			body
		});
		return this.take(data);
	}

	/** Moves a photo by delta places in the gallery. */
	async move(p: Photo, delta: number) {
		const ids = this.photos.map((x) => x.id);
		const i = ids.indexOf(p.id);
		const j = i + delta;
		if (i < 0 || j < 0 || j >= ids.length) return false;
		[ids[i], ids[j]] = [ids[j], ids[i]];
		const { data } = await api().PUT(this.at('/photos/order'), {
			params: { path: { id: this.id } },
			body: { ids }
		});
		return this.take(data);
	}

	async remove(p: Photo) {
		const { data } = await api().DELETE(this.at('/photos/{photo}'), {
			params: { path: { id: this.id, photo: p.id } }
		});
		return this.take(data);
	}

	/** Shows the next (delta 1) or previous (-1) photo large. */
	step(delta: number) {
		const i = this.photos.findIndex((p) => p.id === this.open);
		if (i < 0 || this.photos.length === 0) return;
		this.open = this.photos[(i + delta + this.photos.length) % this.photos.length].id;
	}
}
