<script lang="ts">
	import PlannerView from '$lib/planner/PlannerView.svelte';

	let { data } = $props();
</script>

{#key data.journey.stage_list[data.index].id}
	<PlannerView
		user={data.user}
		route={data.route}
		stage={{ journey: data.journey, index: data.index }}
	/>
{/key}
