/**
 * Acts on a select's choice once it is made. On Windows and Linux, arrow
 * keys on a closed select fire change for every option passed, which would
 * add, publish or switch the language at the first press. A change that
 * comes from a key press is therefore only remembered, and acted on with
 * Enter or when the field is left. A change from the mouse, or from the
 * option popup that macOS opens instead, acts at once.
 *
 * Use as `use:choose={(value, select) => …}` instead of onchange.
 */
type Act = (value: string, select: HTMLSelectElement) => void;

export function choose(select: HTMLSelectElement, act: Act) {
	let browsing = false; // a key is being handled right now
	let pending: string | undefined;

	const commit = () => {
		if (pending === undefined) return;
		const v = pending;
		pending = undefined;
		act(v, select);
	};
	const keydown = (e: KeyboardEvent) => {
		if (e.key === 'Enter' && pending !== undefined) {
			e.preventDefault();
			commit();
			return;
		}
		// The change a key causes follows in the same task.
		browsing = true;
		setTimeout(() => (browsing = false));
	};
	const change = () => {
		if (browsing) pending = select.value;
		else {
			pending = undefined;
			act(select.value, select);
		}
	};
	select.addEventListener('keydown', keydown);
	select.addEventListener('change', change);
	select.addEventListener('blur', commit);
	return {
		update(next: Act) {
			act = next;
		},
		destroy() {
			select.removeEventListener('keydown', keydown);
			select.removeEventListener('change', change);
			select.removeEventListener('blur', commit);
		}
	};
}
