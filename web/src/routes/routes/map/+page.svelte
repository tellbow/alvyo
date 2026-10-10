<script lang="ts">
	import MyMapView from '#lib/mymap/MyMapView.svelte';

	let { data } = $props();
</script>

<MyMapView user={data.user} />
