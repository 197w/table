-- Rarytka · dane przykładowe do testów
-- Uruchom po wszystkich migracjach. Lokale, adresy, NIP-y i opinie są fikcyjne
-- i oznaczone polem is_example, żeby aplikacja pokazywała je jako przykłady.

insert into public.restaurants
  (id, name, cuisine, price_level, description, address, city, phone, nip, location, plan, is_example)
values
  ('0a000000-0000-4000-8000-000000000001', 'Pierogarnia Na Mostku', 'polska', 2,
   'Pierogi lepione na miejscu i domowe zupy.', 'ul. Przykładowa 1', 'Białystok',
   '+48850000001', '1111111101', 'SRID=4326;POINT(23.1587 53.1325)', 'pro', true),
  ('0a000000-0000-4000-8000-000000000002', 'Trattoria Oliwka', 'wloska', 3,
   'Świeży makaron i pizza z pieca opalanego drewnem.', 'ul. Przykładowa 2', 'Białystok',
   '+48850000002', '1111111102', 'SRID=4326;POINT(23.1520 53.1335)', 'pro', true),
  ('0a000000-0000-4000-8000-000000000003', 'Sushi Kaze', 'japonska', 3,
   'Sushi, ramen i krótka karta sake.', 'ul. Przykładowa 3', 'Białystok',
   '+48850000003', '1111111103', 'SRID=4326;POINT(23.1720 53.1360)', 'free', true),
  ('0a000000-0000-4000-8000-000000000004', 'Pho Lotos', 'wietnamska', 1,
   'Zupa pho gotowana przez całą noc.', 'ul. Przykładowa 4', 'Białystok',
   '+48850000004', '1111111104', 'SRID=4326;POINT(23.1560 53.1245)', 'pro', true),
  ('0a000000-0000-4000-8000-000000000005', 'Gruzińska Chata', 'gruzinska', 2,
   'Chinkali, chaczapuri i gruzińskie wina.', 'ul. Przykładowa 5', 'Białystok',
   '+48850000005', '1111111105', 'SRID=4326;POINT(23.1650 53.1255)', 'free', true),
  ('0a000000-0000-4000-8000-000000000006', 'Zielony Talerz', 'weganska', 2,
   'Sezonowa kuchnia roślinna.', 'ul. Przykładowa 6', 'Białystok',
   '+48850000006', '1111111106', 'SRID=4326;POINT(23.1660 53.1380)', 'pro', true),
  ('0a000000-0000-4000-8000-000000000007', 'Bistro Lumière', 'francuska', 4,
   'Klasyczne bistro z menu degustacyjnym.', 'ul. Przykładowa 7', 'Białystok',
   '+48850000007', '1111111107', 'SRID=4326;POINT(23.1610 53.1300)', 'free', true),
  ('0a000000-0000-4000-8000-000000000008', 'Masala Dom', 'indyjska', 2,
   'Curry z własnych mieszanek przypraw.', 'ul. Przykładowa 8', 'Białystok',
   '+48850000008', '1111111108', 'SRID=4326;POINT(23.1420 53.1480)', 'pro', true);

-- Godziny otwarcia: codziennie od 12:00, w piątek i sobotę do 23:00.
insert into public.opening_hours (restaurant_id, weekday, opens, closes)
select r.id, d, time '12:00',
       case when d in (5, 6) then time '23:00' else time '22:00' end
from public.restaurants r
cross join generate_series(1, 7) as d
where r.is_example;

-- Stoliki dla lokali z planem Pro.
insert into public.dining_tables
  (restaurant_id, label, seats, width_cm, height_cm, zone, join_group, priority)
select r.id, t.label, t.seats, t.w, t.h, t.zone, t.join_group, t.priority
from public.restaurants r
cross join (values
  ('S1', 2,  70, 70, 'sala', null::text, 0),
  ('S2', 2,  70, 70, 'sala', null,       0),
  ('S3', 4, 120, 80, 'sala', null,       1),
  ('S4', 4, 120, 80, 'sala', null,       1),
  ('S5', 6, 180, 90, 'sala', null,       0),
  ('O1', 2,  70, 70, 'okno', 'okno',     0),
  ('O2', 2,  70, 70, 'okno', 'okno',     0)
) as t(label, seats, w, h, zone, join_group, priority)
where r.is_example and r.plan = 'pro';

-- Menu.
do $$
declare
  v_rest   jsonb;
  v_sec    jsonb;
  v_item   jsonb;
  v_sec_id uuid;
  v_spos   integer;
  v_ipos   integer;
