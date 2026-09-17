/// Błąd z komunikatem gotowym do pokazania użytkownikowi.
class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
