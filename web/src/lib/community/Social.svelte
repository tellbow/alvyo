<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api, type Me } from '$lib/api/client';
	import type { components } from '$lib/api/schema';
	import { m } from '$lib/paraglide/messages';
	import { intlLocale } from '$lib/util/locale';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import ReportButton from './ReportButton.svelte';

	type Social = components['schemas']['SocialBody'];
	type Comment = Social['comments'][number];

	let {
		kind,
		id,
		token,
		user
	}: {
		kind: 'routes' | 'journeys';
		id: string;
		/** Share token of an unlisted item. */
		token?: string;
		user: Me | null;
	} = $props();

	const hydrated = new Hydrated();
	let social = $state<Social>();
	let text = $state('');
	let busy = $state(false);
	let error = $state('');
	// The comment being replied to or edited, and the text typed for it.
	let replyTo = $state<string>();
	let editing = $state<string>();
	let draft = $state('');

	/** Comments with their replies below them; replies whose comment is not shown are left out. */
	const threads = $derived.by(() => {
		const all = social?.comments ?? [];
		return all
			.filter((c) => !c.parent_id)
			.map((c) => ({ comment: c, replies: all.filter((r) => r.parent_id === c.id) }));
	});

	const when = $derived(
		new Intl.DateTimeFormat(intlLocale(), {
			dateStyle: 'medium',
			timeStyle: 'short',
			timeZone: 'Europe/Zurich'
		})
	);

	// Routes and journeys have the same endpoints; the paths differ only in
	// the first segment.
	const at = <S extends string>(suffix: S) => `/${kind}/{id}${suffix}` as `/routes/{id}${S}`;
	const params = () => ({ path: { id }, query: token ? { t: token } : {} });

	async function run(call: Promise<{ data?: Social; response: Response }>) {
		busy = true;
		error = '';
		const { data, response } = await call;
		busy = false;
		if (data) social = data;
		else error = response.status === 429 ? m.community_rate() : m.error_generic();
		return !!data;
	}

	function like() {
		return run(
			social?.liked
				? api().DELETE(at('/like'), { params: params() })
				: api().PUT(at('/like'), { params: params() })
		);
	}

	async function post(e: SubmitEvent) {
		e.preventDefault();
		if (await run(api().POST(at('/comments'), { params: params(), body: { body: text.trim() } }))) {
			text = '';
		}
	}

	/** Opens the reply field of a thread (replies are one level deep). */
	function startReply(thread: string) {
		replyTo = thread;
		editing = undefined;
		draft = '';
	}

	function startEdit(c: Comment) {
		editing = c.id;
		replyTo = undefined;
		draft = c.body;
	}

	async function reply(e: SubmitEvent, parent: string) {
		e.preventDefault();
		const body = { body: draft.trim(), parent_id: parent };
		if (await run(api().POST(at('/comments'), { params: params(), body }))) replyTo = undefined;
	}

	async function saveEdit(e: SubmitEvent, comment: string) {
		e.preventDefault();
		const ok = await run(
			api().PATCH(at('/comments/{comment}'), {
				params: { path: { id, comment }, query: token ? { t: token } : {} },
				body: { body: draft.trim() }
			})
		);
		if (ok) editing = undefined;
	}

	function remove(comment: string) {
		return run(
			api().DELETE(at('/comments/{comment}'), {
				params: { path: { id, comment }, query: token ? { t: token } : {} }
			})
		);
	}

	function toggle(on: boolean) {
		return run(
			api().PATCH(at('/social'), { params: { path: { id } }, body: { comments_enabled: on } })
		);
	}

	onMount(() => void run(api().GET(at('/social'), { params: params() })));
</script>

