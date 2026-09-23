<script lang="ts">
	import CollectionView from '$lib/collections/CollectionView.svelte';

	let { data } = $props();
</script>

{#key data.collection.id}
	<CollectionView collection={data.collection} user={data.user} />
{/key}
