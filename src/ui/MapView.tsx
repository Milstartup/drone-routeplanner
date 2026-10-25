// The map: imagery, field boundary, route, photo positions and the simulated drone.
import L from 'leaflet';
import { useEffect, useMemo, useRef } from 'react';
import { MapContainer, Marker, Polygon, Polyline, TileLayer, useMap, useMapEvents } from 'react-leaflet';
import type { PlanAnalysis } from '../core/analysis';
import { groundFootprint } from '../core/camera';
import { DEG, localProjection } from '../core/geo';
import type { DroneState } from '../core/timeline';
import type { LatLng, PhotoPoint, Plan, RouteLeg } from '../core/types';
import type { MapProvider } from '../map/providers';
import type { PointTarget } from './planReducer';

export type Tool = 'none' | 'add' | 'home';

export interface FocusRequest {
  seq: number;
  points: LatLng[];
}

interface MapViewProps {
  plan: Plan;
  analysis: PlanAnalysis;
  provider: MapProvider;
  tool: Tool;
  selectedId: string | null;
  drone: DroneState | null;
  photosTaken: number;
  simulating: boolean;
  focus: FocusRequest | null;
  onMapClick(at: LatLng): void;
  onPointMove(target: PointTarget, id: string, at: LatLng): void;
  onPointInsert(target: PointTarget, index: number, at: LatLng): void;
  onPointSelect(target: PointTarget, id: string): void;
  onHomeMove(at: LatLng): void;
  onDragStart(): void;
}

const NL_CENTER: [number, number] = [52.25, 5.4];

const iconCache = new Map<string, L.DivIcon>();
function pointIcon(kind: 'boundary' | 'route' | 'home' | 'mid' | 'label', label: string, selected = false): L.DivIcon {
  const key = `${kind}|${label}|${selected}`;
  let icon = iconCache.get(key);
  if (!icon) {
    const size = kind === 'mid' ? 16 : kind === 'home' ? 30 : kind === 'label' ? 44 : 24;
    icon = L.divIcon({
      className: `pt pt--${kind}${selected ? ' pt--selected' : ''}`,
      html: `<span>${label}</span>`,
      iconSize: kind === 'label' ? [size, 18] : [size, size],
      iconAnchor: kind === 'label' ? [size / 2, 28] : [size / 2, size / 2],
    });
    iconCache.set(key, icon);
  }
  return icon;
}

function droneIcon(headingDeg: number): L.DivIcon {
  const key = `drone|${Math.round(headingDeg)}`;
  let icon = iconCache.get(key);
  if (!icon) {
    icon = L.divIcon({
      className: 'drone',
      html: `<svg viewBox="-20 -20 40 40" width="40" height="40" style="transform: rotate(${Math.round(headingDeg)}deg)">
        <g stroke="#111" stroke-width="2"><line x1="-11" y1="-11" x2="11" y2="11"/><line x1="11" y1="-11" x2="-11" y2="11"/></g>
        <g fill="rgba(255,255,255,.85)" stroke="#111" stroke-width="1.5">
          <circle cx="-11" cy="-11" r="6"/><circle cx="11" cy="-11" r="6"/><circle cx="-11" cy="11" r="6"/><circle cx="11" cy="11" r="6"/>
        </g>
        <path d="M0 -9 L6 5 L0 2 L-6 5 Z" fill="#ef4444" stroke="#111" stroke-width="1.5"/>
      </svg>`,
      iconSize: [40, 40],
      iconAnchor: [20, 20],
    });
    iconCache.set(key, icon);
  }
  return icon;
}

const toLL = (p: LatLng): [number, number] => [p.lat, p.lng];

function MapClicks({ onClick }: { onClick(at: LatLng): void }) {
  useMapEvents({ click: (e) => onClick({ lat: e.latlng.lat, lng: e.latlng.lng }) });
  return null;
}

function FocusController({ focus }: { focus: FocusRequest | null }) {
  const map = useMap();
  useEffect(() => {
    if (!focus || focus.points.length === 0) return;
    if (focus.points.length === 1) {
      map.flyTo(toLL(focus.points[0]), Math.max(map.getZoom(), 17), { duration: 0.6 });
    } else {
      map.fitBounds(L.latLngBounds(focus.points.map(toLL)), { padding: [40, 40], maxZoom: 19 });
    }
    // Only react to new requests, not to every re-render.
  }, [focus?.seq]);
  return null;
}

function PlacingCursor({ active }: { active: boolean }) {
  const map = useMap();
  useEffect(() => {
    map.getContainer().classList.toggle('map--placing', active);
  }, [active, map]);
  return null;
}

