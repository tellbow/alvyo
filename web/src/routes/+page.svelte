<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import type { DiscoverItem } from '#lib/api/client.js';
	import { outline } from '#lib/discover/outline.js';
	import { m } from '#lib/paraglide/messages.js';
	import PlaceSearch from '#lib/planner/PlaceSearch.svelte';
	import { formatDistance, formatDuration, formatHeight, formatSAC } from '#lib/planner/route.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	const pace = $derived(data.user?.speed_factor ?? 1);
	const featured = $derived(data.hikes[0]);

	function href(it: DiscoverItem) {
		return it.kind === 'route'
			? resolve('/routes/[id]', { id: it.id })
			: resolve('/journeys/[id]', { id: it.id });
	}

	function kindOf(it: DiscoverItem) {
		const kind = it.kind === 'route' ? m.collection_kind_route() : m.collection_kind_journey();
		return it.sac_grade > 0 ? `${kind} · ${formatSAC(it.sac_grade, it.sac_max)}` : kind;
	}

	function stats(it: DiscoverItem) {
		return `${formatDistance(it.distance_m)} · ${formatDuration(it.duration_s, pace)} · ↑\u00a0${formatHeight(it.ascent_m)}`;
	}

	// A place: the public hikes around it.
	function around(at: number[]) {
		const [lon, lat] = at;
		const bbox = [lon - 0.12, lat - 0.08, lon + 0.12, lat + 0.08].map((v) => v.toFixed(4));
		void goto(`${resolve('/discover')}?bbox=${bbox.join(',')}`);
	}
</script>

<Seo title="Alvyo – {m.seo_home_title()}" description={m.seo_home_description()} image="/og.jpg" />