begin
  for v_rest in select value from jsonb_array_elements($json$
  [
    {"id":"0a000000-0000-4000-8000-000000000001","sections":[
      {"name":"Zupy","items":[
        {"name":"Żurek na zakwasie","desc":"Z białą kiełbasą i jajkiem","price":2200,"allergens":["gluten","jaja","gorczyca"]},
        {"name":"Rosół z makaronem","desc":"Gotowany 6 godzin","price":1800,"allergens":["gluten","seler"]}]},
      {"name":"Pierogi","items":[
        {"name":"Ruskie","desc":"Z twarogiem i ziemniakami, 8 sztuk","price":3200,"allergens":["gluten","mleko"]},
        {"name":"Z kaczką","desc":"Z sosem żurawinowym, 8 sztuk","price":4200,"allergens":["gluten"]},
        {"name":"Z jagodami","desc":"Ze śmietaną, 8 sztuk","price":3400,"allergens":["gluten","mleko"]}]}]},
    {"id":"0a000000-0000-4000-8000-000000000002","sections":[
      {"name":"Antipasti","items":[
        {"name":"Burrata","desc":"Z pomidorami i bazylią","price":4600,"allergens":["mleko"]},
        {"name":"Vitello tonnato","desc":"Cielęcina z sosem z tuńczyka","price":4900,"allergens":["ryby","jaja"]}]},
      {"name":"Pasta i pizza","items":[
        {"name":"Tagliatelle al ragù","desc":"Makaron robiony na miejscu","price":5200,"allergens":["gluten","jaja","seler"]},
        {"name":"Pizza Margherita","desc":"Mąka typu 00, mozzarella fior di latte","price":3900,"allergens":["gluten","mleko"]}]}]},
    {"id":"0a000000-0000-4000-8000-000000000003","sections":[
      {"name":"Sushi","items":[
        {"name":"Nigiri z łososiem","desc":"2 sztuki","price":2400,"allergens":["ryby","soja"]},
        {"name":"Futomaki z krewetką","desc":"8 sztuk","price":4800,"allergens":["skorupiaki","sezam","soja"]}]},
      {"name":"Ramen","items":[
        {"name":"Tonkotsu","desc":"Bulion wieprzowy, jajko marynowane","price":4400,"allergens":["gluten","jaja","soja","sezam"]}]}]},
    {"id":"0a000000-0000-4000-8000-000000000004","sections":[
      {"name":"Zupy","items":[
        {"name":"Pho bo","desc":"Z wołowiną i świeżymi ziołami","price":3600,"allergens":["soja"]},
        {"name":"Pho ga","desc":"Z kurczakiem","price":3200,"allergens":["soja"]}]},
      {"name":"Przystawki","items":[
        {"name":"Nem","desc":"Smażone sajgonki, 4 sztuki","price":1900,"allergens":["gluten","skorupiaki"]}]}]},
    {"id":"0a000000-0000-4000-8000-000000000005","sections":[
      {"name":"Chinkali","items":[
        {"name":"Chinkali z mięsem","desc":"5 sztuk","price":3500,"allergens":["gluten"]},
        {"name":"Chinkali z serem","desc":"5 sztuk","price":3200,"allergens":["gluten","mleko"]}]},
      {"name":"Z pieca","items":[
        {"name":"Chaczapuri po adżarsku","desc":"Z jajkiem i masłem","price":3800,"allergens":["gluten","mleko","jaja"]}]}]},
    {"id":"0a000000-0000-4000-8000-000000000006","sections":[
      {"name":"Talerze","items":[
        {"name":"Pieczony kalafior","desc":"Z tahini i granatem","price":3600,"allergens":["sezam"]},
        {"name":"Risotto z dynią","desc":"Z pestkami i szałwią","price":4200,"allergens":["seler"]}]},
      {"name":"Desery","items":[
        {"name":"Tarta czekoladowa","desc":"Na spodzie z orzechów","price":2200,"allergens":["orzechy"]}]}]},
    {"id":"0a000000-0000-4000-8000-000000000007","sections":[
      {"name":"Entrées","items":[
        {"name":"Zupa cebulowa","desc":"Z grzanką i gruyère","price":3400,"allergens":["gluten","mleko"]},
        {"name":"Tatar wołowy","desc":"Z żółtkiem i kaparami","price":5800,"allergens":["jaja","gorczyca"]}]},
      {"name":"Plats","items":[
        {"name":"Confit z kaczki","desc":"Z ziemniakami sarladaise","price":8900,"allergens":[]}]}]},
    {"id":"0a000000-0000-4000-8000-000000000008","sections":[
      {"name":"Curry","items":[
        {"name":"Butter chicken","desc":"Z ryżem basmati","price":4200,"allergens":["mleko","orzechy"]},
        {"name":"Chana masala","desc":"Z ciecierzycą, wegańskie","price":3400,"allergens":[]}]},
      {"name":"Pieczywo","items":[
        {"name":"Naan czosnkowy","desc":"Z pieca tandoor","price":1200,"allergens":["gluten","mleko"]}]}]}
  ]
  $json$::jsonb)
  loop
    v_spos := 0;
    for v_sec in select value from jsonb_array_elements(v_rest -> 'sections')
    loop
      insert into public.menu_sections (restaurant_id, name, position)
      values ((v_rest ->> 'id')::uuid, v_sec ->> 'name', v_spos)
      returning id into v_sec_id;

      v_ipos := 0;
      for v_item in select value from jsonb_array_elements(v_sec -> 'items')
      loop
        insert into public.menu_items (section_id, name, description, price_grosze, allergens, position)
        values (
          v_sec_id,
          v_item ->> 'name',
          v_item ->> 'desc',
          (v_item ->> 'price')::integer,
          array(select jsonb_array_elements_text(v_item -> 'allergens')),
          v_ipos
        );
        v_ipos := v_ipos + 1;
      end loop;

      v_spos := v_spos + 1;
    end loop;
  end loop;
