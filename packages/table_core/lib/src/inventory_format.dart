// Liczby i opakowania w inwentaryzacji (panel i Table for employees).

/// Liczba po polsku, bez zbędnych zer: 0,7; 2,45; 12.
String inventoryNumber(double value) {
  final fixed = value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  return (fixed == '-0' ? '0' : fixed).replaceAll('.', ',');
}

/// Jak [inventoryNumber], z odstępami co trzy cyfry, np. „52 500”.
String inventoryGrouped(double value) {
  final text = inventoryNumber(value);
  final negative = text.startsWith('-');
  final parts = (negative ? text.substring(1) : text).split(',');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('\u00a0');
    grouped.write(digits[i]);
  }
  return '${negative ? '-' : ''}$grouped${parts.length > 1 ? ',${parts[1]}' : ''}';
}

/// Liczba wpisana z przecinkiem albo kropką. Null: to nie jest liczba.
double? parseInventoryNumber(String text) {
  final clean = text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  if (clean.isEmpty) return null;
  return double.tryParse(clean);
}

/// Odmiana nazw opakowań: 1 worek, 2 worki, 5 worków, 2,5 worka. Nieznana nazwa bez odmiany, brak nazwy: „op.”.
const _packForms = {
  'zgrzewka': ('zgrzewka', 'zgrzewki', 'zgrzewek', 'zgrzewki'),
  'worek': ('worek', 'worki', 'worków', 'worka'),
  'puszka': ('puszka', 'puszki', 'puszek', 'puszki'),
  'butelka': ('butelka', 'butelki', 'butelek', 'butelki'),
  'karton': ('karton', 'kartony', 'kartonów', 'kartonu'),
  'skrzynka': ('skrzynka', 'skrzynki', 'skrzynek', 'skrzynki'),
  'opakowanie': ('opakowanie', 'opakowania', 'opakowań', 'opakowania'),
  'słoik': ('słoik', 'słoiki', 'słoików', 'słoika'),
  'paczka': ('paczka', 'paczki', 'paczek', 'paczki'),
  'kanister': ('kanister', 'kanistry', 'kanistrów', 'kanistra'),
  'beczka': ('beczka', 'beczki', 'beczek', 'beczki'),
};

/// Nazwa opakowania do liczby [n] (null: forma do pustego pola, „zgrzewek”).
String packWord(String? packName, double? n) {
  if (packName == null) return 'op.';
  final forms = _packForms[packName.trim().toLowerCase()];
  if (forms == null) return packName;
  if (n == null) return forms.$3;
  if (n != n.roundToDouble()) return forms.$4;
  final i = n.round().abs();
  if (i == 1) return forms.$1;
  final last = i % 10, tens = i % 100;
  return last >= 2 && last <= 4 && (tens < 12 || tens > 14) ? forms.$2 : forms.$3;
}

/// „11 zgrzewek”, „2,5 worka”, „3 op.”.
String packCount(double n, String? packName) => '${inventoryNumber(n)} ${packWord(packName, n)}';
