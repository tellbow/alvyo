<script lang="ts">
	import { primaryButtonSmall } from '#lib/components/actions.js';
	import { page } from '$app/state';
	import { api } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import { pageScreenshot } from './screenshot';

	// «Fehler melden» on every page for signed-in people: what is open and a
	// screenshot (taken before the dialog opens) go with the description to
	// the API, which opens an issue on GitHub.
	let dialog = $state<HTMLDialogElement>();
	let shot = $state<string>();
	let withShot = $state(true);
	let text = $state('');
	let status = $state<'idle' | 'taking' | 'sending' | 'sent' | 'failed' | 'busy'>('idle');
	let version = '';

	/** The address without a share token: the issue is read by others. */
	const place = () => {
		const u = new URL(page.url.href);
		u.searchParams.delete('t');
		return u.pathname + u.search;
	};

	async function open() {
		status = 'taking';
		shot = await pageScreenshot();
		withShot = !!shot;
		status = 'idle';
		text = '';
		dialog?.showModal();
		if (!version) {
			const { data } = await api().GET('/version');
			version = data?.version ?? '';
		}
	}

	async function send(e: SubmitEvent) {
		e.preventDefault();
		status = 'sending';
		const { response } = await api().POST('/bug-reports', {
			body: {
				description: text.trim(),
				place: place(),
				version: `${version} · ${navigator.userAgent}`.slice(0, 60),
				platform: 'web',
				...(withShot && shot ? { screenshot: shot.slice(shot.indexOf(',') + 1) } : {})
			}
		});
		status = response.ok ? 'sent' : response.status === 429 ? 'busy' : 'failed';
	}
</script>

<button
	type="button"
	data-bug-report
	class="ml-auto flex size-10 shrink-0 items-center justify-center rounded-full border border-stone-300 bg-surface text-stone-900 hover:bg-stone-100 xl:ml-0 print:hidden"
	aria-label={m.bug_open()}
	title={m.bug_open()}
	disabled={status === 'taking'}
	onclick={open}
	data-testid="bug-open"
>
	<svg
		width="18"
		height="18"
		viewBox="0 0 24 24"
		fill="none"
		stroke="currentColor"
		stroke-width="2"
		aria-hidden="true"
		><path
			d="M8 2l1.9 1.9M16 2l-1.9 1.9M9 7.1V6a3 3 0 1 1 6 0v1.1M12 20v-9M6.5 13H3M21 13h-3.5M5 20l2.5-2M19 20l-2.5-2M5 6l2.4 2.1M19 6l-2.4 2.1"
		/><path d="M12 20c-3.3 0-6-2.7-6-6v-3a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v3c0 3.3-2.7 6-6 6z" /></svg
	>
</button>

<dialog
	bind:this={dialog}
	data-bug-report
	class="m-auto w-[min(32rem,calc(100vw-2rem))] rounded-lg bg-surface p-0 text-stone-900 shadow-xl backdrop:bg-black/40"
	aria-label={m.bug_title()}
	data-testid="bug-dialog"
>
	{#if status === 'sent'}
		<div class="flex flex-col gap-3 p-4 text-sm">
			<p data-testid="bug-sent">{m.bug_sent()}</p>
			<button
				type="button"
				class="self-end rounded-md px-3 py-1.5 ring-1 ring-stone-300"
				onclick={() => dialog?.close()}>{m.place_close()}</button
			>
		</div>
	{:else}
		<form class="flex flex-col gap-3 p-4 text-sm" onsubmit={send}>
			<h2 class="text-base font-semibold">{m.bug_title()}</h2>
			<label class="flex flex-col gap-1">
				<span>{m.bug_what()}</span>
				<textarea
					bind:value={text}
					required
					maxlength="4000"
					rows="5"
					class="rounded-md px-2 py-1.5 ring-1 ring-stone-300"
					data-testid="bug-text"></textarea>
			</label>
			{#if shot}
				<label class="flex items-start gap-2">
					<input type="checkbox" bind:checked={withShot} class="mt-1" data-testid="bug-with-shot" />
					<span class="flex flex-col gap-1">
						{m.bug_with_screenshot()}
						<img
							src={shot}
							alt={m.bug_screenshot_alt()}
							class="max-h-40 w-fit rounded ring-1 ring-stone-200"
						/>
					</span>
				</label>
			{/if}
			<p class="text-xs text-stone-500">{m.bug_privacy({ place: place() })}</p>
			{#if status === 'failed'}<p class="text-red-700 dark:text-red-400" role="alert">
					{m.bug_failed()}
				</p>{/if}
			{#if status === 'busy'}<p class="text-red-700 dark:text-red-400" role="alert">
					{m.bug_busy()}
				</p>{/if}
			<div class="flex justify-end gap-2">
				<button
					type="button"
					class="rounded-md px-3 py-1.5 ring-1 ring-stone-300"
					onclick={() => dialog?.close()}>{m.report_cancel()}</button
				>
				<button
					type="submit"
					class={primaryButtonSmall}
					disabled={status === 'sending' || !text.trim()}
					data-testid="bug-send">{m.bug_send()}</button
				>
			</div>
		</form>
	{/if}
</dialog>
