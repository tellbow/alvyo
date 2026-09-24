<script lang="ts">
	import LiveView from '$lib/live/LiveView.svelte';

	let { data } = $props();
</script>

<LiveView view={data.view} token={data.token} />