end
$$;

-- Opinie przykładowe. „receipt” liczy się do rankingu, „none” nie.
insert into public.reviews
  (restaurant_id, food, service, ambience, body, verification, seed_author, created_at)
values
  ('0a000000-0000-4000-8000-000000000001', 5, 4, 4, 'Ruskie jak u babci, żurek bardzo kwaśny i dobry.', 'receipt', 'Marta', now() - interval '3 days'),
  ('0a000000-0000-4000-8000-000000000001', 5, 5, 4, 'Pierogi z kaczką to obowiązkowy punkt.', 'receipt', 'Tomek', now() - interval '9 days'),
  ('0a000000-0000-4000-8000-000000000001', 4, 3, 3, 'Smacznie, ale długo czekaliśmy.', 'receipt', 'Ola', now() - interval '20 days'),
  ('0a000000-0000-4000-8000-000000000001', 5, 5, 5, 'Najlepsze pierogi w mieście!', 'none', 'Kasia', now() - interval '1 day'),

  ('0a000000-0000-4000-8000-000000000002', 5, 5, 5, 'Makaron świeży, ragù jak we Włoszech.', 'receipt', 'Piotr', now() - interval '2 days'),
  ('0a000000-0000-4000-8000-000000000002', 5, 4, 5, 'Burrata perfekcyjna.', 'receipt', 'Julia', now() - interval '6 days'),
  ('0a000000-0000-4000-8000-000000000002', 4, 4, 5, 'Pizza dobra, ale ciasto mogłoby być lżejsze.', 'receipt', 'Kuba', now() - interval '14 days'),
  ('0a000000-0000-4000-8000-000000000002', 5, 5, 4, 'Wracamy co tydzień.', 'receipt', 'Agnieszka', now() - interval '30 days'),
  ('0a000000-0000-4000-8000-000000000002', 2, 2, 3, 'Nie polecam.', 'none', 'Anonim', now() - interval '4 days'),

  ('0a000000-0000-4000-8000-000000000003', 4, 4, 3, 'Ramen konkretny, sushi poprawne.', 'receipt', 'Michał', now() - interval '5 days'),
  ('0a000000-0000-4000-8000-000000000003', 5, 4, 4, 'Nigiri z łososiem rozpływa się w ustach.', 'none', 'Ewa', now() - interval '8 days'),

  ('0a000000-0000-4000-8000-000000000004', 5, 4, 3, 'Pho bo z prawdziwym, głębokim bulionem.', 'receipt', 'Łukasz', now() - interval '1 day'),
  ('0a000000-0000-4000-8000-000000000004', 5, 3, 3, 'Tanio i bardzo smacznie.', 'receipt', 'Natalia', now() - interval '11 days'),
  ('0a000000-0000-4000-8000-000000000004', 4, 4, 3, 'Nem chrupiące, pho trochę za słone.', 'receipt', 'Bartek', now() - interval '25 days'),

  ('0a000000-0000-4000-8000-000000000005', 4, 5, 5, 'Świetna atmosfera, chinkali mogłyby być soczystsze.', 'receipt', 'Zosia', now() - interval '7 days'),
  ('0a000000-0000-4000-8000-000000000005', 5, 5, 5, 'Chaczapuri rewelacyjne!', 'none', 'Adam', now() - interval '2 days'),
  ('0a000000-0000-4000-8000-000000000005', 5, 5, 5, 'Idealne na urodziny.', 'none', 'Iga', now() - interval '3 days'),

  ('0a000000-0000-4000-8000-000000000006', 4, 5, 4, 'Kalafior z tahini zaskakująco dobry.', 'receipt', 'Weronika', now() - interval '4 days'),
  ('0a000000-0000-4000-8000-000000000006', 4, 4, 4, 'Dobre risotto, porcje niewielkie.', 'receipt', 'Filip', now() - interval '16 days'),

  ('0a000000-0000-4000-8000-000000000007', 5, 5, 5, 'Confit z kaczki na poziomie Paryża.', 'receipt', 'Magda', now() - interval '10 days'),

  ('0a000000-0000-4000-8000-000000000008', 5, 4, 3, 'Butter chicken najlepszy, jaki jadłem.', 'receipt', 'Kamil', now() - interval '2 days'),
  ('0a000000-0000-4000-8000-000000000008', 4, 4, 3, 'Chana masala mocno przyprawiona, w dobrym sensie.', 'receipt', 'Paula', now() - interval '12 days'),
  ('0a000000-0000-4000-8000-000000000008', 5, 3, 3, 'Naan świeży z pieca.', 'receipt', 'Olek', now() - interval '18 days');