<main class="relative flex-1 overflow-y-auto">
	<!-- Contour lines and a route, as on a map. -->
	<svg
		class="pointer-events-none absolute inset-0 size-full"
		viewBox="0 0 800 600"
		preserveAspectRatio="xMidYMid slice"
		aria-hidden="true"
	>
		<g fill="none" class="stroke-stone-200" stroke-width="0.9">
			<path
				d="M520 150C570 148 610 185 605 225C600 268 560 290 515 285C470 280 445 250 450 215C455 180 480 152 520 150Z"
			/>
			<path
				d="M515 100C600 95 665 150 660 225C655 300 590 340 510 335C430 330 395 280 400 215C405 150 440 105 515 100Z"
			/>
			<path
				d="M505 50C630 40 720 120 715 230C710 340 620 395 500 390C380 385 340 310 345 215C350 120 400 58 505 50Z"
			/>
			<path
				d="M490 0C660 -15 780 100 775 240C770 380 650 455 490 450C330 445 280 350 290 215C300 90 360 8 490 0Z"
			/>
			<path
				d="M480 -40C690 -60 830 80 830 250C830 420 690 510 480 505C280 500 220 390 235 215C250 70 320 -30 480 -40Z"
			/>
			<path
				d="M220 380C255 378 275 400 272 425C268 450 245 462 218 458C190 454 175 435 178 412C182 392 198 381 220 380Z"
			/>
			<path
				d="M215 335C280 330 320 375 316 428C312 480 270 505 212 500C155 496 128 460 133 412C138 365 170 338 215 335Z"
			/>
			<path
				d="M205 285C300 275 370 340 362 432C355 520 290 555 205 550C120 545 80 490 88 410C95 335 140 290 205 285Z"
			/>
			<path
				d="M195 230C320 220 420 310 410 440C400 560 310 610 190 600C75 590 30 510 40 410C50 310 110 236 195 230Z"
			/>
		</g>
		<path
			d="M0 300C80 320 120 280 200 250C280 220 300 180 340 120C360 90 400 60 420 0"
			fill="none"
			class="stroke-[#b7d1d0] dark:stroke-[#1e3a36]"
			stroke-width="3"
		/>
		<ellipse cx="330" cy="505" rx="80" ry="28" class="fill-[#d2e4e2] dark:fill-[#15302c]" />
		<g fill="none" class="stroke-accent" stroke-linecap="round">
			<path
				d="M90 560C160 520 170 470 230 440C300 405 330 360 380 330C430 300 470 290 510 250C540 220 560 200 600 190C660 175 700 150 760 120"
				stroke-opacity="0.2"
				stroke-width="12"
			/>
			<path
				d="M90 560C160 520 170 470 230 440C300 405 330 360 380 330C430 300 470 290 510 250C540 220 560 200 600 190C660 175 700 150 760 120"
				stroke-width="2.6"
			/>
		</g>
		<circle cx="510" cy="250" r="5" class="fill-surface stroke-accent" stroke-width="2" />
		<circle cx="760" cy="120" r="5" class="fill-accent" />
	</svg>

	<div
		class="relative flex min-h-full flex-col justify-between gap-8 p-6 lg:flex-row lg:items-end lg:p-10"
	>
		<section
			class="flex w-full max-w-md flex-col gap-6 self-start rounded-[28px] border border-stone-200 bg-surface/95 p-8"
		>
			<h1 class="text-5xl leading-[0.98] font-bold">{m.home_headline()}</h1>
			<p class="text-[17px] leading-normal text-stone-600">{m.app_tagline()}</p>
			<!-- Place search needs an account (it asks geo.admin). -->
			{#if data.user}
				<PlaceSearch
					label={m.home_search()}
					near={() => undefined}
					onpick={(p) => around(p.at)}
					inputClass="h-14 w-full rounded-2xl border border-stone-400 bg-ground px-4 text-base"
				/>
			{/if}
			<div class="flex gap-3">
				<a
					href={resolve('/plan')}
					class="flex h-12 flex-1 items-center justify-center rounded-md bg-accent font-semibold text-on-accent hover:bg-accent-hover"
				>
					{m.nav_plan()}
				</a>
				<a
					href={resolve('/discover')}
					class="flex h-12 flex-1 items-center justify-center rounded-md border border-stone-300 font-medium hover:bg-stone-50"
				>
					{m.discover_title()}
				</a>
			</div>
			{#if data.hikes.length}
				<div class="flex flex-col">
					<h2 class="mb-1 font-sans text-sm font-semibold text-stone-600">{m.home_public()}</h2>
					{#each data.hikes as it (it.id)}
						<a
							href={href(it)}
							class="flex items-center gap-3.5 border-t border-stone-200 py-3.5 hover:text-accent-ink"
							data-testid="home-hike"
						>
							<svg width="56" height="32" aria-hidden="true" class="shrink-0">
								<path
									d={outline(it.lines, 56, 32)}
									fill="none"
									class="stroke-accent"
									stroke-width="2"
									stroke-linejoin="round"
								/>
							</svg>
							<div class="min-w-0 flex-1">
								<div class="truncate font-semibold">{it.title}</div>
								<div class="text-[13px] text-stone-600 tabular-nums">{stats(it)}</div>
							</div>
							<svg
								width="18"
								height="18"
								viewBox="0 0 24 24"
								fill="none"
								class="shrink-0 stroke-stone-600"
								stroke-width="2"
								aria-hidden="true"><path d="M9 5l7 7-7 7" /></svg
							>
						</a>
					{/each}
				</div>
			{/if}
		</section>

		<div class="flex w-full max-w-md flex-col gap-4 lg:items-end">
			{#if featured}
				<article
					class="flex w-full flex-col gap-4 rounded-[28px] border border-stone-200 bg-surface/95 p-7"
				>
					<div>
						<div class="text-[13px] font-semibold text-accent-ink">
							{kindOf(featured)}
						</div>
						<h2 class="text-3xl font-bold">{featured.title}</h2>
						<div class="text-sm text-stone-600">
							{m.shared_by({ user: featured.owner_username })}
						</div>
					</div>
					<svg width="100%" height="96" viewBox="0 0 364 96" aria-hidden="true">
						<path
							d={outline(featured.lines, 364, 96, 6)}
							fill="none"
							class="stroke-accent"
							stroke-width="3"
							stroke-linejoin="round"
							stroke-linecap="round"
						/>
					</svg>
					<dl class="grid grid-cols-3 gap-2">
						<div class="flex flex-col-reverse">
							<dt class="text-xs text-stone-600">{m.stat_distance()}</dt>
							<dd class="font-display text-[22px] font-semibold tabular-nums">
								{formatDistance(featured.distance_m)}
							</dd>
						</div>
						<div class="flex flex-col-reverse">
							<dt class="text-xs text-stone-600">{m.stat_time()}</dt>
							<dd class="font-display text-[22px] font-semibold tabular-nums">
								{formatDuration(featured.duration_s, pace)}
							</dd>
						</div>
						<div class="flex flex-col-reverse">
							<dt class="text-xs text-stone-600">{m.stat_ascent()}</dt>
							<dd class="font-display text-[22px] font-semibold tabular-nums">
								{formatHeight(featured.ascent_m)}
							</dd>
						</div>
					</dl>
					<a
						href={href(featured)}
						class="flex h-13 items-center justify-center rounded-md bg-accent font-semibold text-on-accent hover:bg-accent-hover"
					>
						{m.home_open()}
					</a>
				</article>
			{/if}
			<ul class="grid gap-2 text-sm text-stone-700">
				{#each [m.home_feature_plan(), m.home_feature_journeys(), m.home_feature_app(), m.home_feature_discover()] as f (f)}
					<li class="rounded-2xl border border-stone-200 bg-surface/90 px-4 py-3">{f}</li>
				{/each}
			</ul>
		</div>
	</div>
</main>
