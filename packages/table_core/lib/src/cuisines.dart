/// Rodzaje kuchni lokali: klucz w bazie (`restaurants.cuisine`) i nazwa. Wspólne dla panelu (wybór w „Dane lokalu”
/// i przy zakładaniu lokalu) i aplikacji Table (kategorie w Odkrywaj z ilustracjami `assets/cuisines/<klucz>.webp`).
///
/// Kuchnie świata od 27.11.2026 (prośba użytkownika: „zrób wszystkie kuchnie, które istnieją na świecie, ale niech
/// pokazuje tylko kuchnie, które są w twoim mieście”). Kolejność alfabetyczna po polsku, „Inna” na końcu. Nowa kuchnia
/// potrzebuje też ilustracji w aplikacji Table (bez niej pokazuje się ilustracja „Inna”).
library;

const cuisineNames = <String, String>{
  'afrykanska': 'Afrykańska',
  'amerykanska': 'Amerykańska',
  'argentynska': 'Argentyńska',
  'australijska': 'Australijska',
  'azjatycka': 'Azjatycka',
  'balkanska': 'Bałkańska',
  'bliskowschodnia': 'Bliskowschodnia',
  'brazylijska': 'Brazylijska',
  'brytyjska': 'Brytyjska',
  'chinska': 'Chińska',
  'cukiernia': 'Cukiernia',
  'filipinska': 'Filipińska',
  'francuska': 'Francuska',
  'grecka': 'Grecka',
  'gruzinska': 'Gruzińska',
  'hawajska': 'Hawajska',
  'hiszpanska': 'Hiszpańska',
  'indonezyjska': 'Indonezyjska',
  'indyjska': 'Indyjska',
  'irlandzka': 'Irlandzka',
  'izraelska': 'Izraelska',
  'japonska': 'Japońska',
  'kanadyjska': 'Kanadyjska',
  'karaibska': 'Karaibska',
  'kawiarnia': 'Kawiarnia',
  'koreanska': 'Koreańska',
  'kubanska': 'Kubańska',
  'litewska': 'Litewska',
  'marokanska': 'Marokańska',
  'meksykanska': 'Meksykańska',
  'nepalska': 'Nepalska',
  'niemiecka': 'Niemiecka',
  'owoce_morza': 'Owoce morza',
  'perska': 'Perska',
  'peruwianska': 'Peruwiańska',
  'polska': 'Polska',
  'portugalska': 'Portugalska',
  'rosyjska': 'Rosyjska',
  'skandynawska': 'Skandynawska',
  'steki': 'Steki',
  'szwajcarska': 'Szwajcarska',
  'srodziemnomorska': 'Śródziemnomorska',
  'tajska': 'Tajska',
  'tajwanska': 'Tajwańska',
  'turecka': 'Turecka',
  'ukrainska': 'Ukraińska',
  'uzbecka': 'Uzbecka',
  'weganska': 'Wegańska',
  'wegetarianska': 'Wegetariańska',
  'wegierska': 'Węgierska',
  'wietnamska': 'Wietnamska',
  'wloska': 'Włoska',
  'zydowska': 'Żydowska',
  'inna': 'Inna',
};

/// Rodzaje lokali, których nazwa nie jest przymiotnikiem kuchni („kuchnia kawiarnia” byłoby błędem).
const _notCuisineAdjective = {'cukiernia', 'kawiarnia', 'owoce_morza', 'steki', 'inna'};

/// Nazwa kuchni, np. „Polska”. Nieznany klucz: z wielkiej litery.
String cuisineLabel(String slug) {
  final label = cuisineNames[slug];
  if (label != null) return label;
  if (slug.isEmpty) return slug;
  return slug[0].toUpperCase() + slug.substring(1).replaceAll('_', ' ');
}

/// Kuchnia w zdaniu, małymi literami: „kuchnia polska”, ale „kawiarnia”, „owoce morza”, „inna kuchnia”.
String cuisinePhrase(String slug) {
  if (slug == 'inna') return 'inna kuchnia';
  final label = cuisineLabel(slug).toLowerCase();
  return _notCuisineAdjective.contains(slug) ? label : 'kuchnia $label';
}

/// Miejsce kuchni na listach (kolejność [cuisineNames]); nieznane na końcu.
int cuisineOrder(String slug) {
  final i = cuisineNames.keys.toList().indexOf(slug);
  return i < 0 ? cuisineNames.length : i;
}
