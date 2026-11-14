/// Konfiguracja przekazywana przy uruchomieniu:
/// flutter run --dart-define-from-file=env.json
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Publiczny klucz Mapbox („pk.…”) do mapy dostawców w panelu: kafelki, adresy, trasy (14.11.2026). Pusty: panel
  /// pokazuje mapę bez kafelków z informacją, jak dodać klucz. Klucz zakłada i wpisuje do env.json użytkownik.
  static const mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');

  /// Style mapy Mapbox („konto/styl”, np. własny styl z Mapbox Studio). Domyślnie gotowe style ciemny i jasny.
  static const mapboxStyleDark = String.fromEnvironment('MAPBOX_STYLE_DARK', defaultValue: 'mapbox/dark-v11');
  static const mapboxStyleLight = String.fromEnvironment('MAPBOX_STYLE_LIGHT', defaultValue: 'mapbox/light-v11');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
