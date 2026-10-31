<script lang="ts">
	import Avatar from '#lib/components/Avatar.svelte';
	import { resolve } from '$app/paths';
	import { api } from '#lib/api/client.js';
	import { page } from '$app/state';
	import { actionButton, mainAction } from '#lib/components/actions.js';
	import DoneFilter from '#lib/done/DoneFilter.svelte';
	import { doneDate, passes, readDone } from '#lib/done/done.js';
	import ShareButton from '#lib/components/ShareButton.svelte';
	import TabBar from '#lib/components/TabBar.svelte';
	import FriendButton from '#lib/community/FriendButton.svelte';
	import { outline } from '#lib/discover/outline.js';
	import ReportButton from '#lib/community/ReportButton.svelte';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';
	import { intlLocale } from '#lib/util/locale.js';
	import { sacBackground, sacInk } from '#lib/planner/colors.js';
	import { formatDistance, formatDuration, formatHeight, formatSAC } from '#lib/planner/route.js';

	let { data } = $props();
	const profile = $derived(data.profile);
	// Follower counts and the viewer's follow and block; the buttons override
	// them until the next profile loads.
	let relation = $derived({
		followers: data.profile.followers,
		following: data.profile.following,
		followed: data.profile.followed,
		blocked: data.profile.blocked
	});
	let busy = $state(false);

	async function set(what: 'follow' | 'block', on: boolean) {
		busy = true;
		const params = { params: { path: { username: profile.username } } };
		const call =
			what === 'follow'
				? on
					? api().PUT('/users/{username}/follow', params)
					: api().DELETE('/users/{username}/follow', params)
				: on
					? api().PUT('/users/{username}/block', params)
					: api().DELETE('/users/{username}/block', params);
		const { data: r } = await call;
		busy = false;
		if (r) relation = r;
	}
	const pace = $derived(data.user?.speed_factor ?? 1);

	const tabs = $derived(
		[
			profile.routes.length ? { id: 'routes', label: m.profile_routes() } : undefined,
			profile.journeys.length ? { id: 'journeys', label: m.nav_journeys() } : undefined,
			profile.collections.length ? { id: 'collections', label: m.collections_title() } : undefined
		].filter((t) => t !== undefined)
	);
	let tab = $derived(tabs[0]?.id ?? 'routes');
	// Planned or hiked (feedback issue 58); dates are sent to friends only.
	const done = $derived(readDone(page.url.searchParams));
	const hiked = $derived(
		[...profile.routes, ...profile.journeys].filter((it) => it.done_on).length
	);
	const routes = $derived(profile.routes.filter((r) => passes(done, r.done_on)));
	const journeys = $derived(profile.journeys.filter((j) => passes(done, j.done_on)));
	const since = $derived(
		new Intl.DateTimeFormat(intlLocale(), {
			month: 'long',
			year: 'numeric',
			timeZone: 'Europe/Zurich'
		}).format(new Date(profile.since))
	);
</script>

<Seo
	title={profile.display_name}
	description={m.seo_profile_description({ name: profile.display_name })}
	image={profile.routes.length || profile.journeys.length
		? `/api/v1/users/${encodeURIComponent(profile.username)}/og.png`
		: undefined}
/>

