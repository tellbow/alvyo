<script lang="ts">
	import { focused } from '#lib/util/focus.js';
	import OpenInApp from '#lib/sharing/OpenInApp.svelte';
	import type { Map as MapLibreMap } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api, type Collection, type CollectionItem, type Me } from '#lib/api/client.js';
	import { stageColor } from '#lib/journeys/colors.js';
	import LayerSwitcher from '#lib/map/LayerSwitcher.svelte';
	import Map from '#lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '#lib/map/styles.js';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';
	import { sacBackground, sacInk } from '#lib/planner/colors.js';
	import { formatDistance, formatDuration, formatHeight, formatSAC } from '#lib/planner/route.js';
	import SharePanel from '#lib/sharing/SharePanel.svelte';
	import TagChips from '#lib/tags/TagChips.svelte';
	import TagInput from '#lib/tags/TagInput.svelte';
	import AddItems from './AddItems.svelte';
	import CollectionLayers from './CollectionLayers.svelte';
	import { choose } from '#lib/util/choose.js';
	import DoneButton from '#lib/done/DoneButton.svelte';

	let { collection: initial, user }: { collection: Collection; user: Me | null } = $props();

	// The API returns the whole collection after every change; it replaces this.
	// svelte-ignore state_referenced_locally
	let collection = $state(initial);
	const canEdit = $derived(collection.can_edit);
	const isOwner = $derived(collection.role === 'owner');
	const pace = $derived(user?.speed_factor ?? 1);

	let base = $state<BaseMapId>('landeskarte');
	let overlays = $state<OverlayId[]>(['wanderwege']);
	let map = $state<MapLibreMap>();
	let highlight = $state<string>();
	let confirming = $state(false);
	let removing = $state<string>(); // the item asked about before removing
	let error = $state('');

	const shareUrl = $derived(
		isOwner && collection.share_token
			? `${page.url.origin}/collections/${collection.id}?t=${collection.share_token}`
			: ''
	);

	function onready(mp: MapLibreMap, l: typeof MapLibre) {
		map = mp;
		const pts = collection.item_list.flatMap((it) => it.lines.flat());
		if (pts.length === 0) return;
		const b = pts.reduce(
			(acc, c) => acc.extend([c[0], c[1]]),
			new l.LngLatBounds([pts[0][0], pts[0][1]], [pts[0][0], pts[0][1]])
		);
		mp.fitBounds(b, { padding: 60, duration: 0, maxZoom: 14 });
	}

	// Changes are sent one after another, like on the journey page.
	let queue: Promise<unknown> = Promise.resolve();
	function mutate(call: () => Promise<{ data?: Collection; response: Response }>) {
		const run = queue.then(async () => {
			error = '';
			const { data } = await call();
			if (data) collection = data;
			else error = m.error_generic();
			return data;
		});
		queue = run.catch(() => {});
		return run;
	}

	const id = () => ({ id: collection.id });
	const ifMatch = () => ({ 'If-Match': `"${collection.version}"` });

	function patch(body: {
		title?: string;
		description?: string;
		visibility?: 'private' | 'unlisted' | 'public';
		tags?: string[];
	}) {
		return mutate(() =>
			api().PATCH('/collections/{id}', { params: { path: id(), header: ifMatch() }, body })
		);
	}

	function patchItem(it: CollectionItem, body: { note?: string; position?: number }) {
		return mutate(() =>
			api().PATCH('/collections/{id}/items/{item}', {
				params: { path: { ...id(), item: it.id } },
				body
			})
		);
	}

	function addItem(c: { kind: 'route' | 'journey'; id: string }) {
		return mutate(() =>
			api().POST('/collections/{id}/items', {
				params: { path: id() },
				body: c.kind === 'route' ? { route_id: c.id } : { journey_id: c.id }
			})
		);
	}

	function removeItem(it: CollectionItem) {
		return mutate(() =>
			api().DELETE('/collections/{id}/items/{item}', {
				params: { path: { ...id(), item: it.id } }
			})
		);
	}

	async function remove() {
		const { response } = await api().DELETE('/collections/{id}', { params: { path: id() } });
		if (response.ok) await goto(resolve('/collections'));
	}

	// Who sees the collection without an invitation opens its items through
	// it: `c.{id}`, with the link's token when it is unlisted.
	const pass = $derived.by(() => {
		if (collection.visibility === 'private' || collection.role !== 'viewer') return '';
		const t = page.url.searchParams.get('t');
		return `?t=${encodeURIComponent(`c.${collection.id}${t ? `.${t}` : ''}`)}`;
	});

	function href(it: CollectionItem) {
		return it.kind === 'route'
			? resolve('/routes/[id]', { id: it.target_id })
			: resolve('/journeys/[id]', { id: it.target_id });
	}
