import { error } from '@sveltejs/kit';
import { adminApi } from '#lib/api/client.js';
import type { PageLoad } from './$types';

// «Übersicht»: what is waiting and this week, from the other pages' answers.
export const load: PageLoad = async ({ fetch, url }) => {
	const api = adminApi(fetch, url.origin);
	const [reports, system, jobs, stats] = await Promise.all([
		api.GET('/moderation/reports'),
		api.GET('/admin/system'),
		api.GET('/admin/jobs'),
		api.GET('/admin/stats')
	]);
	if (!reports.data || !system.data || !jobs.data || !stats.data)
		error(reports.response.status === 403 ? 403 : 500);
	return {
		reports: reports.data.reports.length,
		down: system.data.services.filter((s) => !s.up).map((s) => s.name),
		failed: jobs.data.jobs
			.filter((j) => j.last_start && !j.running && !j.last_finished)
			.map((j) => j.name),
		week: stats.data.weeks[0]
	};
};
