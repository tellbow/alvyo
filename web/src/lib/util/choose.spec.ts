import { describe, expect, it, vi } from 'vitest';
import { choose } from './choose';

/** A stand-in for a select: events and a value. */
function fakeSelect() {
	const el = new EventTarget() as EventTarget & { value: string };
	el.value = '';
	const key = (k: string) => {
		const e = new Event('keydown', { cancelable: true }) as Event & { key: string };
		e.key = k;
		el.dispatchEvent(e);
	};
	const pick = (v: string) => {
		el.value = v;
		el.dispatchEvent(new Event('change'));
	};
	return { el, key, pick };
}

describe('choose', () => {
	it('acts on a choice with the mouse at once', () => {
		const { el, pick } = fakeSelect();
		const act = vi.fn();
		choose(el as unknown as HTMLSelectElement, act);
		pick('a');
		expect(act).toHaveBeenCalledExactlyOnceWith('a', el);
	});

	it('waits for Enter when the arrows move through the options', async () => {
		const { el, key, pick } = fakeSelect();
		const act = vi.fn();
		choose(el as unknown as HTMLSelectElement, act);
		// Windows and Linux: each arrow changes the value in the same task.
		key('ArrowDown');
		pick('a');
		await new Promise((r) => setTimeout(r));
		key('ArrowDown');
		pick('b');
		await new Promise((r) => setTimeout(r));
		expect(act).not.toHaveBeenCalled();
		key('Enter');
		expect(act).toHaveBeenCalledExactlyOnceWith('b', el);
		key('Enter'); // nothing pending: no second action
		expect(act).toHaveBeenCalledOnce();
	});

	it('acts on the option browsed to when the field is left', async () => {
		const { el, key, pick } = fakeSelect();
		const act = vi.fn();
		choose(el as unknown as HTMLSelectElement, act);
		key('ArrowDown');
		pick('a');
		await new Promise((r) => setTimeout(r));
		el.dispatchEvent(new Event('blur'));
		expect(act).toHaveBeenCalledExactlyOnceWith('a', el);
		el.dispatchEvent(new Event('blur'));
		expect(act).toHaveBeenCalledOnce();
	});

	it('acts on a choice in the macOS popup, which comes after the key', async () => {
		const { el, key, pick } = fakeSelect();
		const act = vi.fn();
		choose(el as unknown as HTMLSelectElement, act);
		key('ArrowDown'); // opens the popup
		await new Promise((r) => setTimeout(r, 5));
		pick('b'); // chosen there with Enter or a click
		expect(act).toHaveBeenCalledExactlyOnceWith('b', el);
	});
});
