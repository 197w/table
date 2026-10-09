// Mapa dostawców w panelu: kafelki mapy, współrzędne adresów dostaw i trasy dostawców.
// Z kluczami Google (sekrety GOOGLE_MAPS_TILES_KEY i GOOGLE_MAPS_SERVER_KEY) używa Map Tiles API,
// Geocoding API i Routes API. Bez nich tymczasowo OpenStreetMap: kafelki, Nominatim i OSRM.
//
// Wywołuje ją panel z tokenem zalogowanego konta. Uprawnienia sprawdzają funkcje bazy
// (panel_geocode_input, panel_route_input), a zapis robi ta funkcja kluczem serwisowym.

import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const TILES_KEY = Deno.env.get("GOOGLE_MAPS_TILES_KEY") ?? "";
const SERVER_KEY = Deno.env.get("GOOGLE_MAPS_SERVER_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Trasa z pamięci wystarcza, dopóki ma mniej niż 4 minuty, a dostawca nie odjechał dalej niż 400 m od jej początku.
const ROUTE_TTL_MS = 4 * 60 * 1000;
const ROUTE_MOVE_M = 400;

// Ciemna mapa w ciemnym motywie panelu (kolory jak PanelPalette.dark), bez punktów usług i komunikacji.
const DARK_STYLES = [
  { elementType: "geometry", stylers: [{ color: "#141416" }] },
  { elementType: "labels.text.fill", stylers: [{ color: "#8b8b94" }] },
  { elementType: "labels.text.stroke", stylers: [{ color: "#09090b" }] },
  { elementType: "labels.icon", stylers: [{ visibility: "off" }] },
  { featureType: "administrative", elementType: "geometry", stylers: [{ color: "#2a2a30" }] },
  { featureType: "poi", stylers: [{ visibility: "off" }] },
  { featureType: "transit", stylers: [{ visibility: "off" }] },
  { featureType: "road", elementType: "geometry", stylers: [{ color: "#26262b" }] },
  { featureType: "road.arterial", elementType: "geometry", stylers: [{ color: "#2e2e34" }] },
  { featureType: "road.highway", elementType: "geometry", stylers: [{ color: "#3a3a42" }] },
  { featureType: "road", elementType: "labels.text.fill", stylers: [{ color: "#a1a1aa" }] },
  { featureType: "water", elementType: "geometry", stylers: [{ color: "#0c1820" }] },
  { featureType: "landscape.man_made", elementType: "geometry", stylers: [{ color: "#18181b" }] },
];
const LIGHT_STYLES = [
  { featureType: "poi.business", stylers: [{ visibility: "off" }] },
  { featureType: "transit", elementType: "labels.icon", stylers: [{ visibility: "off" }] },
];

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

/** Odległość w metrach (wzór haversine). */
function distance(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const r = 6371000;
  const rad = Math.PI / 180;
  const dLat = (bLat - aLat) * rad;
  const dLng = (bLng - aLng) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(aLat * rad) * Math.cos(bLat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

// ---------------------------------------------------------------
// Kafelki
// ---------------------------------------------------------------

async function tiles(dark: boolean) {
  if (!TILES_KEY) return { provider: "osm" };
  const res = await fetch(`https://tile.googleapis.com/v1/createSession?key=${TILES_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      mapType: "roadmap",
      language: "pl-PL",
      region: "PL",
      scale: "scaleFactor2x",
      highDpi: true,
      styles: dark ? DARK_STYLES : LIGHT_STYLES,
    }),
  });
  if (!res.ok) {
    console.error("createSession", res.status, await res.text());
    return { provider: "osm" };
  }
  const s = await res.json();
  // Klucz do kafelków trafia do panelu: w Google Cloud jest ograniczony tylko do Map Tiles API.
  return {
    provider: "google",
    session: s.session,
    expiry: s.expiry,
    key: TILES_KEY,
    tile_width: s.tileWidth,
  };
}

// ---------------------------------------------------------------
// Adres na współrzędne
// ---------------------------------------------------------------

type GeoInput = {
  order_id: string;
  address: string | null;
  street: string | null;
  house: string | null;
  city: string | null;
  restaurant_lat: number | null;
  restaurant_lng: number | null;
  lat: number | null;
  lng: number | null;
  geo: string | null;
};

function query(g: GeoInput): string {
  if (g.street) return `${g.street} ${g.house ?? ""}`.trim() + `, ${g.city ?? ""}`;
  // Numer lokalu po ukośniku przeszkadza w szukaniu („Lipowa 14/3” → „Lipowa 14”).
  return (g.address ?? "").replace(/(\d+[a-zA-Z]?)\/\S+/, "$1");
}

async function geocodeGoogle(g: GeoInput): Promise<{ lat: number; lng: number } | null> {
  const params = new URLSearchParams({
    address: query(g),
    components: "country:PL",
    language: "pl",
    region: "pl",
    key: SERVER_KEY,
  });
  if (g.restaurant_lat != null && g.restaurant_lng != null) {
    // Ten sam adres może być w kilku miastach: najpierw szukamy w okolicy lokalu (ok. 30 km).
    const d = 0.3;
    params.set(
      "bounds",
      `${g.restaurant_lat - d},${g.restaurant_lng - d}|${g.restaurant_lat + d},${g.restaurant_lng + d}`,
    );
  }
  const res = await fetch(`https://maps.googleapis.com/maps/api/geocode/json?${params}`);
  const body = await res.json();
  if (body.status !== "OK" || !body.results?.length) {
    if (body.status !== "ZERO_RESULTS") console.error("geocode", body.status, body.error_message);
    return null;
  }
  const loc = body.results[0].geometry.location;
  return { lat: loc.lat, lng: loc.lng };
}

async function geocodeOsm(g: GeoInput): Promise<{ lat: number; lng: number } | null> {
  const params = new URLSearchParams({ q: query(g), format: "jsonv2", limit: "1", countrycodes: "pl" });
  const res = await fetch(`https://nominatim.openstreetmap.org/search?${params}`, {
    headers: { "User-Agent": "TablePanel/1.0 (mapa dostawcow)" },
  });
  if (!res.ok) return null;
  const rows = await res.json();
  if (!rows.length) return null;
  return { lat: Number(rows[0].lat), lng: Number(rows[0].lon) };
}

async function geocode(user: ReturnType<typeof createClient>, admin: ReturnType<typeof createClient>, orderId: string) {
  const { data, error } = await user.rpc("panel_geocode_input", { p_order_id: orderId });
  if (error) return json({ error: error.message }, 403);
  const g = data as GeoInput;
  if (g.lat != null && g.lng != null) return json({ lat: g.lat, lng: g.lng, geo: g.geo });
  if (g.geo === "none") return json({ lat: null, lng: null, geo: "none" });
  const provider = SERVER_KEY ? "google" : "osm";
  const found = SERVER_KEY ? await geocodeGoogle(g) : await geocodeOsm(g);
  const geo = found ? provider : "none";
  await admin
    .from("orders")
    .update({ delivery_lat: found?.lat ?? null, delivery_lng: found?.lng ?? null, delivery_geo: geo })
    .eq("id", orderId);
  return json({ lat: found?.lat ?? null, lng: found?.lng ?? null, geo });
}

// ---------------------------------------------------------------
// Trasa dostawcy do celu
// ---------------------------------------------------------------

type RouteInput = {
  restaurant_id: string;
  active: boolean | null;
  origin_lat: number | null;
  origin_lng: number | null;
  dest_lat: number | null;
  dest_lng: number | null;
  cached: {
    polyline: string;
    duration_s: number | null;
    distance_m: number | null;
    provider: string;
    computed_at: string;
    origin_lat: number | null;
    origin_lng: number | null;
  } | null;
};

type Route = { polyline: string; duration_s: number | null; distance_m: number | null; provider: string };

async function routeGoogle(r: RouteInput): Promise<Route | null> {
  const point = (lat: number, lng: number) => ({ location: { latLng: { latitude: lat, longitude: lng } } });
  const res = await fetch("https://routes.googleapis.com/directions/v2:computeRoutes", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": SERVER_KEY,
      // Tylko linia, czas i odległość: bez opisu trasy krok po kroku (w EOG nie wolno go pokazywać przy mapie).
      "X-Goog-FieldMask": "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline",
    },
    body: JSON.stringify({
      origin: point(r.origin_lat!, r.origin_lng!),
      destination: point(r.dest_lat!, r.dest_lng!),
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_AWARE",
      languageCode: "pl-PL",
      regionCode: "PL",
      units: "METRIC",
    }),
  });
  const body = await res.json();
  const route = body.routes?.[0];
  if (!res.ok || !route) {
    console.error("computeRoutes", res.status, JSON.stringify(body).slice(0, 300));
    return null;
  }
  return {
    polyline: route.polyline.encodedPolyline,
    duration_s: route.duration ? parseInt(String(route.duration).replace("s", ""), 10) : null,
    distance_m: route.distanceMeters ?? null,
    provider: "google",
  };
}

async function routeOsrm(r: RouteInput): Promise<Route | null> {
  const url = `https://router.project-osrm.org/route/v1/driving/${r.origin_lng},${r.origin_lat};${r.dest_lng},${r.dest_lat}` +
    "?overview=full&geometries=polyline";
  const res = await fetch(url, { headers: { "User-Agent": "TablePanel/1.0 (mapa dostawcow)" } });
  if (!res.ok) return null;
  const body = await res.json();
  const route = body.routes?.[0];
  if (!route) return null;
  return {
    polyline: route.geometry,
    duration_s: Math.round(route.duration),
    distance_m: Math.round(route.distance),
    provider: "osm",
  };
}

async function route(
  user: ReturnType<typeof createClient>,
  admin: ReturnType<typeof createClient>,
  memberId: string,
  orderId: string,
) {
  const { data, error } = await user.rpc("panel_route_input", { p_member_id: memberId, p_order_id: orderId });
  if (error) return json({ error: error.message }, 403);
  const r = data as RouteInput;
  if (!r.active) return json({ error: "Kurs nie jest w drodze." }, 409);
  if (r.origin_lat == null || r.dest_lat == null) return json({ error: "Brak pozycji dostawcy albo celu." }, 409);

  const c = r.cached;
  if (
    c &&
    Date.now() - Date.parse(c.computed_at) < ROUTE_TTL_MS &&
    c.origin_lat != null &&
    distance(c.origin_lat, c.origin_lng!, r.origin_lat, r.origin_lng!) < ROUTE_MOVE_M
  ) {
    return json({ ...c, cached: true });
  }

  const found = SERVER_KEY ? await routeGoogle(r) : await routeOsrm(r);
  if (!found) return json({ error: "Nie udało się wyznaczyć trasy." }, 502);
  const computedAt = new Date().toISOString();
  await admin.from("courier_routes").upsert({
    member_id: memberId,
    order_id: orderId,
    restaurant_id: r.restaurant_id,
    polyline: found.polyline,
    duration_s: found.duration_s,
    distance_m: found.distance_m,
    origin_lat: r.origin_lat,
    origin_lng: r.origin_lng,
    provider: found.provider,
    computed_at: computedAt,
  });
  return json({ ...found, computed_at: computedAt, cached: false });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Tylko POST." }, 405);
  const auth = req.headers.get("Authorization") ?? "";
  const user = createClient(SUPABASE_URL, ANON_KEY || SERVICE_KEY, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Zły format zapytania." }, 400);
  }
  try {
    switch (body.action) {
      case "tiles": {
        // Klucz do kafelków dostaje tylko obsługa lokalu z uprawnieniem do zamówień, nie każdy zalogowany gość.
        const { error } = await user.rpc("panel_couriers", { p_restaurant_id: String(body.restaurant_id) });
        if (error) return json({ error: error.message }, 403);
        return json(await tiles(body.dark === true));
      }
      case "geocode":
        return await geocode(user, admin, String(body.order_id));
      case "route":
        return await route(user, admin, String(body.member_id), String(body.order_id));
      default:
        return json({ error: "Nieznane działanie." }, 400);
    }
  } catch (e) {
    console.error(e);
    return json({ error: "Błąd mapy. Spróbuj ponownie." }, 500);
  }
});