<main class="mx-auto w-full max-w-4xl overflow-y-auto px-4 py-8">
	<section class="rounded-xl border border-stone-200 bg-surface p-5 sm:p-6">
		<div class="flex flex-wrap items-center gap-4">
			<Avatar id={profile.avatar} class="size-16" />
			<div class="min-w-0 flex-1">
				<h1 class="text-2xl font-semibold">{profile.display_name}</h1>
				<p class="text-stone-600">@{profile.username} · {m.profile_since({ date: since })}</p>
			</div>
			<div class="flex flex-wrap items-center gap-2 text-sm">
				{#if profile.self}
					<a href={resolve('/account')} class={actionButton}>{m.profile_edit()}</a>
				{:else if data.user && !relation.blocked}
					<button
						type="button"
						disabled={busy}
						onclick={() => set('follow', !relation.followed)}
						class={actionButton}
					>
						{relation.followed ? m.profile_unfollow() : m.profile_follow()}
					</button>
					{#key profile.username}
						<FriendButton
							username={profile.username}
							friend={profile.friend}
							primary={mainAction}
						/>
					{/key}
				{/if}
				<ShareButton title={profile.display_name} testid="profile-share" />
			</div>
		</div>

		<dl
			class="mt-5 grid grid-cols-2 gap-2 {hiked ? 'sm:grid-cols-5' : 'sm:grid-cols-4'}"
			data-testid="profile-counts"
		>
			{#each [[m.profile_routes(), profile.routes.length], [m.nav_journeys(), profile.journeys.length], ...(hiked ? [[m.done_filter_done(), hiked]] : []), [m.profile_stat_followers(), relation.followers], [m.profile_stat_following(), relation.following]] as [label, n] (label)}
				<div class="flex flex-col-reverse rounded-lg bg-stone-100 px-3 py-2">
					<dt class="text-xs text-stone-600">{label}</dt>
					<dd class="font-display text-xl font-semibold tabular-nums">{n}</dd>
				</div>
			{/each}
		</dl>

		{#if data.user && !profile.self}
			<div class="mt-4 flex flex-wrap items-center gap-3 text-xs">
				<button
					type="button"
					disabled={busy}
					class="text-stone-500 underline"
					onclick={() => set('block', !relation.blocked)}
				>
					{relation.blocked ? m.profile_unblock() : m.profile_block()}
				</button>
				<ReportButton target={{ kind: 'user', username: profile.username }} />
			</div>
			{#if relation.blocked}
				<p class="mt-2 text-xs text-stone-500">{m.profile_blocked_note()}</p>
			{/if}
		{/if}
	</section>

	{#snippet thumb(id: string)}
		<svg width="100%" height="64" viewBox="0 0 280 64" aria-hidden="true" class="mb-3">
			<path
				d={outline(profile.outlines[id] ?? [], 280, 64, 4)}
				fill="none"
				class="stroke-accent"
				stroke-width="2.5"
				stroke-linejoin="round"
				stroke-linecap="round"
			/>
		</svg>
	{/snippet}

	{#snippet byline(owner: string, doneOn: string | undefined)}
		{@const line = [
			doneOn ? `✓ ${m.done_on({ date: doneDate(doneOn) })}` : '',
			owner !== profile.username ? m.collection_add_shared({ owner }) : ''
		]
			.filter(Boolean)
			.join(' · ')}
		{#if line}<div class="mt-1 text-xs text-stone-500" data-testid="byline">{line}</div>{/if}
	{/snippet}

	{#if tabs.length}
		<!-- A card as the others: rounded and outlined, without the bar's own line. -->
		<div class="mt-8 overflow-hidden rounded-xl border border-stone-200 [&>div]:border-b-0">
			<TabBar {tabs} bind:current={tab} />
		</div>
		{#if hiked && tab !== 'collections'}<div class="mt-4"><DoneFilter /></div>{/if}
	{/if}

	{#if profile.routes.length > 0}
		<div role="tabpanel" id="pane-routes" aria-labelledby="tab-routes" hidden={tab !== 'routes'}>
			<ul class="mt-4 grid gap-3 sm:grid-cols-2" data-testid="profile-routes">
				{#each routes as r (r.id)}
					<li>
						<a
							href={resolve('/routes/[id]', { id: r.id })}
							class="block h-full rounded-xl border border-stone-200 bg-surface p-4 hover:border-stone-300 hover:bg-stone-50"
						>
							{@render thumb(r.id)}
							<div class="flex items-start gap-2">
								<span class="min-w-0 flex-1 truncate font-semibold">{r.title}</span>
								<span
									class="shrink-0 rounded px-1.5 py-0.5 text-xs font-semibold"
									style:background={sacBackground(r.totals.sac_grade)}
									style:color={sacInk(r.totals.sac_grade)}
								>
									{formatSAC(r.totals.sac_grade, r.totals.sac_max)}
								</span>
							</div>
							<div class="mt-1 text-[13px] text-stone-600 tabular-nums">
								{formatDistance(r.totals.distance_m)} · {formatDuration(r.totals.duration_s, pace)} ·
								↑&nbsp;{formatHeight(r.totals.ascent_m)}
							</div>
							{@render byline(r.owner_username, r.done_on)}
						</a>
					</li>
				{/each}
			</ul>
		</div>
	{/if}

	{#if profile.journeys.length > 0}
		<div
			role="tabpanel"
			id="pane-journeys"
			aria-labelledby="tab-journeys"
			hidden={tab !== 'journeys'}
		>
			<ul class="mt-4 grid gap-3 sm:grid-cols-2" data-testid="profile-journeys">
				{#each journeys as j (j.id)}
					<li>
						<a
							href={resolve('/journeys/[id]', { id: j.id })}
							class="block h-full rounded-xl border border-stone-200 bg-surface p-4 hover:border-stone-300 hover:bg-stone-50"
						>
							{@render thumb(j.id)}
							<div class="truncate font-semibold">{j.title}</div>
							<div class="mt-1 text-[13px] text-stone-600 tabular-nums">
								{m.collection_stages({ n: j.stages })} · {formatDistance(j.distance_m)} · {formatDuration(
									j.duration_s,
									pace
								)}
							</div>
							{@render byline(j.owner_username, j.done_on)}
						</a>
					</li>
				{/each}
			</ul>
		</div>
	{/if}

	{#if profile.collections.length > 0}
		<div
			role="tabpanel"
			id="pane-collections"
			aria-labelledby="tab-collections"
			hidden={tab !== 'collections'}
		>
			<ul class="mt-4 grid gap-3 sm:grid-cols-2" data-testid="profile-collections">
				{#each profile.collections as c (c.id)}
					<li>
						<a
							href={resolve('/collections/[id]', { id: c.id })}
							class="block h-full rounded-xl border border-stone-200 bg-surface p-4 hover:border-stone-300 hover:bg-stone-50"
						>
							<div class="truncate font-semibold">{c.title}</div>
							<div class="mt-1 text-[13px] text-stone-600">
								{m.collection_items_count({ n: c.items })}
							</div>
						</a>
					</li>
				{/each}
			</ul>
		</div>
	{/if}
</main>
