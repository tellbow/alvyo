<script lang="ts">
	import ReachView from '$lib/reach/ReachView.svelte';

	let { data } = $props();
</script>

<ReachView user={data.user} />
