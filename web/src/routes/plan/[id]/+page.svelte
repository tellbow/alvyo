<script lang="ts">
	import PlannerView from '#lib/planner/PlannerView.svelte';

	let { data } = $props();
</script>

<!-- A new planner per route: {#key} resets it when navigating between routes. -->
{#key data.route.id}
	<PlannerView user={data.user} route={data.route} />
{/key}
