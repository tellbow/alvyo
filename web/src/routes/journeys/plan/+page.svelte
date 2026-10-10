<script lang="ts">
	import JourneyPlanView from '#lib/journeys/JourneyPlanView.svelte';

	let { data } = $props();
</script>

<JourneyPlanView user={data.user} />
