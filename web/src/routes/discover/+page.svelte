<script lang="ts">
	import DiscoverView from '#lib/discover/DiscoverView.svelte';

	let { data } = $props();
</script>

<DiscoverView user={data.user} />