</script>

<Seo
	title={collection.title}
	description={`${m.seo_collection_description({ owner: collection.owner_username, n: collection.item_list.length })} ${collection.description ?? ''}`}
	image={collection.item_list.some((i) => i.lines.length)
		? `${page.url.origin}/api/v1/collections/${collection.id}/og.png?v=${collection.version}${page.url.searchParams.has('t') ? `&t=${page.url.searchParams.get('t')}` : ''}`
		: undefined}
	index={collection.visibility === 'public'}
/>

<main class="flex min-h-0 flex-1 flex-col md:flex-row">
	<section class="relative h-[50dvh] shrink-0 md:h-auto md:flex-1 md:shrink">
		<Map bind:base bind:overlays {onready} />
		<LayerSwitcher bind:base bind:overlays />
		{#if map}
			<CollectionLayers {map} items={collection.item_list} {highlight} />
		{/if}
	</section>

	<aside
		class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto border-t border-stone-200 bg-surface p-4 md:w-96 md:flex-none md:border-t-0 md:border-l"
		data-testid="collection-panel"
	>
		<div>
			{#if canEdit}
				<input
					class="w-full rounded border border-transparent px-1 text-xl font-semibold hover:border-stone-400"
					value={collection.title}
					maxlength="120"
					aria-label={m.field_title()}
					data-testid="collection-title"
					onchange={(e) => patch({ title: e.currentTarget.value })}
				/>
			{:else}
				<h1 class="text-xl font-semibold" data-testid="collection-title">{collection.title}</h1>
				<OpenInApp kind="collections" id={collection.id} />
			{/if}
			<p class="text-sm text-stone-500">
				{collection.role === 'editor'
					? m.shared_editor_note({ user: collection.owner_username })
					: m.route_by({ user: collection.owner_username })}
			</p>
			{#if canEdit}
				<textarea
					class="mt-2 w-full rounded-md border border-stone-400 px-2 py-1 text-sm"
					rows="2"
					value={collection.description}
					placeholder={m.collection_description_placeholder()}
					aria-label={m.collection_description_placeholder()}
					onchange={(e) => patch({ description: e.currentTarget.value })}></textarea>
			{:else if collection.description}
				<p class="mt-2 text-sm whitespace-pre-line">{collection.description}</p>
			{/if}
			<div class="mt-2">
				{#if canEdit}
					<TagInput tags={collection.tags} onchange={(tags) => patch({ tags })} />
				{:else}
					<TagChips tags={collection.tags} />
				{/if}
			</div>
		</div>

		{#if error}<p role="alert" class="text-sm text-red-700 dark:text-red-400">{error}</p>{/if}

		{#if canEdit}
			<AddItems
				taken={new Set(collection.item_list.map((it) => `${it.kind}:${it.target_id}`))}
				onadd={addItem}
			/>
		{/if}

		{#if collection.hidden > 0}
			<p class="text-sm text-stone-600" data-testid="collection-hidden">
				{m.collection_hidden({ n: collection.hidden })}
			</p>
		{/if}
		{#if collection.item_list.length === 0}
			{#if collection.hidden === 0}
				<p class="text-sm text-stone-600">{m.collection_empty()}</p>
			{/if}
		{:else}
			{#if user}
				<p class="text-sm text-stone-600" data-testid="collection-done">
					{m.collection_done({
						done: collection.item_list.filter((it) => it.done_on).length,
						n: collection.item_list.length
					})}
				</p>
			{/if}
			<ol class="flex flex-col gap-2" data-testid="collection-items">
				{#each collection.item_list as it, i (it.id)}
					<li
						class="rounded-md border border-stone-200 p-2 text-sm"
						data-testid="collection-item"
						onmouseenter={() => (highlight = it.id)}
						onmouseleave={() => (highlight = undefined)}
					>
						<div class="flex items-center gap-2">
							<span class="inline-block size-3 rounded-full" style:background={stageColor(i)}
							></span>
							<a href="{href(it)}{pass}" class="flex-1 font-medium hover:underline">{it.title}</a>
							<span class="text-xs text-stone-500"
								>{it.kind === 'route'
									? m.collection_kind_route()
									: m.collection_kind_journey()}</span
							>
						</div>
						<div class="mt-1 flex items-center gap-2 text-xs text-stone-600 tabular-nums">
							<span>{m.shared_by({ user: it.owner_username })}</span>
							{#if it.distance_m > 0}
								<span class="ml-auto"
									>{formatDistance(it.distance_m)} · {formatDuration(it.duration_s, pace)} · ↑&nbsp;{formatHeight(
										it.ascent_m
									)}</span
								>
							{/if}
							{#if it.sac_grade > 0}
								<span
									class="rounded px-1 font-semibold"
									style:background={sacBackground(it.sac_grade)}
									style:color={sacInk(it.sac_grade)}>{formatSAC(it.sac_grade, it.sac_max)}</span
								>
							{/if}
						</div>
						{#if it.kind === 'journey' || user}
							<div class="mt-1 flex items-center gap-2 text-xs text-stone-500">
								{#if it.kind === 'journey'}<span>{m.collection_stages({ n: it.stages })}</span>{/if}
								{#if user}
									<!-- Hiked without opening each one (feedback issue 59). -->
									<span class="ml-auto">
										<DoneButton
											kind={it.kind === 'route' ? 'routes' : 'journeys'}
											id={it.target_id}
											doneOn={it.done_on}
											marked={it.done_marked}
											by={it.kind === 'route' ? 'hike' : 'stages'}
											testid="done-{i}"
											onchange={(on) => (it.done_on = on)}
										/>
									</span>
								{/if}
							</div>
						{/if}
						{#if canEdit}
							<div class="mt-2 flex items-center gap-2 text-xs">
								<input
									class="min-w-0 flex-1 rounded-md border border-stone-400 px-2 py-1"
									value={it.note}
									maxlength="1000"
									placeholder={m.collection_note_placeholder()}
									aria-label={m.collection_note_placeholder()}
									onchange={(e) => patchItem(it, { note: e.currentTarget.value })}
								/>
								<button
									type="button"
									class="px-1"
									disabled={i === 0}
									aria-label={m.journey_move_up()}
									onclick={() => patchItem(it, { position: collection.item_list[i - 1].position })}
									>↑</button
								>
								<button
									type="button"
									class="px-1"
									disabled={i === collection.item_list.length - 1}
									aria-label={m.journey_move_down()}
									onclick={() => patchItem(it, { position: collection.item_list[i + 1].position })}
									>↓</button
								>
								<button
									type="button"
									class="text-stone-500 underline"
									onclick={() => (removing = it.id)}>{m.collection_remove_item()}</button
								>
							</div>
							{#if removing === it.id}
								<div
									class="mt-2 flex flex-wrap items-center gap-2 text-xs"
									data-testid="remove-confirm"
								>
									<span class="flex-1">{m.collection_remove_confirm({ title: it.title })}</span>
									<button
										type="button"
										class="rounded bg-red-700 px-2 py-1 text-white"
										use:focused
										onclick={() => {
											removing = undefined;
											removeItem(it);
										}}>{m.collection_remove_item()}</button
									>
									<button
										type="button"
										class="text-stone-500 underline"
										onclick={() => (removing = undefined)}>{m.collection_remove_cancel()}</button
									>
								</div>
							{/if}
						{:else if it.note}
							<p class="mt-1 text-xs text-stone-600">{it.note}</p>
						{/if}
					</li>
				{/each}
			</ol>
		{/if}

		{#if isOwner}
			<section class="flex flex-col gap-2 rounded-md border border-stone-200 p-3 text-sm">
				<h2 class="font-medium">{m.journey_settings()}</h2>
				<label class="flex flex-col gap-1">
					<span>{m.field_visibility()}</span>
					<select
						class="rounded-md border border-stone-400 px-2 py-1.5"
						value={collection.visibility}
						use:choose={(v) => patch({ visibility: v as 'private' | 'unlisted' | 'public' })}
					>
						<option value="private">{m.visibility_private()}</option>
						<option value="unlisted" disabled={!user?.email_verified}
							>{m.visibility_unlisted()}</option
						>
						<option value="public" disabled={!user?.email_verified}>{m.visibility_public()}</option>
					</select>
				</label>
				{#if shareUrl && collection.visibility === 'unlisted'}
					<input
						readonly
						aria-label={m.share_link()}
						value={shareUrl}
						class="rounded-md border border-stone-400 px-1.5 py-1 text-xs"
						data-testid="collection-share-link"
					/>
				{/if}
				{#if confirming}
					<button
						type="button"
						class="self-start rounded bg-red-700 px-2 py-1 text-white"
						use:focused
						onclick={remove}>{m.collection_delete_confirm()}</button
					>
				{:else}
					<button
						type="button"
						class="self-start text-stone-500 underline"
						onclick={() => (confirming = true)}>{m.collection_delete()}</button
					>
				{/if}
			</section>
			<SharePanel kind="collections" id={collection.id} verified={!!user?.email_verified} />
		{/if}
	</aside>
</main>
