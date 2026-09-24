<script lang="ts">
	import { resolve } from '$app/paths';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';
</script>

<Seo title="odysgeh – {m.seo_home_title()}" description={m.seo_home_description()} />

<main class="mx-auto mt-16 max-w-2xl px-4">
	<h1 class="text-4xl font-semibold tracking-tight">odysgeh</h1>
	<p class="mt-3 text-lg text-stone-600">{m.app_tagline()}</p>
	<div class="mt-8 flex gap-3">
		<a
			href={resolve('/plan')}
			class="rounded-md bg-emerald-700 px-4 py-2 text-white hover:bg-emerald-800"
		>
			{m.nav_plan()}
		</a>
		<a
			href={resolve('/discover')}
			class="rounded-md px-4 py-2 text-emerald-800 ring-1 ring-emerald-700 hover:bg-emerald-50"
		>
			{m.discover_title()}
		</a>
	</div>
	<ul class="mt-10 list-disc space-y-2 pl-5 text-stone-700">
		<li>{m.home_feature_plan()}</li>
		<li>{m.home_feature_journeys()}</li>
		<li>{m.home_feature_app()}</li>
		<li>{m.home_feature_discover()}</li>
	</ul>
</main>
