/** Stage colours on the journey map and profile, cycled. */
export const STAGE_COLORS = ['#a21caf', '#2563eb', '#0f766e', '#c2410c', '#4d7c0f', '#be123c'];

export const stageColor = (i: number) => STAGE_COLORS[i % STAGE_COLORS.length];

/** Colour map keyed like the profile runs (S0, S1 …). */
export const STAGE_RUN_COLORS = Object.fromEntries(STAGE_COLORS.map((c, i) => [`S${i}`, c]));
