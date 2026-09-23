<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '$lib/paraglide/messages';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import type { Gallery, UploadProblem } from './gallery.svelte';
	import Lightbox from './Lightbox.svelte';

	let { gallery, loggedIn }: { gallery: Gallery; loggedIn: boolean } = $props();

	const hydrated = new Hydrated();
	let progress = $state<{ done: number; total: number }>();
	let problems = $state<string[]>([]);

	const messages: Record<UploadProblem, () => string> = {
		format: m.photos_problem_format,
		size: m.photos_problem_size,
		limit: m.photos_problem_limit,
		rate: m.photos_problem_rate,
		other: m.photos_problem_other
	};

	async function pick(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const files = [...(input.files ?? [])];
		input.value = '';
		problems = [];
		progress = { done: 0, total: files.length };
		for (const f of files) {
			const problem = await gallery.upload(f);
			if (problem) problems = [...problems, `${f.name}: ${messages[problem]()}`];
			progress.done++;
			if (problem === 'limit') break;
		}
		progress = undefined;
	}

	onMount(() => void gallery.load());
</script>

{#if gallery.photos.length > 0 || gallery.canEdit}
	<section class="flex flex-col gap-2 text-sm" data-testid="photos">
		<h2 class="font-medium">{m.photos_title()}</h2>
		{#if gallery.photos.length > 0}
			<ul class="grid grid-cols-3 gap-1">
				{#each gallery.photos as p (p.id)}
					<li>
						<button
							type="button"
							class="block aspect-square w-full overflow-hidden rounded bg-stone-100"
							onclick={() => (gallery.open = p.id)}
							aria-label={p.caption || m.photos_open()}
						>
							<img
								src={gallery.src(p, 'thumb')}
								alt={p.caption}
								loading="lazy"
								class="h-full w-full object-cover"
							/>
						</button>
					</li>
				{/each}
			</ul>
		{/if}
		{#if gallery.canEdit}
			<label
				class="cursor-pointer self-start rounded-md px-3 py-1.5 ring-1 ring-stone-300 hover:bg-stone-50"
				class:opacity-50={!hydrated.value || progress}
			>
				{progress
					? m.photos_uploading({ done: progress.done, total: progress.total })
					: m.photos_add()}
				<input
					type="file"
					accept="image/jpeg,image/png,image/webp"
					multiple
					class="sr-only"
					disabled={!hydrated.value || !!progress}
					onchange={pick}
				/>
			</label>
			<p class="text-xs text-stone-500">{m.photos_hint()}</p>
			{#each problems as problem, i (i)}
				<p class="text-xs text-red-700" role="alert">{problem}</p>
			{/each}
		{/if}
	</section>
{/if}

{#if gallery.open}
	<Lightbox {gallery} {loggedIn} />
{/if}
