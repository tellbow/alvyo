<script lang="ts">
	import * as AlertDialog from '#lib/components/ui/alert-dialog/index.js';
	import { m } from '#lib/paraglide/messages.js';

	// Asks before something that cannot be taken back (feedback issue 56).
	let {
		open = $bindable(false),
		question,
		action,
		onconfirm,
		testid,
		actionTestid
	}: {
		open?: boolean;
		question: string;
		/** The button that does it, e.g. «Löschen». */
		action: string;
		onconfirm: () => void;
		testid?: string;
		actionTestid?: string;
	} = $props();
</script>

<AlertDialog.Root bind:open>
	<AlertDialog.Content data-testid={testid}>
		<AlertDialog.Header>
			<AlertDialog.Title class="text-base font-medium">{question}</AlertDialog.Title>
		</AlertDialog.Header>
		<AlertDialog.Footer>
			<AlertDialog.Cancel>{m.collection_remove_cancel()}</AlertDialog.Cancel>
			<AlertDialog.Action
				class="bg-red-700 text-white hover:bg-red-800"
				data-testid={actionTestid}
				onclick={() => {
					open = false;
					onconfirm();
				}}>{action}</AlertDialog.Action
			>
		</AlertDialog.Footer>
	</AlertDialog.Content>
</AlertDialog.Root>
