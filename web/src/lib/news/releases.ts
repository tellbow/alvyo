import { m } from '#lib/paraglide/messages.js';

/**
 * «Was ist neu»: one line per release for the people who use Alvyo, newest
 * first, in their language (the release table in docs/plan.md is the
 * developers' account). The `release` skill adds the line of a new version.
 */
export const releases: { version: string; date: string; text: () => string }[] = [
	{ version: '1.9.0', date: '2026-10-20', text: m.news_1_9_0 },
	{ version: '1.8.0', date: '2026-10-19', text: m.news_1_8_0 },
	{ version: '1.7.1', date: '2026-10-19', text: m.news_1_7_1 },
	{ version: '1.7.0', date: '2026-10-19', text: m.news_1_7_0 },
	{ version: '1.6.0', date: '2026-10-19', text: m.news_1_6_0 },
	{ version: '1.5.0', date: '2026-10-18', text: m.news_1_5_0 },
	{ version: '1.4.0', date: '2026-10-18', text: m.news_1_4_0 },
	{ version: '1.3.0', date: '2026-10-18', text: m.news_1_3_0 },
	{ version: '1.2.0', date: '2026-10-16', text: m.news_1_2_0 },
	{ version: '1.1.0', date: '2026-10-15', text: m.news_1_1_0 },
	{ version: '1.0.0', date: '2026-10-15', text: m.news_1_0_0 },
	{ version: '0.34.0', date: '2026-10-14', text: m.news_0_34_0 },
	{ version: '0.33.0', date: '2026-10-10', text: m.news_0_33_0 },
	{ version: '0.32.0', date: '2026-10-10', text: m.news_0_32_0 },
	{ version: '0.31.0', date: '2026-10-09', text: m.news_0_31_0 },
	{ version: '0.30.0', date: '2026-10-08', text: m.news_0_30_0 },
	{ version: '0.29.1', date: '2026-10-07', text: m.news_0_29_1 },
	{ version: '0.29.0', date: '2026-10-07', text: m.news_0_29_0 },
	{ version: '0.28.0', date: '2026-10-07', text: m.news_0_28_0 },
	{ version: '0.27.0', date: '2026-10-07', text: m.news_0_27_0 }
];
