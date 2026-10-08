import { ROUTE_COLOR } from '$lib/planner/colors';
/**
 * Stage colours on the journey map and profile, cycled; in an order where
 * neighbours differ also for red-green colour blindness (colors.spec.ts).
 */
export const STAGE_COLORS = [ROUTE_COLOR, '#4d7c0f', '#2563eb', '#c2410c', '#0f766e', '#be123c'];

export const stageColor = (i: number) => STAGE_COLORS[i % STAGE_COLORS.length];

/** Colour map keyed like the profile runs (S0, S1 …). */
export const STAGE_RUN_COLORS = Object.fromEntries(STAGE_COLORS.map((c, i) => [`S${i}`, c]));
