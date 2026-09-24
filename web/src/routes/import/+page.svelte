<script lang="ts">
	import FileImport from '$lib/imports/FileImport.svelte';
	import KomootImport from '$lib/imports/KomootImport.svelte';
	import { m } from '$lib/paraglide/messages';

	let { data } = $props();
</script>

<main class="mx-auto flex w-full max-w-4xl flex-col gap-6 overflow-y-auto px-4 py-8">
	<div>
		<h1 class="text-2xl font-semibold">{m.import_title()}</h1>
		<p class="mt-1 text-stone-600">{m.import_intro()}</p>
	</div>
	<FileImport pace={data.user?.speed_factor ?? 1} />
	<KomootImport />
</main>
