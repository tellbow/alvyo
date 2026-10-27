import type * as MapLibre from 'maplibre-gl';

/**
 * «Meinen Standort finden» as in Apple's and Google's maps: the dot shows
 * whenever the site may already use the location (the browser asks only
 * on a click), and a click moves the map there. MapLibre's own control
 * shows the dot only after a click, and moves the map with it.
 */
export class LocateControl implements MapLibre.IControl {
	#ml: typeof MapLibre;
	#label: string;
	#unavailable: string;
	#map?: MapLibre.Map;
	#container = document.createElement('div');
	#button = document.createElement('button');
	#dot?: MapLibre.Marker;
	#watch?: number;
	#at?: [number, number];
	#flyOnFix = false;

	constructor(ml: typeof MapLibre, label: string, unavailable: string) {
		this.#ml = ml;
		this.#label = label;
		this.#unavailable = unavailable;
	}

	onAdd(map: MapLibre.Map): HTMLElement {
		this.#map = map;
		this.#container.className = 'maplibregl-ctrl maplibregl-ctrl-group';
		this.#button.type = 'button';
		this.#button.className = 'maplibregl-ctrl-geolocate';
		const icon = document.createElement('span');
		icon.className = 'maplibregl-ctrl-icon';
		icon.setAttribute('aria-hidden', 'true');
		this.#button.append(icon);
		this.#title(this.#label);
		this.#button.addEventListener('click', () => this.#locate());
		this.#container.append(this.#button);
		const dot = document.createElement('div');
		dot.className = 'maplibregl-user-location-dot';
		this.#dot = new this.#ml.Marker({ element: dot });
		if (!('geolocation' in navigator)) {
			this.#button.disabled = true;
			this.#title(this.#unavailable);
			return this.#container;
		}
		navigator.permissions
			?.query({ name: 'geolocation' })
			.then((s) => {
				if (s.state === 'granted') this.#follow();
			})
			.catch(() => {});
		return this.#container;
	}

	onRemove(): void {
		if (this.#watch !== undefined) navigator.geolocation.clearWatch(this.#watch);
		this.#dot?.remove();
		this.#container.remove();
		this.#map = undefined;
	}

	#title(text: string) {
		this.#button.title = text;
		this.#button.setAttribute('aria-label', text);
	}

	#locate() {
		if (this.#at) return this.#fly();
		this.#flyOnFix = true;
		this.#button.classList.add('maplibregl-ctrl-geolocate-waiting');
		this.#follow();
	}

	/** Moves the dot with each position. */
	#follow() {
		if (this.#watch !== undefined) return;
		this.#watch = navigator.geolocation.watchPosition(
			(p) => {
				if (!this.#map) return;
				this.#at = [p.coords.longitude, p.coords.latitude];
				this.#dot?.setLngLat(this.#at).addTo(this.#map);
				this.#button.classList.remove(
					'maplibregl-ctrl-geolocate-waiting',
					'maplibregl-ctrl-geolocate-active-error'
				);
				this.#title(this.#label);
				if (this.#flyOnFix) {
					this.#flyOnFix = false;
					this.#fly();
				}
			},
			(e) => {
				this.#button.classList.remove('maplibregl-ctrl-geolocate-waiting');
				if (this.#flyOnFix || e.code === e.PERMISSION_DENIED) {
					this.#flyOnFix = false;
					this.#button.classList.add('maplibregl-ctrl-geolocate-active-error');
					this.#title(this.#unavailable);
				}
				// Refused: a click asks again (or the browser says it may not).
				if (e.code === e.PERMISSION_DENIED) {
					if (this.#watch !== undefined) navigator.geolocation.clearWatch(this.#watch);
					this.#watch = undefined;
					this.#at = undefined;
					this.#dot?.remove();
				}
			},
			{ enableHighAccuracy: true }
		);
	}

	#fly() {
		if (!this.#map || !this.#at) return;
		this.#map.flyTo({ center: this.#at, zoom: Math.max(this.#map.getZoom(), 15) });
	}
}
