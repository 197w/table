import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/providers.dart';

/// Gdzie jest dostawca: jego pozycja i lokal. Null, gdy kurs nie jest w drodze albo pozycji jeszcze nie ma.
class CourierPosition {
  const CourierPosition({this.courier, this.updatedAt, this.restaurant});

  final LatLng? courier;
  final DateTime? updatedAt;
  final LatLng? restaurant;

  static CourierPosition? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    double? d(Object? v) => v is num ? v.toDouble() : null;
    final lat = d(json['lat']);
    final lng = d(json['lng']);
    final rLat = d(json['restaurant_lat']);
    final rLng = d(json['restaurant_lng']);
    return CourierPosition(
      courier: lat == null || lng == null ? null : LatLng(lat, lng),
      updatedAt: json['updated_at'] == null ? null : DateTime.parse(json['updated_at'] as String).toLocal(),
      restaurant: rLat == null || rLng == null ? null : LatLng(rLat, rLng),
    );
  }
}

/// Pozycja dostawcy odświeżana co 10 sekund, dopóki zamówienie jest w drodze.
final courierPositionProvider = StreamProvider.autoDispose.family<CourierPosition?, String>((ref, orderId) async* {
  final repo = ref.watch(repositoryProvider);
  while (true) {
    try {
      yield CourierPosition.fromJson(await repo.courierPosition(orderId));
    } catch (_) {
      // Chwilowy brak sieci: zostaje ostatnia pozycja.
    }
    await Future<void>.delayed(const Duration(seconds: 10));
  }
});

/// Mapa z dostawcą w drodze (OpenStreetMap). Pokazuje też lokal, z którego jedzie.
class CourierMap extends ConsumerWidget {
  const CourierMap({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final position = ref.watch(courierPositionProvider(orderId)).value;
    final courier = position?.courier;
    final restaurant = position?.restaurant;
    final center = courier ?? restaurant;
    if (center == null) return const SizedBox.shrink();
    final updated = position?.updatedAt;
    final ago = updated == null ? null : DateTime.now().difference(updated);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: FlutterMap(
              key: ValueKey(courier == null),
              options: MapOptions(
                initialCenter: center,
                initialZoom: courier == null ? 14 : 15,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'pl.table.app',
                ),
                MarkerLayer(
                  markers: [
                    if (restaurant != null)
                      Marker(
                        point: restaurant,
                        width: 34,
                        height: 34,
                        child: _Pin(icon: AppIcons.storefront, color: AppColors.surfaceRaised, iconColor: AppColors.text),
                      ),
                    if (courier != null)
                      Marker(
                        point: courier,
                        width: 42,
                        height: 42,
                        child: _Pin(icon: AppIcons.moped, color: AppColors.accentFill, iconColor: AppColors.onAccent),
                      ),
                  ],
                ),
                const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap')]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                Glyph(AppIcons.moped, size: 16, color: courier == null ? AppColors.textMuted : AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    courier == null
                        ? 'Dostawca wyjechał. Jego pozycja pojawi się za chwilę.'
                        : ago != null && ago.inMinutes >= 2
                        ? 'Ostatnia pozycja dostawcy ${ago.inMinutes} min temu.'
                        : 'Dostawca jest w drodze.',
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.icon, required this.color, required this.iconColor});

  final AppIconData icon;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Glyph(icon, size: 18, color: iconColor),
    );
  }
}
