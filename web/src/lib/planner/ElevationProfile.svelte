<script lang="ts">
	import { m } from '$lib/paraglide/messages';
	import { SAC_COLOR } from './colors';
	import { formatDistance, formatHeight, gradeAt, type Profile3 } from './route';

	let {
		line,
		hover = $bindable(),
		colors = SAC_COLOR,
		breaks = [],
		height = 140
	}: {
		line: Profile3;
		hover?: number;
		/** fill colour per run value (default: SAC grades) */
		colors?: Record<string, string>;
		/** coordinate indices where a new stage starts (vertical separators) */
		breaks?: number[];
		/** in pixels */
		height?: number;
	} = $props();

	let width = $state(600);
	const pad = { l: 44, r: 12, t: 18, b: 20 };

	const total = $derived(line.distance.at(-1) ?? 0);
	const range = $derived.by(() => {
		let lo = Infinity;
		let hi = -Infinity;
		for (const c of line.coordinates) {
			lo = Math.min(lo, c[2]);
			hi = Math.max(hi, c[2]);
		}
		// Round outwards to 50 m and keep at least 100 m of relief visible.
		lo = Math.floor(lo / 50) * 50;
		hi = Math.max(Math.ceil(hi / 50) * 50, lo + 100);
		return { lo, hi };
	});

	// What the picture shows, for screen readers.
	const summary = $derived.by(() => {
		let low = Infinity;
		let high = -Infinity;
		for (const c of line.coordinates) {
			low = Math.min(low, c[2]);
			high = Math.max(high, c[2]);
		}
		return m.profile_summary({
			length: formatDistance(total),
			low: formatHeight(low),
			high: formatHeight(high)
		});
	});

	const x = (d: number) => pad.l + (total ? (d / total) * (width - pad.l - pad.r) : 0);
	const y = (e: number) =>
		pad.t + ((range.hi - e) / (range.hi - range.lo)) * (height - pad.t - pad.b);

	/** One filled area per SAC run, in its grade colour. */
	const areas = $derived(
		line.sac.map((run) => {
			let d = `M${x(line.distance[run.from])},${y(range.lo)}`;
			for (let i = run.from; i <= run.to; i++)
				d += `L${x(line.distance[i])},${y(line.coordinates[i][2])}`;
			d += `L${x(line.distance[run.to])},${y(range.lo)}Z`;
			return { d, color: colors[run.value] ?? '#8a978f' };
		})
	);
	const outline = $derived(
		line.coordinates.map((c, i) => `${i ? 'L' : 'M'}${x(line.distance[i])},${y(c[2])}`).join('')
	);

	function onmove(e: PointerEvent) {
		const rect = (e.currentTarget as SVGElement).getBoundingClientRect();
		const d = ((e.clientX - rect.left - pad.l) / (width - pad.l - pad.r)) * total;
		// Binary search for the first sample at or beyond d.
		let lo = 0;
		let hi = line.distance.length - 1;
		while (lo < hi) {
			const mid = (lo + hi) >> 1;
			if (line.distance[mid] < d) lo = mid + 1;
			else hi = mid;
		}
		hover = Math.max(0, Math.min(lo, line.distance.length - 1));
	}
</script>

{#if line.coordinates.length > 1}
	<!-- Clipped until it has measured its width: no page wider than a phone. -->
	<figure class="w-full overflow-hidden" bind:clientWidth={width} aria-label={m.profile_title()}>
		<svg
			{width}
			{height}
			role="img"
			aria-label={summary}
			class="block touch-none select-none"
			onpointermove={onmove}
			onpointerleave={() => (hover = undefined)}
			data-testid="elevation-profile"
		>
			{#each areas as a, i (i)}
				<path d={a.d} fill={a.color} fill-opacity="0.35" />
			{/each}
			<path d={outline} fill="none" class="stroke-stone-700" stroke-width="1.5" />
			{#each breaks.slice(1) as b (b)}
				{@const bx = x(line.distance[b])}
				<line
					x1={bx}
					x2={bx}
					y1={pad.t}
					y2={height - pad.b}
					class="stroke-stone-500"
					stroke-width="1"
				/>
			{/each}

			<g class="fill-stone-500 text-[10px]">
				<text x={pad.l - 6} y={y(range.hi) + 4} text-anchor="end">{range.hi} m</text>
				<text x={pad.l - 6} y={y(range.lo)} text-anchor="end">{range.lo} m</text>
				<text x={x(0)} y={height - 4}>0</text>
				<text x={x(total)} y={height - 4} text-anchor="end">{formatDistance(total)}</text>
			</g>

			{#if hover !== undefined && line.coordinates[hover]}
				{@const hx = x(line.distance[hover])}
				<line
					x1={hx}
					x2={hx}
					y1={pad.t}
					y2={height - pad.b}
					class="stroke-stone-700"
					stroke-dasharray="2 2"
				/>
				<text
					x={Math.min(Math.max(hx, pad.l + 40), width - 140)}
					y={12}
					class="fill-stone-800 text-[11px] font-medium"
				>
					{[
						formatDistance(line.distance[hover]),
						formatHeight(line.coordinates[hover][2]),
						gradeAt(line, hover)
					]
						.filter(Boolean)
						.join(' · ')}
				</text>
			{/if}
		</svg>
	</figure>
{/if}
