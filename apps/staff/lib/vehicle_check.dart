import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'ui.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Pojazd do wyboru w kontroli auta.
class CheckVehicle {
  const CheckVehicle({required this.id, required this.name, required this.kind, this.plate, this.lastKm, this.takenBy});

  final String id;
  final String name;
  final String kind;
  final String? plate;

  /// Ostatnio wpisany przebieg (km).
  final int? lastKm;

  /// Kto ma to auto dziś (inna osoba).
  final String? takenBy;

  /// Auto i skuter mają licznik, rower nie musi.
  bool get needsOdometer => kind == 'car' || kind == 'scooter';

  String get label => [name, ?plate].join(' · ');

  factory CheckVehicle.fromJson(Map<String, dynamic> j) => CheckVehicle(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    kind: j['kind'] as String? ?? 'car',
    plate: j['plate'] as String?,
    lastKm: (j['last_km'] as num?)?.toInt(),
    takenBy: j['taken_by'] as String?,
  );
}

/// Kontrola auta dostawcy na tej zmianie: czy lokal jej wymaga, auto na dziś i co już zrobione.
class VehicleStatus {
  const VehicleStatus({
    required this.required,
    required this.onShift,
    required this.vehicles,
    this.vehicleId,
    this.startKm,
    this.startDone = false,
    this.endDone = false,
    this.startVehicleId,
  });

  /// Lokal ma flotę, a ja rozwożę: przed pierwszym kursem i na koniec zmiany kontrola auta.
  final bool required;
  final bool onShift;
  final List<CheckVehicle> vehicles;

  /// Auto przypisane mi na dziś (Grafik albo Dostawy w panelu).
  final String? vehicleId;
  final bool startDone;
  final bool endDone;
  final int? startKm;
  final String? startVehicleId;

  bool get needsStart => required && onShift && !startDone;
  bool get needsEnd => required && onShift && startDone && !endDone;

  CheckVehicle? vehicle(String? id) => vehicles.where((v) => v.id == id).firstOrNull;

  factory VehicleStatus.fromJson(Map<String, dynamic> j) {
    final start = j['start'] as Map<String, dynamic>?;
    return VehicleStatus(
      required: j['required'] == true,
      onShift: j['on_shift'] == true,
      vehicleId: j['vehicle_id'] as String?,
      startDone: start != null,
      endDone: j['end'] != null,
      startKm: (start?['odometer_km'] as num?)?.toInt(),
      startVehicleId: start?['vehicle_id'] as String?,
      vehicles: [for (final v in j['vehicles'] as List? ?? const []) CheckVehicle.fromJson(v as Map<String, dynamic>)],
    );
  }
}

final vehicleStatusProvider = FutureProvider.autoDispose.family<VehicleStatus, String>((ref, memberId) async {
  final json = await Supabase.instance.client.rpc<Map<String, dynamic>>(
    'staff_vehicle_status',
    params: {'p_member_id': memberId},
  );
  return VehicleStatus.fromJson(json);
});

/// Kontrola auta: wybór auta, przebieg z licznika i cztery zdjęcia dookoła (przód, tył, boki). Zdjęcia są
/// zmniejszane w telefonie (najdłuższy bok 1280 px, JPEG), więc ważą zwykle 150–300 KB i nadal widać rysy.
class VehicleCheckScreen extends ConsumerStatefulWidget {
  const VehicleCheckScreen({super.key, required this.job, required this.end});

  final Job job;

  /// Koniec zmiany (przebieg i zdjęcia po jeździe). Fałsz: przed pierwszym kursem.
  final bool end;

  /// Otwiera kontrolę; zwraca true, gdy zapisana.
  static Future<bool> open(BuildContext context, Job job, {required bool end}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleCheckScreen(job: job, end: end),
      ),
    );
    return ok == true;
  }

  @override
  ConsumerState<VehicleCheckScreen> createState() => _VehicleCheckScreenState();
}

