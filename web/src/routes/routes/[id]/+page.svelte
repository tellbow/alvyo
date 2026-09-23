<script lang="ts">
	import RouteView from '$lib/planner/RouteView.svelte';

	let { data } = $props();
</script>

{#key data.route.id}
	<RouteView route={data.route} token={data.token} user={data.user} />
{/key}
