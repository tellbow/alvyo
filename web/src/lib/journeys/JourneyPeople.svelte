<script lang="ts">
	import Avatar from '#lib/components/Avatar.svelte';
	import { api, type JourneyStage, type Person } from '#lib/api/client.js';
	import FriendOptions from '#lib/community/FriendOptions.svelte';
	import { m } from '#lib/paraglide/messages.js';
	import { personName } from './people';

	// Who comes along, and on which stages: seen by the owner and the people
	// the journey is shared with (not the public); the owner adds and
	// removes people (someone without access is invited as a viewer), editors
	// change their stages. `people` is given back for the stage cards.
	let {
		id,
		stages,
		isOwner,
		canEdit,
		people = $bindable([])
	}: {
		id: string;
		stages: JourneyStage[];
		isOwner: boolean;
		canEdit: boolean;
		people?: Person[];
	} = $props();

	let shown = $state(false); // false while loading or not ours to see
	let who = $state('');
	let error = $state('');
	let busy = $state(false);

	$effect(() => {
		void id;
		api()
			.GET('/journeys/{id}/people', { params: { path: { id } } })
			.then(({ data }) => {
				people = data?.people ?? [];
				shown = !!data;
			});
	});

	async function run(req: Promise<{ data?: { people: Person[] }; response: Response }>) {
		busy = true;
		error = '';
		const { data, response } = await req;
		busy = false;
		if (data) {
			people = data.people;
			return true;
		}
		error =
			response.status === 422
				? m.people_unknown()
				: response.status === 403
					? m.people_verify()
					: m.people_failed();
		return false;
	}

	async function add(e: SubmitEvent) {
		e.preventDefault();
		const w = who.trim();
		if (!w) return;
		const body = w.includes('@') ? { email: w } : { username: w.replace(/^@/, '') };
		if (await run(api().POST('/journeys/{id}/people', { params: { path: { id } }, body })))
			who = '';
	}

	function toggle(p: Person, stage: string) {
		const next = p.stages.includes(stage)
			? p.stages.filter((s) => s !== stage)
			: stages.filter((s) => s.id === stage || p.stages.includes(s.id)).map((s) => s.id);
		run(
			api().PUT('/journeys/{id}/people/{person}', {
				params: { path: { id, person: p.id } },
				body: { stages: next }
			})
		);
	}

	function remove(p: Person) {
		run(api().DELETE('/journeys/{id}/people/{person}', { params: { path: { id, person: p.id } } }));
	}
</script>

{#if shown && (people.length > 0 || isOwner)}
	<section class="flex flex-col gap-2 text-sm" data-testid="journey-people">
		<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">{m.people_title()}</h3>
		{#if people.length === 0}
			<p class="text-xs text-stone-500">{m.people_none()}</p>
		{/if}
		<ul class="flex flex-col gap-2">
			{#each people as p (p.id)}
				<li class="flex flex-col gap-1" data-testid="person">
					<div class="flex items-center gap-2">
						<Avatar id={p.avatar} class="size-7" />
						<span class="font-medium">{personName(p)}</span>
						{#if p.username && p.display_name}<span class="text-xs text-stone-500"
								>@{p.username}</span
							>{/if}
						{#if isOwner}
							<button
								type="button"
								class="ml-auto text-xs underline"
								disabled={busy}
								onclick={() => remove(p)}>{m.people_remove()}</button
							>
						{/if}
					</div>
					<div
						class="flex flex-wrap gap-1"
						role="group"
						aria-label={m.people_stages({ name: personName(p) })}
					>
						{#each stages as s, i (s.id)}
							{@const on = p.stages.includes(s.id)}
							{#if canEdit}
								<button
									type="button"
									class="rounded-full px-2 py-0.5 text-xs ring-1 ring-stone-300 {on
										? 'bg-accent text-on-accent ring-0'
										: 'hover:bg-stone-100'}"
									aria-pressed={on}
									disabled={busy}
									onclick={() => toggle(p, s.id)}>{i + 1}</button
								>
							{:else if on}
								<span class="rounded-full px-2 py-0.5 text-xs ring-1 ring-stone-300">{i + 1}</span>
							{/if}
						{/each}
					</div>
				</li>
			{/each}
		</ul>
		{#if isOwner}
			<form class="flex gap-2" onsubmit={add}>
				<input
					bind:value={who}
					class="min-w-0 flex-1 rounded-md px-2 py-1 ring-1 ring-stone-300"
					placeholder={m.people_who()}
					aria-label={m.people_who()}
					autocomplete="off"
					list="people-friends"
					data-testid="people-who"
				/>
				<FriendOptions id="people-friends" />
				<button
					type="submit"
					class="rounded-md px-3 py-1 ring-1 ring-stone-300"
					disabled={busy || !who.trim()}
					data-testid="people-add">{m.people_add()}</button
				>
			</form>
			<p class="text-xs text-stone-500">{m.people_hint()}</p>
		{/if}
		{#if error}<p class="text-xs text-red-700 dark:text-red-400" role="alert">{error}</p>{/if}
	</section>
{/if}
