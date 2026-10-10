<script lang="ts">
	import ReportButton from '#lib/community/ReportButton.svelte';
	import { m } from '#lib/paraglide/messages.js';
	import { intlLocale } from '#lib/util/locale.js';
	import type { Gallery } from './gallery.svelte';

	let { gallery, loggedIn }: { gallery: Gallery; loggedIn: boolean } = $props();

	const photo = $derived(gallery.photos.find((p) => p.id === gallery.open));
	const index = $derived(gallery.photos.findIndex((p) => p.id === gallery.open));
	const when = $derived(
		new Intl.DateTimeFormat(intlLocale(), {
			dateStyle: 'medium',
			timeStyle: 'short',
			timeZone: 'Europe/Zurich'
		})
	);
	let confirming = $state(false);
	// When it was taken (if known) and who uploaded it.
	const details = $derived(
		photo
			? [
					photo.taken_at && when.format(new Date(photo.taken_at)),
					m.photos_by({ user: photo.uploader })
				]
					.filter(Boolean)
					.join(' · ')
			: ''
	);

	function close() {
		gallery.open = undefined;
	}

	function key(e: KeyboardEvent) {
		if (e.target instanceof HTMLInputElement) return;
		if (e.key === 'Escape') close();
		else if (e.key === 'ArrowRight') gallery.step(1);
		else if (e.key === 'ArrowLeft') gallery.step(-1);
	}

	$effect(() => {
		void gallery.open;
		confirming = false;
	});

	// A modal dialog keeps the keyboard in it and gives focus back when closed.
	let dialog = $state<HTMLDialogElement>();
	$effect(() => {
		if (!dialog) return;
		if (photo && !dialog.open) dialog.showModal();
		else if (!photo && dialog.open) dialog.close();
	});
</script>

<svelte:window onkeydown={key} />

<dialog
	bind:this={dialog}
	class="m-0 h-full max-h-none w-full max-w-none border-0 bg-black/90 p-0 text-white backdrop:bg-transparent"
	aria-label={photo?.caption || m.photos_title()}
	oncancel={(e) => {
		e.preventDefault(); // Escape: closed through the gallery, as by the button
		close();
	}}
>
	{#if photo}
		<div class="flex h-full flex-col" data-testid="lightbox">
			<div class="flex items-center gap-3 px-4 py-2 text-sm">
				<span class="text-white/75 tabular-nums">{index + 1} / {gallery.photos.length}</span>
				<span class="flex-1"></span>
				<button
					type="button"
					class="px-2 text-2xl leading-none"
					onclick={close}
					aria-label={m.photos_close()}>×</button
				>
			</div>
			<div class="relative flex min-h-0 flex-1 items-center justify-center px-12">
				<img
					src={gallery.src(photo, 'large')}
					alt={photo.caption}
					class="max-h-full max-w-full object-contain"
				/>
				{#if gallery.photos.length > 1}
					<button
						type="button"
						class="absolute top-1/2 left-2 -translate-y-1/2 px-2 text-4xl"
						onclick={() => gallery.step(-1)}
						aria-label={m.photos_previous()}>‹</button
					>
					<button
						type="button"
						class="absolute top-1/2 right-2 -translate-y-1/2 px-2 text-4xl"
						onclick={() => gallery.step(1)}
						aria-label={m.photos_next()}>›</button
					>
				{/if}
			</div>
			<div class="flex flex-col gap-2 px-4 py-3 text-sm">
				{#if gallery.canEdit}
					<input
						class="rounded bg-white/10 px-2 py-1 text-white placeholder:text-white/50"
						value={photo.caption}
						maxlength="500"
						placeholder={m.photos_caption()}
						aria-label={m.photos_caption()}
						onchange={(e) => gallery.update(photo, { caption: e.currentTarget.value })}
					/>
				{:else if photo.caption}
					<p>{photo.caption}</p>
				{/if}
				<p class="text-xs text-white/65">{details}</p>
				<div class="flex flex-wrap items-center gap-3 text-xs">
					{#if gallery.canEdit}
						<button
							type="button"
							class="underline disabled:opacity-40"
							disabled={index === 0}
							onclick={() => gallery.move(photo, -1)}>{m.photos_move_earlier()}</button
						>
						<button
							type="button"
							class="underline disabled:opacity-40"
							disabled={index === gallery.photos.length - 1}
							onclick={() => gallery.move(photo, 1)}>{m.photos_move_later()}</button
						>
						{#if photo.pin}
							<button
								type="button"
								class="underline"
								onclick={() => gallery.update(photo, { unpin: true })}>{m.photos_unpin()}</button
							>
						{/if}
						{#if confirming}
							<button
								type="button"
								class="rounded bg-red-700 px-2 py-0.5"
								onclick={() => gallery.remove(photo)}>{m.photos_delete_confirm()}</button
							>
						{:else}
							<button type="button" class="underline" onclick={() => (confirming = true)}
								>{m.photos_delete()}</button
							>
						{/if}
					{:else if loggedIn}
						<ReportButton target={{ kind: 'photo', id: photo.id }} />
					{/if}
				</div>
			</div>
		</div>
	{/if}
</dialog>