/** Photo dots drawn on one canvas; thousands of them stay fast while editing. */
function PhotoLayer({ photos, taken, simulating }: { photos: PhotoPoint[]; taken: number; simulating: boolean }) {
  const map = useMap();
  const groupRef = useRef<L.LayerGroup | null>(null);
  const markersRef = useRef<L.CircleMarker[]>([]);
  const shownTaken = useRef(0);
  const renderer = useMemo(() => L.canvas({ padding: 0.5 }), []);

  useEffect(() => {
    const group = L.layerGroup().addTo(map);
    groupRef.current = group;
    return () => {
      group.remove();
      groupRef.current = null;
    };
  }, [map]);

  useEffect(() => {
    const group = groupRef.current;
    if (!group) return;
    group.clearLayers();
    markersRef.current = photos.map((p) =>
      L.circleMarker([p.lat, p.lng], { renderer, radius: 3, interactive: false, ...PLANNED_PHOTO }).addTo(group),
    );
    shownTaken.current = 0;
  }, [photos, renderer]);

  useEffect(() => {
    const markers = markersRef.current;
    const target = simulating ? Math.min(taken, markers.length) : 0;
    const from = Math.min(shownTaken.current, target);
    const to = Math.max(shownTaken.current, target);
    for (let i = from; i < to; i++) markers[i]?.setStyle(i < target ? TAKEN_PHOTO : PLANNED_PHOTO);
    shownTaken.current = target;
  }, [taken, simulating, photos]);

  return null;
}

const PLANNED_PHOTO: L.PathOptions = { color: '#ffffff', weight: 1, fillColor: '#ffffff', fillOpacity: 0.35, opacity: 0.8 };
const TAKEN_PHOTO: L.PathOptions = { color: '#831843', weight: 1, fillColor: '#f472b6', fillOpacity: 1, opacity: 1 };
const CAPTURE_LINE: L.PathOptions = { color: '#facc15', weight: 3, opacity: 0.95 };
const TRANSIT_LINE: L.PathOptions = { color: '#fb923c', weight: 2, opacity: 0.9, dashArray: '6 6' };
const HOME_LINE: L.PathOptions = { color: '#e5e7eb', weight: 2, opacity: 0.8, dashArray: '2 6' };

/** Consecutive legs with the same photo setting become one polyline. */
function groupRuns(legs: RouteLeg[]): { capture: boolean; points: [number, number][] }[] {
  const runs: { capture: boolean; points: [number, number][] }[] = [];
  for (const leg of legs) {
    const last = runs[runs.length - 1];
    if (last && last.capture === leg.capture) last.points.push(toLL(leg.to));
    else runs.push({ capture: leg.capture, points: [toLL(leg.from), toLL(leg.to)] });
  }
  return runs;
}

function midpoints(points: LatLng[], closed: boolean): { index: number; at: LatLng }[] {
  const out: { index: number; at: LatLng }[] = [];
  const n = points.length;
  const edges = closed && n >= 3 ? n : n - 1;
  for (let i = 0; i < edges; i++) {
    const a = points[i];
    const b = points[(i + 1) % n];
    out.push({ index: i + 1, at: { lat: (a.lat + b.lat) / 2, lng: (a.lng + b.lng) / 2 } });
  }
  return out;
}

function footprintCorners(center: LatLng, headingDeg: number, widthM: number, lengthM: number): [number, number][] {
  const proj = localProjection(center);
  const h = headingDeg * DEG;
  const u = { x: Math.sin(h), y: Math.cos(h) }; // along the flight direction
  const n = { x: Math.cos(h), y: -Math.sin(h) }; // across
  const corners: [number, number][] = [];
  for (const [a, c] of [
    [1, 1],
    [1, -1],
    [-1, -1],
    [-1, 1],
  ]) {
    const p = proj.toLatLng({
      x: (a * lengthM * u.x) / 2 + (c * widthM * n.x) / 2,
      y: (a * lengthM * u.y) / 2 + (c * widthM * n.y) / 2,
    });
    corners.push(toLL(p));
  }
  return corners;
}

