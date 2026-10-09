import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

/// Kolory mapy Table w jednym motywie.
class _MapColors {
  const _MapColors({
    required this.background,
    required this.water,
    required this.park,
    required this.building,
    required this.buildingOutline,
    required this.service,
    required this.minor,
    required this.street,
    required this.major,
    required this.motorway,
    required this.casing,
    required this.label,
    required this.labelMuted,
    required this.halo,
  });

  final String background;
  final String water;
  final String park;
  final String building;
  final String buildingOutline;

  /// Drogi dojazdowe i parkingowe: widać je dopiero z bliska i słabiej niż ulice.
  final String service;
  final String minor;
  final String street;
  final String major;
  final String motorway;

  /// Obrys dróg (w jasnym motywie białe drogi potrzebują krawędzi).
  final String casing;
  final String label;
  final String labelMuted;
  final String halo;
}

// Ciemna: tło jak panel (#09090B, karty #111113), woda i zieleń z lekkim odcieniem akcentu Table.
const _dark = _MapColors(
  background: '#101012',
  water: '#0b1f1d',
  park: '#10201a',
  building: '#17171b',
  buildingOutline: '#1d1d22',
  service: '#1b1b20',
  minor: '#232329',
  street: '#2a2a31',
  major: '#323239',
  motorway: '#3b3b44',
  casing: '#101012',
  label: '#a1a1aa',
  labelMuted: '#8f8f98',
  halo: '#101012',
);

// Jasna: tło jak panel w jasnym motywie, białe drogi z szarą krawędzią.
const _light = _MapColors(
  background: '#f1f2f1',
  water: '#cfe5e2',
  park: '#dcece3',
  building: '#e5e6e5',
  buildingOutline: '#d9dbd9',
  service: '#fafafa',
  minor: '#ffffff',
  street: '#ffffff',
  major: '#ffffff',
  motorway: '#fbfbfb',
  casing: '#d5d8d5',
  label: '#3f4441',
  labelMuted: '#5f6561',
  halo: '#ffffff',
);

/// Tło mapy (także pod kafelkami): ten sam kolor co tło stylu, żeby przy ułamkowym przybliżeniu
/// na granicach kafelków nie prześwitywały cienkie linie.
Color mapBackground({required bool dark}) =>
    Color(int.parse('FF${(dark ? _dark : _light).background.substring(1)}', radix: 16));

/// Źródło kafelków w stylu (OpenFreeMap, schemat OpenMapTiles).
const mapTileSource = 'openmaptiles';

