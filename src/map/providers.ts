// Map imagery sources. Only sources whose terms allow this use are listed; each one shows
// its required attribution on the map. See README.md ("Kaartdiensten") for the terms.

export interface MapProvider {
  id: string;
  label: string;
  url: string;
  attribution: string;
  /** Highest zoom level the server delivers; Leaflet enlarges tiles beyond it. */
  maxNativeZoom: number;
  /** Shown under the selector. */
  note: string;
  available: boolean;
}

const arcgisKey = import.meta.env.VITE_ARCGIS_API_KEY?.trim() ?? '';

const PDOK_ATTRIBUTION =
  'Luchtfoto © <a href="https://www.beeldmateriaal.nl" target="_blank" rel="noreferrer">Beeldmateriaal Nederland</a> ' +
  'via <a href="https://www.pdok.nl" target="_blank" rel="noreferrer">PDOK</a> ' +
  '(<a href="https://creativecommons.org/licenses/by/4.0/deed.nl" target="_blank" rel="noreferrer">CC BY 4.0</a>)';

export const MAP_PROVIDERS: MapProvider[] = [
  {
    id: 'pdok-hr',
    label: 'Luchtfoto Nederland, 8 cm (PDOK)',
    url: 'https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0/Actueel_orthoHR/EPSG:3857/{z}/{x}/{y}.jpeg',
    attribution: PDOK_ATTRIBUTION,
    maxNativeZoom: 21,
    note: 'Open data van de overheid (CC BY 4.0), geen sleutel nodig. Alleen Nederland.',
    available: true,
  },
  {
    id: 'pdok-25',
    label: 'Luchtfoto Nederland, 25 cm (PDOK, sneller)',
    url: 'https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0/Actueel_ortho25/EPSG:3857/{z}/{x}/{y}.jpeg',
    attribution: PDOK_ATTRIBUTION,
    maxNativeZoom: 19,
    note: 'Zelfde bron in lagere resolutie. Handig bij een trage verbinding.',
    available: true,
  },
  {
    id: 'esri',
    label: 'Satelliet wereldwijd (Esri, eigen sleutel)',
    url: `https://ibasemaps-api.arcgis.com/arcgis/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}?token=${encodeURIComponent(arcgisKey)}`,
    attribution:
      'Powered by <a href="https://www.esri.com" target="_blank" rel="noreferrer">Esri</a> | Esri, Maxar, Earthstar Geographics, and the GIS User Community',
    maxNativeZoom: 19,
    note: arcgisKey
      ? 'ArcGIS Location Platform met jouw sleutel uit .env.local.'
      : 'Niet beschikbaar: zet VITE_ARCGIS_API_KEY in .env.local (zie README).',
    available: arcgisKey !== '',
  },
  {
    id: 'osm',
    label: 'Stratenkaart (OpenStreetMap)',
    url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a>-bijdragers',
    maxNativeZoom: 19,
    note: 'Geen luchtfoto. Alleen voor licht gebruik (tegelbeleid van OpenStreetMap).',
    available: true,
  },
];

export const DEFAULT_PROVIDER_ID = 'pdok-hr';