export function MapView(props: MapViewProps) {
  const { plan, analysis, provider, tool, selectedId, drone, photosTaken, simulating, focus } = props;
  const { route, photos } = analysis;
  const fieldMode = plan.mode === 'field';
  const editTarget: PointTarget = fieldMode ? 'boundary' : 'route';
  const editPoints = fieldMode ? plan.boundary : plan.routePoints;
  const runs = useMemo(() => groupRuns(route.legs), [route.legs]);

  const homeLegs = useMemo(() => {
    if (!plan.home || route.waypoints.length === 0) return [];
    const first = route.waypoints[0];
    const last = route.waypoints[route.waypoints.length - 1];
    return [
      [toLL(plan.home), toLL(first)],
      [toLL(last), toLL(plan.home)],
    ];
  }, [plan.home, route.waypoints]);

  const droneFootprint = drone && drone.altitudeM > 1 ? groundFootprint(drone.altitudeM) : null;

  return (
    <MapContainer center={NL_CENTER} zoom={8} maxZoom={22} className="map" zoomControl>
      <TileLayer
        key={provider.id}
        url={provider.url}
        attribution={provider.attribution}
        maxNativeZoom={provider.maxNativeZoom}
        maxZoom={22}
      />
      <MapClicks onClick={props.onMapClick} />
      <FocusController focus={focus} />
      <PlacingCursor active={tool !== 'none'} />

      {plan.boundary.length >= 2 && (
        <Polygon
          positions={plan.boundary.map(toLL)}
          interactive={false}
          pathOptions={
            fieldMode
              ? { color: '#22c55e', weight: 3, fillColor: '#22c55e', fillOpacity: 0.12 }
              : { color: '#22c55e', weight: 2, fillOpacity: 0, dashArray: '4 6' }
          }
        />
      )}

      {homeLegs.map((pts, i) => (
        <Polyline key={`home-${i}`} positions={pts} pathOptions={HOME_LINE} interactive={false} />
      ))}
      {runs.map((run, i) => (
        <Polyline key={`run-${i}`} positions={run.points} pathOptions={run.capture ? CAPTURE_LINE : TRANSIT_LINE} interactive={false} />
      ))}

      <PhotoLayer photos={photos} taken={photosTaken} simulating={simulating} />

      {fieldMode && route.waypoints.length > 0 && (
        <>
          <Marker position={toLL(route.waypoints[0])} icon={pointIcon('label', 'start')} interactive={false} />
          <Marker position={toLL(route.waypoints[route.waypoints.length - 1])} icon={pointIcon('label', 'eind')} interactive={false} />
        </>
      )}

      {!simulating &&
        editPoints.length >= 2 &&
        midpoints(editPoints, fieldMode).map(({ index, at }) => (
          <Marker
            key={`mid-${editTarget}-${index}`}
            position={toLL(at)}
            icon={pointIcon('mid', '+')}
            title="Klik om hier een punt toe te voegen"
            eventHandlers={{ click: () => props.onPointInsert(editTarget, index, at) }}
          />
        ))}

      {editPoints.map((p, i) => (
        <Marker
          key={p.id}
          position={toLL(p)}
          draggable={!simulating}
          icon={pointIcon(editTarget, String(i + 1), p.id === selectedId)}
          title={`${fieldMode ? 'Grenspunt' : 'Routepunt'} ${i + 1} (sleep om te verplaatsen)`}
          eventHandlers={{
            dragstart: () => props.onDragStart(),
            drag: (e) => {
              const ll = (e.target as L.Marker).getLatLng();
              props.onPointMove(editTarget, p.id, { lat: ll.lat, lng: ll.lng });
            },
            dragend: (e) => {
              const ll = (e.target as L.Marker).getLatLng();
              props.onPointMove(editTarget, p.id, { lat: ll.lat, lng: ll.lng });
            },
            click: () => props.onPointSelect(editTarget, p.id),
          }}
        />
      ))}

      {plan.home && (
        <Marker
          position={toLL(plan.home)}
          draggable={!simulating}
          icon={pointIcon('home', 'H')}
          title="Startpunt (sleep om te verplaatsen)"
          eventHandlers={{
            dragstart: () => props.onDragStart(),
            dragend: (e) => {
              const ll = (e.target as L.Marker).getLatLng();
              props.onHomeMove({ lat: ll.lat, lng: ll.lng });
            },
          }}
        />
      )}

      {drone && droneFootprint && (
        <Polygon
          positions={footprintCorners(drone.position, drone.headingDeg, droneFootprint.widthM, droneFootprint.lengthM)}
          interactive={false}
          pathOptions={{
            color: '#22d3ee',
            weight: drone.capture ? 2 : 1,
            fillColor: '#22d3ee',
            fillOpacity: drone.capture ? 0.18 : 0.06,
          }}
        />
      )}
      {drone && <Marker position={toLL(drone.position)} icon={droneIcon(drone.headingDeg)} interactive={false} zIndexOffset={1000} />}
    </MapContainer>
  );
}
