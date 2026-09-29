import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';

/// Aparat skanujący kod QR z panelu restauracji (tryb obsługi). Po skanie baza zaczyna
/// zmianę i odblokowuje panel. Zwraca wynik skanu albo null, gdy pracownik się wycofał.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    String? code;
    for (final b in capture.barcodes) {
      final value = b.rawValue;
      if (value != null && value.startsWith('table-praca:')) code = value;
    }
    if (code == null) {
      setState(() => _problem = 'To nie jest kod z panelu Table.');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final result = await ref.read(staffRepositoryProvider).scan(code);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) setState(() => _problem = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Zeskanuj kod'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Brak dostępu do aparatu. Zezwól na aparat w ustawieniach telefonu.',
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
          // Ramka pokazuje, gdzie ustawić kod.
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppPalette.dark.accent, width: 4),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _busy
                    ? 'Zaczynam zmianę…'
                    : _problem ?? 'Skieruj aparat na kod QR na ekranie „Zaloguj się do pracy” w lokalu.',
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(
                  color: _problem == null || _busy ? Colors.white : const Color(0xFFFF8A8A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
