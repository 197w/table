/// Język interfejsu. Na razie zapisujemy tylko wybór, tłumaczeń jeszcze nie ma.
enum AppLanguage {
  pl('Polski'),
  en('English');

  const AppLanguage(this.label);
  final String label;
}

enum DistanceUnit {
  kilometers('Kilometry', 'km'),
  miles('Mile', 'mi');

  const DistanceUnit(this.label, this.short);
  final String label;
  final String short;
}
