/**
 * Focuses the element when it appears: a confirmation that replaces the
 * button pressed keeps the keyboard where it was, not back at the page's
 * start. Use as `use:focused`.
 */
export function focused(node: HTMLElement) {
	node.focus();
}
