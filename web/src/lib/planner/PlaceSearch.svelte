<script lang="ts">
	import { api, type FoundPlace } from '$lib/api/client';
	import { placeLabel } from '$lib/journeys/places';
	import { m } from '$lib/paraglide/messages';

	let {
		label,
		near,
		onpick
	}: {
		label: string;
		/** The map centre: among equally good matches, the nearest come first. */
		near: () => [number, number] | undefined;
		onpick: (place: FoundPlace) => void;
	} = $props();

	const uid = $props.id();
	let q = $state('');
	let results = $state<FoundPlace[]>();
	let active = $state(-1);

	$effect(() => {
		const text = q.trim();
		if (text.length < 2) {
			results = undefined;
			return;
		}
		let stale = false;
		const timer = setTimeout(async () => {
			const c = near();
			const inCH = c && c[0] >= 5.9 && c[0] <= 10.6 && c[1] >= 45.8 && c[1] <= 47.9;
			const { data } = await api().GET('/places/search', {
				params: { query: { q: text, ...(inCH ? { lon: c[0], lat: c[1] } : {}) } }
			});
			if (stale) return;
			results = data?.places ?? [];
			active = -1;
		}, 250);
		return () => {
			stale = true;
			clearTimeout(timer);
		};
	});

	function pick(p: FoundPlace) {
		onpick(p);
		q = '';
		results = undefined;
	}

	function onkeydown(e: KeyboardEvent) {
		if (!results?.length) return;
		if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
			e.preventDefault();
			const step = e.key === 'ArrowDown' ? 1 : -1;
			active = (active + step + results.length) % results.length;
		} else if (e.key === 'Enter') {
			e.preventDefault();
			pick(results[Math.max(active, 0)]);
		} else if (e.key === 'Escape') {
			results = undefined;
		}
	}

	/** What it is: stop modes ("Bus"), the kind of name ("Hauptgipfel, Isenthal (UR)") … */
	function kind(p: FoundPlace): string {
		switch (p.kind) {
			case 'name':
				return p.detail;
			case 'address':
				return m.place_kind_address();
			case 'pt_stop':
				return p.detail || placeLabel(p.kind);
			default:
				return p.detail === 'wilderness_hut' ? m.place_wilderness_hut() : placeLabel(p.kind);
		}
	}
</script>

<div class="relative">
	<input
		type="search"
		class="w-full rounded-md border border-stone-300 px-2 py-1.5 text-sm"
		placeholder={label}
		aria-label={label}
		role="combobox"
		aria-autocomplete="list"
		aria-expanded={!!results?.length}
		aria-controls="{uid}-list"
		aria-activedescendant={active >= 0 ? `${uid}-${active}` : undefined}
		bind:value={q}
		{onkeydown}
	/>
	{#if results?.length === 0}
		<p class="mt-1 text-xs text-stone-500">{m.place_nothing_found()}</p>
	{:else if results}
		<ul
			id="{uid}-list"
			role="listbox"
			class="absolute z-20 mt-1 max-h-80 w-full overflow-y-auto rounded-md bg-white py-1 text-sm shadow-lg ring-1 ring-stone-300"
		>
			{#each results as p, i (i)}
				<!-- Combobox pattern: the keys are handled on the input, options never get focus. -->
				<!-- svelte-ignore a11y_click_events_have_key_events -->
				<li
					id="{uid}-{i}"
					role="option"
					aria-selected={i === active}
					class="flex cursor-pointer flex-col px-2 py-1 hover:bg-stone-100"
					class:bg-stone-100={i === active}
					onmousedown={(e) => e.preventDefault()}
					onclick={() => pick(p)}
				>
					<span>{p.name}</span>
					<span class="text-xs text-stone-500">{kind(p)}</span>
				</li>
			{/each}
		</ul>
	{/if}
</div>