/// Styl mapy Table dla dostawców: tylko to, czego potrzeba do jazdy. Drogi (bez ścieżek, chodników, dróg
/// rowerowych i torów), budynki, woda, zieleń, nazwy ulic, numery domów i nazwy osiedli. Bez punktów usług,
/// placów zabaw, przystanków, granic i innych znaczników. Napisy czcionką Geist.
Map<String, dynamic> tableMapStyle({required bool dark}) {
  final c = dark ? _dark : _light;
  const font = [AppTheme.fontFamily];
  // Drogi, które mają sens dla dostawcy (samochód, skuter): bez ścieżek, torów, promów i wyciągów.
  const driveable = ['in', 'class', 'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor', 'service'];

  Map<String, dynamic> road(
    String id,
    List<String> classes,
    String color,
    List<List<num>> width, {
    bool casing = false,
    int? minzoom,
  }) => {
    'id': id,
    'type': 'line',
    'minzoom': ?minzoom,
    'source': mapTileSource,
    'source-layer': 'transportation',
    'filter': [
      'all',
      ['in', 'class', ...classes],
      // Drogi w tunelach rysujemy tak samo, ale bez krawędzi (nie zasłaniają tego, co nad nimi).
      if (casing) ['!=', 'brunnel', 'tunnel'],
    ],
    // Zaokrąglone końce wypełniają styk odcinków pod kątem (proste zostawiały ciemne kliny).
    'layout': {'line-cap': 'round', 'line-join': 'round'},
    'paint': {
      'line-color': casing ? c.casing : color,
      'line-width': {
        'base': 1.4,
        'stops': [
          for (final s in width) [s[0], casing ? s[1] + 1.5 : s[1]],
        ],
      },
    },
  };

  const serviceWidth = [
    [15, 1],
    [17, 4],
    [19, 10],
  ];
  const minorWidth = [
    [13, 0.6],
    [15, 2.4],
    [17, 8],
    [19, 20],
  ];
  // Główne ulice z bliska są szersze niż pas między jezdniami, więc droga z dwiema jezdniami
  // wygląda jak jedna (bez ciemnej szczeliny pośrodku).
  const streetWidth = [
    [11, 0.8],
    [14, 3.4],
    [17, 15],
    [19, 34],
  ];
  const majorWidth = [
    [9, 1],
    [13, 4],
    [17, 20],
    [19, 42],
  ];
  const motorwayWidth = [
    [7, 1],
    [12, 4.5],
    [17, 22],
    [19, 46],
  ];

  return {
    'version': 8,
    'id': dark ? 'table-dark' : 'table-light',
    'metadata': {'version': '2'},
    'sources': {
      mapTileSource: {'type': 'vector'},
    },
    'layers': [
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': c.background},
      },
      {
        'id': 'park',
        'type': 'fill',
        'source': mapTileSource,
        'source-layer': 'park',
        'paint': {'fill-color': c.park},
      },
      {
        'id': 'grass',
        'type': 'fill',
        'source': mapTileSource,
        'source-layer': 'landcover',
        'filter': ['in', 'class', 'grass', 'wood'],
        'paint': {'fill-color': c.park, 'fill-opacity': 0.7},
      },
      {
        'id': 'water',
        'type': 'fill',
        'source': mapTileSource,
        'source-layer': 'water',
        'filter': ['!=', 'brunnel', 'tunnel'],
        'paint': {'fill-color': c.water},
      },
      {
        'id': 'waterway',
        'type': 'line',
        'source': mapTileSource,
        'source-layer': 'waterway',
        'filter': ['in', 'class', 'river', 'canal'],
        'paint': {
          'line-color': c.water,
          'line-width': {
            'base': 1.3,
            'stops': [
              [10, 1],
              [16, 6],
            ],
          },
        },
      },
      {
        'id': 'building',
        'type': 'fill',
        'source': mapTileSource,
        'source-layer': 'building',
        'minzoom': 14,
        'paint': {'fill-color': c.building, 'fill-outline-color': c.buildingOutline},
      },
      // Krawędzie (w jasnym motywie), potem drogi od najmniejszych do autostrad.
      if (!dark) ...[
        road('service-casing', ['service'], c.service, serviceWidth, casing: true, minzoom: 15),
        road('minor-casing', ['minor'], c.minor, minorWidth, casing: true),
        road('street-casing', ['secondary', 'tertiary'], c.street, streetWidth, casing: true),
        road('major-casing', ['primary', 'trunk'], c.major, majorWidth, casing: true),
        road('motorway-casing', ['motorway'], c.motorway, motorwayWidth, casing: true),
      ],
      road('service', ['service'], c.service, serviceWidth, minzoom: 15),
      road('minor', ['minor'], c.minor, minorWidth),
      road('street', ['secondary', 'tertiary'], c.street, streetWidth),
      road('major', ['primary', 'trunk'], c.major, majorWidth),
      road('motorway', ['motorway'], c.motorway, motorwayWidth),
      // Nazwy ulic wzdłuż dróg.
      {
        'id': 'street-names',
        'type': 'symbol',
        'source': mapTileSource,
        'source-layer': 'transportation_name',
        'minzoom': 13,
        'filter': driveable,
        'layout': {
          'symbol-placement': 'line',
          'text-field': '{name}',
          'text-font': font,
          'text-size': {
            'base': 1.2,
            'stops': [
              [13, 10],
              [17, 14],
            ],
          },
        },
        'paint': {'text-color': c.label, 'text-halo-color': c.halo, 'text-halo-width': 1.5},
      },
      // Numery domów: dostawca szuka konkretnego budynku.
      {
        'id': 'house-numbers',
        'type': 'symbol',
        'source': mapTileSource,
        'source-layer': 'housenumber',
        'minzoom': 16,
        'layout': {'text-field': '{housenumber}', 'text-font': font, 'text-size': 11},
        'paint': {'text-color': c.labelMuted, 'text-halo-color': c.halo, 'text-halo-width': 1},
      },
      // Osiedla i dzielnice, a przy dalekim widoku miasta.
      {
        'id': 'places',
        'type': 'symbol',
        'source': mapTileSource,
        'source-layer': 'place',
        'filter': ['in', 'class', 'city', 'town', 'village', 'suburb', 'quarter', 'neighbourhood'],
        'layout': {
          'text-field': '{name}',
          'text-font': font,
          'text-size': {
            'base': 1.2,
            'stops': [
              [10, 11],
              [14, 13],
            ],
          },
          'text-transform': 'uppercase',
          'text-letter-spacing': 0.08,
        },
        'paint': {'text-color': c.labelMuted, 'text-halo-color': c.halo, 'text-halo-width': 1.5},
      },
    ],
  };
}