class _VehicleCheckScreenState extends ConsumerState<VehicleCheckScreen> {
  static const _sides = ['Przód', 'Tył', 'Lewy bok', 'Prawy bok'];
  final _km = TextEditingController();
  final _photos = <int, Uint8List>{};
  String? _vehicleId;
  bool _busy = false;

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  Future<void> _shoot(int side) async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 72,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _photos[side] = bytes);
    } catch (_) {
      if (!mounted) return;
      showMessage(context, 'Nie udało się zrobić zdjęcia. Sprawdź dostęp do aparatu.', tone: ToastTone.error);
    }
  }

  Future<void> _save(VehicleStatus status) async {
    final vehicle = status.vehicle(_vehicleId);
    final km = int.tryParse(_km.text.replaceAll(RegExp(r'\s'), ''));
    String? problem;
    if (vehicle == null) {
      problem = 'Wybierz auto.';
    } else if (vehicle.needsOdometer && km == null) {
      problem = 'Wpisz przebieg z licznika.';
    } else if (km != null && vehicle.lastKm != null && km < vehicle.lastKm!) {
      problem = 'Przebieg jest mniejszy niż ostatnio wpisany (${vehicle.lastKm} km). Sprawdź licznik.';
    } else if (_photos.length < _sides.length) {
      problem = 'Zrób wszystkie cztery zdjęcia: przód, tył i oba boki.';
    }
    if (problem != null) {
      showMessage(context, problem, tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      final storage = Supabase.instance.client.storage.from('vehicle-photos');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final day = DateTime.now().toIso8601String().substring(0, 10);
      final paths = <String>[];
      for (var i = 0; i < _sides.length; i++) {
        final path = '${widget.job.restaurantId}/${vehicle!.id}/$day/$stamp-${widget.end ? 'koniec' : 'start'}-$i.jpg';
        await storage.uploadBinary(
          path,
          _photos[i]!,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
        );
        paths.add(path);
      }
      await Supabase.instance.client.rpc<void>(
        'staff_vehicle_check',
        params: {
          'p_member_id': widget.job.memberId,
          'p_vehicle_id': vehicle!.id,
          'p_kind': widget.end ? 'end' : 'start',
          'p_odometer_km': km,
          'p_photos': paths,
        },
      );
      ref.invalidate(vehicleStatusProvider(widget.job.memberId));
      if (!mounted) return;
      showMessage(
        context,
        widget.end ? 'Auto zdane. Dziękujemy!' : 'Kontrola auta zapisana. Możesz brać kursy.',
        tone: ToastTone.success,
      );
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) showMessage(context, e.message, tone: ToastTone.error);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Podpowiedź pod przebiegiem: ostatni wpis i stan z początku zmiany. Null: brak.
  String? _hint(CheckVehicle vehicle, VehicleStatus status) {
    final parts = [
      if (vehicle.lastKm != null) 'Ostatnio: ${vehicle.lastKm} km',
      if (widget.end && status.startKm != null) 'Na początku zmiany: ${status.startKm} km',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(vehicleStatusProvider(widget.job.memberId));
    return Scaffold(
      appBar: AppBar(leading: glassLeading(context), title: Text(widget.end ? 'Auto na koniec zmiany' : 'Auto przed pierwszym kursem')),
      body: async.when(
        loading: () => const CardsSkeleton(count: 2, tile: false),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(vehicleStatusProvider(widget.job.memberId))),
        data: (status) {
          // Na koniec zmiany to samo auto co na początku; na początku auto z Grafiku, jeśli jest.
          _vehicleId ??= widget.end ? status.startVehicleId : status.vehicleId;
          final vehicle = status.vehicle(_vehicleId);
          if (status.vehicles.isEmpty) {
            return const MessageView(
              icon: AppIcons.car,
              title: 'Lokal nie ma aut we Flocie',
              message: 'Kontrola auta nie jest potrzebna.',
            );
          }
          return ContentWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  widget.end
                      ? 'Wpisz przebieg i zrób zdjęcia auta dookoła, zanim zakończysz zmianę.'
                      : 'Zanim weźmiesz pierwszy kurs: wybierz auto, wpisz przebieg i zrób zdjęcia dookoła.',
                  style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                const SectionHeader('Auto', top: 0),
                if (widget.end && vehicle != null)
                  Text(vehicle.label, style: text.titleMedium)
                else
                  DropdownButtonFormField<String>(
                    initialValue: vehicle?.id,
                    decoration: const InputDecoration(labelText: 'Którym autem jeździsz'),
                    items: [
                      for (final v in status.vehicles)
                        DropdownMenuItem(
                          value: v.id,
                          child: Text(v.takenBy == null ? v.label : '${v.label} (dziś: ${v.takenBy})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _vehicleId = v),
                  ),
                if (vehicle != null) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _km,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                    style: const TextStyle(fontFeatures: _tabular),
                    decoration: InputDecoration(
                      labelText: vehicle.needsOdometer ? 'Przebieg z licznika' : 'Przebieg (opcjonalnie)',
                      suffixText: 'km',
                      helperText: _hint(vehicle, status),
                    ),
                  ),
                ],
                const SectionHeader('Zdjęcia dookoła'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 4 / 3,
                  children: [
                    for (final (i, side) in _sides.indexed)
                      _PhotoSlot(label: side, bytes: _photos[i], onTap: () => _shoot(i)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: async.value == null || async.value!.vehicles.isEmpty
          ? null
          : BottomActionBar(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: _busy ? null : () => _save(async.value!),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Glyph(AppIcons.check, size: 20),
                label: Text(widget.end ? 'Zapisz i zakończ zmianę' : 'Zapisz kontrolę auta'),
              ),
            ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({required this.label, required this.bytes, required this.onTap});

  final String label;
  final Uint8List? bytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = bytes != null;
    return Semantics(
      button: true,
      label: done ? '$label: zdjęcie zrobione, stuknij, żeby zrobić ponownie' : '$label: zrób zdjęcie',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: done ? AppColors.accent : AppColors.ring),
            image: done ? DecorationImage(image: MemoryImage(bytes!), fit: BoxFit.cover) : null,
          ),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Glyph(
                    done ? AppIcons.checkCircle : AppIcons.camera,
                    size: 16,
                    color: done ? AppColors.accent : AppColors.text,
                  ),
                  const SizedBox(width: 6),
                  Text(label, style: text.labelLarge),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
