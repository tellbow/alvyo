<script lang="ts">
	import { NativeSelect } from '#lib/components/ui/native-select/index.js';
	import { api } from '#lib/api/client.js';
	import type { components } from '#lib/api/schema.js';
	import { m } from '#lib/paraglide/messages.js';
	import { formProof } from '#lib/spam/proof.js';
	import Trap from '#lib/spam/Trap.svelte';

	type Report = components['schemas']['ReportInputBody'];

	let { target }: { target: Pick<Report, 'kind' | 'id' | 'username' | 'token'> } = $props();

	let open = $state(false);
	let reason = $state<Report['reason']>('spam');
	let note = $state('');
	let done = $state(false);
	let error = $state('');
	const proof = formProof();

	async function send(e: SubmitEvent) {
		e.preventDefault();
		error = '';
		const { response } = await api().POST('/reports', {
			body: { ...target, reason, note: note.trim() || undefined, ...(await proof.take(e)) }
		});
		if (response.ok) {
			done = true;
			open = false;
		} else {
			error = response.status === 429 ? m.community_rate() : m.error_generic();
		}
	}
</script>

{#if done}
	<span class="text-xs text-stone-500">{m.report_thanks()}</span>
{:else if open}
	<form
		method="post"
		onsubmit={send}
		class="flex w-full flex-col gap-1.5 rounded-md bg-stone-50 p-2 text-xs"
		data-testid="report-form"
	>
		<NativeSelect size="sm" bind:value={reason} aria-label={m.report_reason()}>
			<option value="spam">{m.report_reason_spam()}</option>
			<option value="offensive">{m.report_reason_offensive()}</option>
			<option value="dangerous">{m.report_reason_dangerous()}</option>
			<option value="other">{m.report_reason_other()}</option>
		</NativeSelect>
		<textarea
			bind:value={note}
			maxlength="1000"
			rows="2"
			placeholder={m.report_note()}
			aria-label={m.report_note()}
			class="rounded-md border border-stone-400 px-1 py-0.5"></textarea>
		<Trap />
		{#if error}<p role="alert" class="text-red-700 dark:text-red-400">{error}</p>{/if}
		<div class="flex gap-2">
			<button class="rounded bg-stone-800 px-2 py-0.5 text-stone-50">{m.report_send()}</button>
			<button type="button" class="underline" onclick={() => (open = false)}
				>{m.report_cancel()}</button
			>
		</div>
	</form>
{:else}
	<button
		type="button"
		class="text-xs text-stone-500 underline"
		onclick={() => {
			open = true;
			void proof.start();
		}}>{m.report()}</button
	>
{/if}