{#snippet item(c: Comment, thread: string)}
	<div class="rounded-md bg-stone-50 px-2 py-1.5" data-testid="comment">
		<p class="text-xs text-stone-500">
			<span class="font-medium text-stone-700">{c.author_name}</span>
			@{c.author_username} · {when.format(new Date(c.created_at))}
			{#if c.edited_at}· {m.community_edited()}{/if}
		</p>
		{#if editing === c.id}
			<form method="post" onsubmit={(e) => saveEdit(e, c.id)} class="mt-1 flex flex-col gap-1.5">
				<textarea
					bind:value={draft}
					required
					maxlength="2000"
					rows="3"
					aria-label={m.community_edit()}
					class="rounded-md border border-stone-300 px-2 py-1"></textarea>
				<div class="flex gap-2">
					<button
						disabled={busy || !draft.trim()}
						class="rounded-md bg-emerald-700 px-3 py-1 text-white hover:bg-emerald-800 disabled:opacity-50"
						>{m.save()}</button
					>
					<button type="button" class="underline" onclick={() => (editing = undefined)}
						>{m.report_cancel()}</button
					>
				</div>
			</form>
		{:else}
			<p class="whitespace-pre-line">{c.body}</p>
		{/if}
		<div class="mt-1 flex flex-wrap items-center gap-3 text-xs text-stone-500">
			{#if social?.can_comment && editing !== c.id}
				<button type="button" class="underline" onclick={() => startReply(thread)}
					>{m.community_reply()}</button
				>
			{/if}
			{#if c.can_edit && social?.comments_enabled && editing !== c.id}
				<button type="button" class="underline" onclick={() => startEdit(c)}
					>{m.community_edit()}</button
				>
			{/if}
			{#if c.can_delete}
				<button type="button" class="underline" onclick={() => remove(c.id)}
					>{m.community_comment_delete()}</button
				>
			{/if}
			{#if user && c.author_username !== user.username}
				<ReportButton target={{ kind: 'comment', id: c.id }} />
			{/if}
		</div>
	</div>
{/snippet}

<section class="flex flex-col gap-3 border-t border-stone-200 pt-3 text-sm" data-testid="social">
	{#if social}
		<div class="flex flex-wrap items-center gap-3">
			<button
				type="button"
				class="rounded-full px-2.5 py-0.5 ring-1 ring-stone-300 enabled:hover:bg-rose-50 disabled:opacity-60"
				class:text-rose-700={social.liked}
				aria-pressed={social.liked}
				disabled={!user || busy}
				title={user ? undefined : m.community_login_to_like()}
				onclick={like}
				data-testid="like"
			>
				{social.liked ? '♥' : '♡'}
				{m.community_likes({ n: social.likes })}
			</button>
			<span class="text-stone-600">{m.community_comments({ n: social.comments.length })}</span>
			{#if social.can_moderate}
				<label class="ml-auto flex items-center gap-1 text-xs text-stone-600">
					<input
						type="checkbox"
						checked={social.comments_enabled}
						onchange={(e) => toggle(e.currentTarget.checked)}
					/>
					{m.community_comments_allowed()}
				</label>
			{/if}
		</div>

		{#if !social.comments_enabled}
			<p class="text-xs text-stone-500">{m.community_comments_off()}</p>
		{/if}

		{#if threads.length > 0}
			<ol class="flex flex-col gap-2" data-testid="comments">
				{#each threads as { comment: c, replies } (c.id)}
					<li class="flex flex-col gap-1">
						{@render item(c, c.id)}
						{#if replies.length > 0}
							<ol
								class="ml-4 flex flex-col gap-1 border-l-2 border-stone-200 pl-2"
								data-testid="replies"
							>
								{#each replies as r (r.id)}
									<li>{@render item(r, c.id)}</li>
								{/each}
							</ol>
						{/if}
						{#if replyTo === c.id}
							<form
								method="post"
								onsubmit={(e) => reply(e, c.id)}
								class="ml-4 flex flex-col gap-1.5 pl-2"
							>
								<textarea
									bind:value={draft}
									required
									maxlength="2000"
									rows="2"
									placeholder={m.community_reply_placeholder()}
									aria-label={m.community_reply_placeholder()}
									class="rounded-md border border-stone-300 px-2 py-1"></textarea>
								<div class="flex gap-2">
									<button
										disabled={busy || !draft.trim()}
										class="rounded-md bg-emerald-700 px-3 py-1 text-white hover:bg-emerald-800 disabled:opacity-50"
										>{m.community_reply()}</button
									>
									<button type="button" class="underline" onclick={() => (replyTo = undefined)}
										>{m.report_cancel()}</button
									>
								</div>
							</form>
						{/if}
					</li>
				{/each}
			</ol>
		{/if}

		{#if social.can_comment}
			<form method="post" onsubmit={post} class="flex flex-col gap-1.5">
				<textarea
					bind:value={text}
					required
					maxlength="2000"
					rows="3"
					placeholder={m.community_comment_placeholder()}
					aria-label={m.community_comment_placeholder()}
					class="rounded-md border border-stone-300 px-2 py-1"></textarea>
				<button
					disabled={!hydrated.value || busy || !text.trim()}
					class="self-start rounded-md bg-emerald-700 px-3 py-1 text-white hover:bg-emerald-800 disabled:opacity-50"
					>{m.community_comment_send()}</button
				>
			</form>
		{:else if !user && social.comments_enabled}
			<p class="text-xs text-stone-500">
				<!-- resolve() gives the path; only the query is added -->
				<!-- eslint-disable svelte/no-navigation-without-resolve -->
				<a
					href={`${resolve('/login')}?redirect=${encodeURIComponent(page.url.pathname + page.url.search)}`}
					class="underline">{m.community_login_to_comment()}</a
				>
				<!-- eslint-enable svelte/no-navigation-without-resolve -->
			</p>
		{:else if user && !user.email_verified && social.comments_enabled}
			<p class="text-xs text-stone-500">{m.community_verify_to_comment()}</p>
		{/if}

		{#if error}<p role="alert" class="text-xs text-red-700">{error}</p>{/if}

		{#if user && !social.can_moderate}
			<div>
				<ReportButton target={{ kind: kind === 'routes' ? 'route' : 'journey', id, token }} />
			</div>
		{/if}
	{/if}
</section>
