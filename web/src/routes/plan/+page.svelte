<script lang="ts">
	import PlannerView from '#lib/planner/PlannerView.svelte';

	let { data } = $props();
</script>

<PlannerView user={data.user} />
