import { m } from '#lib/paraglide/messages.js';

/** A data source on the about page: what we use, and its terms. */
export type Source = { text: () => string; terms?: { label: string; href: string } };

const OGD = { label: 'opendata.swiss', href: 'https://opendata.swiss/en/terms-of-use' };

/** Every outside data source Alvyo shows; NOTICE and docs/licensing.md list the same. */
export const sources: Source[] = [
	{
		text: m.about_src_swisstopo,
		terms: {
			label: 'OGD, © swisstopo',
			href: 'https://www.swisstopo.admin.ch/en/terms-of-use-free-geodata-and-geoservices'
		}
	},
	{ text: m.about_src_astra, terms: OGD },
	{ text: m.about_src_bafu, terms: OGD },
	{ text: m.about_src_vbs, terms: OGD },
	{
		text: m.about_src_meteo,
		terms: { label: 'CC BY 4.0', href: 'https://opendatadocs.meteoswiss.ch/general/terms-of-use' }
	},
	{
		text: m.about_src_copernicus,
		terms: { label: 'CLMS data policy', href: 'https://land.copernicus.eu/en/data-policy' }
	},
	{
		text: m.about_src_transport,
		terms: {
			label: 'opentransportdata.swiss',
			href: 'https://opentransportdata.swiss/en/terms-of-use/'
		}
	},
	{ text: m.about_src_bav, terms: OGD },
	{
		text: m.about_src_osm,
		terms: { label: 'ODbL', href: 'https://www.openstreetmap.org/copyright' }
	},
	{
		text: m.about_src_mapterhorn,
		terms: { label: 'mapterhorn.com/attribution', href: 'https://mapterhorn.com/attribution' }
	},
	{
		text: m.about_src_terrain,
		terms: {
			label: 'Mapzen',
			href: 'https://github.com/tilezen/joerd/blob/master/docs/attribution.md'
		}
	},
	{ text: m.about_src_hikingtime }
];
