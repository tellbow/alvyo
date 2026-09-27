import { describe, expect, it } from 'vitest';
import { candidates, type Candidate } from './candidates';

const all: Candidate[] = [
	{ kind: 'route', id: 'r1', title: 'Sargans – Weisstannen' },
	{ kind: 'route', id: 'r2', title: 'Elm–Linthal' },
	{ kind: 'journey', id: 'j1', title: 'Via Alpina' },
	{ kind: 'journey', id: 'j2', title: 'Via Alpina, Teil 2', owner: 'anna' },
	{ kind: 'route', id: 'j1', title: 'Via Alpina Etappe' } // same id, other kind
];

describe('candidates', () => {
	it('matches all words of the query in any case', () => {
		expect(candidates(all, new Set(), 'via TEIL').map((c) => c.id)).toEqual(['j2']);
		expect(candidates(all, new Set(), 'alpina').map((c) => c.id)).toEqual(['j1', 'j2', 'j1']);
	});

	it('leaves out what the collection has, by kind and id', () => {
		const got = candidates(all, new Set(['journey:j1']), 'alpina');
		expect(got.map((c) => `${c.kind}:${c.id}`)).toEqual(['journey:j2', 'route:j1']);
	});

	it('without a query: the first ones, at most the limit', () => {
		expect(candidates(all, new Set(), '', 2).map((c) => c.id)).toEqual(['r1', 'r2']);
	});
});
