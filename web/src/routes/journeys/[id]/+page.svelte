<script lang="ts">
	import JourneyView from '#lib/journeys/JourneyView.svelte';

	let { data } = $props();
</script>

{#key data.journey.id}
	<JourneyView journey={data.journey} token={data.token} user={data.user} />
{/key}
