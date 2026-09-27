<script lang="ts">
	import { resolve } from '$app/paths';
	import { m } from '$lib/paraglide/messages';

	/** Which planner this is: one route, or a multi-day hike. */
	let { current }: { current: 'route' | 'journey' } = $props();

	const tab = (on: boolean) =>
		`flex-1 rounded-md px-3 py-1.5 text-center ${on ? 'bg-surface font-medium shadow ring-1 ring-stone-300' : 'text-stone-600 hover:text-accent-ink'}`;
</script>

<nav
	class="flex gap-1 rounded-lg bg-stone-100 p-1 text-sm"
	aria-label={m.plan_tabs()}
	data-testid="plan-tabs"
>
	<a
		href={resolve('/plan')}
		class={tab(current === 'route')}
		aria-current={current === 'route' ? 'page' : undefined}>{m.plan_tab_route()}</a
	>
	<a
		href={resolve('/journeys/plan')}
		class={tab(current === 'journey')}
		aria-current={current === 'journey' ? 'page' : undefined}>{m.plan_tab_journey()}</a
	>
</nav>
