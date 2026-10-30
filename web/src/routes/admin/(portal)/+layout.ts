import { redirect } from '@sveltejs/kit';
import type { LayoutLoad } from './$types';

// Moderators and admins only; the API checks the role again.
export const load: LayoutLoad = async ({ parent }) => {
	const { user } = await parent();
	if (!user || user.role === 'user') redirect(303, '/admin/login');
};
