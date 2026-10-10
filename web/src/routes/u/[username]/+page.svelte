<script lang="ts">
	import { resolve } from '$app/paths';
	import { api } from '#lib/api/client.js';
	import FriendButton from '#lib/community/FriendButton.svelte';
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
/>

<main class="mx-auto w-full max-w-4xl overflow-y-auto px-4 py-8">
	<h1 class="text-2xl font-semibold">{profile.display_name}</h1>
	<p class="mt-1 text-stone-600">@{profile.username} · {m.profile_since({ date: since })}</p>
	<p class="mt-1 text-sm text-stone-600" data-testid="profile-counts">
		{m.profile_followers({ n: relation.followers })} · {m.profile_following({
			n: relation.following
		})}
	</p>
	{#if data.user && !profile.self}
		<div class="mt-4 flex flex-wrap items-center gap-3 text-sm">
			{#if !relation.blocked}
				<button
					type="button"
					disabled={busy}
					onclick={() => set('follow', !relation.followed)}
					class={relation.followed
						? 'rounded-md px-3 py-1.5 ring-1 ring-stone-300'
						: 'rounded-md bg-accent px-3 py-1.5 text-on-accent hover:bg-accent-hover'}
				>
					{relation.followed ? m.profile_unfollow() : m.profile_follow()}
				</button>
				{#key profile.username}
					<FriendButton username={profile.username} friend={profile.friend} />
				{/key}
			{/if}
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

	{#if profile.journeys.length > 0}
		<h2 class="mt-8 mb-2 text-lg font-semibold">{m.nav_journeys()}</h2>
		<ul
			class="divide-y divide-stone-200 rounded-md border border-stone-200 bg-surface"
			data-testid="profile-journeys"
		>
			{#each profile.journeys as j (j.id)}
				<li>
					<a
						href={resolve('/journeys/[id]', { id: j.id })}
						class="flex items-center gap-4 px-4 py-3 hover:bg-stone-50"
					>
						<span class="flex-1 font-medium">{j.title}</span>
						<span class="text-sm text-stone-600">{m.collection_stages({ n: j.stages })}</span>
						<span class="w-20 text-sm text-stone-600 tabular-nums"
							>{formatDistance(j.distance_m)}</span
						>
						<span class="w-24 text-sm text-stone-600 tabular-nums"
							>{formatDuration(j.duration_s, pace)}</span
						>
					</a>
				</li>
			{/each}
		</ul>
	{/if}

	{#if profile.routes.length > 0}
		<h2 class="mt-8 mb-2 text-lg font-semibold">{m.profile_routes()}</h2>
		<ul
			class="divide-y divide-stone-200 rounded-md border border-stone-200 bg-surface"
			data-testid="profile-routes"
		>
			{#each profile.routes as r (r.id)}
				<li>
					<a
						href={resolve('/routes/[id]', { id: r.id })}
						class="flex items-center gap-4 px-4 py-3 hover:bg-stone-50"
					>
						<span class="flex-1 font-medium">{r.title}</span>
						<span class="text-sm text-stone-600 tabular-nums"
							>{formatDistance(r.totals.distance_m)}</span
						>
						<span class="w-24 text-sm text-stone-600 tabular-nums"
							>{formatDuration(r.totals.duration_s, pace)}</span
						>
						<span class="w-20 text-sm text-stone-600 tabular-nums"
							>↑&nbsp;{formatHeight(r.totals.ascent_m)}</span
						>
						<span
							class="w-16 rounded px-1.5 py-0.5 text-center text-xs font-semibold"
							style:background={sacBackground(r.totals.sac_grade)}
							style:color={sacInk(r.totals.sac_grade)}
						>
							{formatSAC(r.totals.sac_grade, r.totals.sac_max)}
						</span>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</main>
