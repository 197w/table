-- Table · dane przykładowe: Kraków
-- Uruchom po seed.sql. Lokale, adresy, NIP-y i opinie są fikcyjne.

insert into public.restaurants
  (id, name, cuisine, price_level, description, address, city, phone, nip, location, plan, is_example)
values
  ('0a000000-0000-4000-8000-000000000009', 'Stary Młyn', 'polska', 2,
   'Kuchnia małopolska: kwaśnica, placki i oscypek z żurawiną.', 'ul. Przykładowa 9', 'Kraków',
   '+48120000009', '2222222209', 'SRID=4326;POINT(19.9370 50.0617)', 'pro', true),
  ('0a000000-0000-4000-8000-000000000010', 'Osteria Kazimierz', 'wloska', 3,
   'Małe menu, codziennie inny makaron i włoskie wina.', 'ul. Przykładowa 10', 'Kraków',
   '+48120000010', '2222222210', 'SRID=4326;POINT(19.9450 50.0510)', 'pro', true),
  ('0a000000-0000-4000-8000-000000000011', 'Umami Bar', 'japonska', 3,
   'Ramen na bulionie z kości i izakaya do późna.', 'ul. Przykładowa 11', 'Kraków',
   '+48120000011', '2222222211', 'SRID=4326;POINT(19.9500 50.0450)', 'free', true),
  ('0a000000-0000-4000-8000-000000000012', 'Curry House', 'indyjska', 1,
   'Szybkie curry i thali w rozsądnych cenach.', 'ul. Przykładowa 12', 'Kraków',
   '+48120000012', '2222222212', 'SRID=4326;POINT(19.9400 50.0680)', 'pro', true),
  ('0a000000-0000-4000-8000-000000000013', 'Roślinna Spiżarnia', 'weganska', 2,
   'Roślinne śniadania do 16:00 i kolacje z lokalnych warzyw.', 'ul. Przykładowa 13', 'Kraków',
   '+48120000013', '2222222213', 'SRID=4326;POINT(19.9280 50.0570)', 'free', true),
  ('0a000000-0000-4000-8000-000000000014', 'Maison Wawel', 'francuska', 4,
   'Menu degustacyjne z widokiem na Wawel.', 'ul. Przykładowa 14', 'Kraków',
   '+48120000014', '2222222214', 'SRID=4326;POINT(19.9350 50.0540)', 'pro', true);

-- Godziny otwarcia: codziennie od 12:00, w piątek i sobotę do 23:00.
insert into public.opening_hours (restaurant_id, weekday, opens, closes)
select r.id, d, time '12:00',
       case when d in (5, 6) then time '23:00' else time '22:00' end
from public.restaurants r
cross join generate_series(1, 7) as d
where r.city = 'Kraków' and r.is_example;

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
where r.city = 'Kraków' and r.is_example and r.plan = 'pro';

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
    {"id":"0a000000-0000-4000-8000-000000000009","sections":[
      {"name":"Zupy","items":[
        {"name":"Kwaśnica na żeberkach","desc":"Z ziemniakami","price":2400,"allergens":["seler"]},
        {"name":"Barszcz z uszkami","desc":"Uszka z grzybami","price":2200,"allergens":["gluten","seler"]}]},
      {"name":"Dania główne","items":[
        {"name":"Placek po zbójnicku","desc":"Z gulaszem wołowym","price":4600,"allergens":["gluten","jaja","mleko"]},
        {"name":"Grillowany oscypek","desc":"Z żurawiną","price":2800,"allergens":["mleko"]}]}]},
    {"id":"0a000000-0000-4000-8000-000000000010","sections":[
      {"name":"Primi","items":[
        {"name":"Cacio e pepe","desc":"Pecorino i czarny pieprz","price":4400,"allergens":["gluten","mleko"]},
        {"name":"Pappardelle z dzikiem","desc":"Ragù gotowane 8 godzin","price":5600,"allergens":["gluten","jaja","seler"]}]},
      {"name":"Dolci","items":[
        {"name":"Tiramisu","desc":"Z mascarpone","price":2600,"allergens":["gluten","jaja","mleko"]}]}]},
    {"id":"0a000000-0000-4000-8000-000000000011","sections":[
      {"name":"Ramen","items":[
        {"name":"Shoyu ramen","desc":"Bulion z kurczaka, sos sojowy","price":4200,"allergens":["gluten","jaja","soja"]},
        {"name":"Miso ramen","desc":"Z kukurydzą i masłem","price":4400,"allergens":["gluten","soja","mleko"]}]},
      {"name":"Izakaya","items":[
        {"name":"Karaage","desc":"Smażony kurczak po japońsku","price":2900,"allergens":["gluten","soja"]}]}]},
    {"id":"0a000000-0000-4000-8000-000000000012","sections":[
      {"name":"Curry","items":[
        {"name":"Chicken tikka masala","desc":"Z ryżem basmati","price":3200,"allergens":["mleko"]},
        {"name":"Dal tadka","desc":"Soczewica z czosnkiem, wegańskie","price":2400,"allergens":[]}]},
      {"name":"Thali","items":[
        {"name":"Thali wegetariańskie","desc":"Trzy curry, ryż, naan i raita","price":3600,"allergens":["gluten","mleko"]}]}]},
    {"id":"0a000000-0000-4000-8000-000000000013","sections":[
      {"name":"Śniadania","items":[
        {"name":"Szakszuka z tofu","desc":"Z pieczywem na zakwasie","price":3200,"allergens":["gluten","soja"]}]},
      {"name":"Kolacje","items":[
        {"name":"Pierogi z soczewicą","desc":"Z cebulką i majerankiem","price":3400,"allergens":["gluten"]},
        {"name":"Burger z buraka","desc":"Z frytkami z batata","price":3800,"allergens":["gluten","sezam","gorczyca"]}]}]},
    {"id":"0a000000-0000-4000-8000-000000000014","sections":[
      {"name":"Menu degustacyjne","items":[
        {"name":"Degustacja 5 dań","desc":"Zmienia się co miesiąc","price":32000,"allergens":["gluten","mleko","jaja","ryby"]},
        {"name":"Dobór win","desc":"5 kieliszków","price":18000,"allergens":["siarczyny"]}]},
      {"name":"À la carte","items":[
        {"name":"Przegrzebki","desc":"Z masłem brązowym i kalafiorem","price":8400,"allergens":["mięczaki","mleko"]}]}]}
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

-- Opinie przykładowe z ceną na osobę. „receipt” liczy się do rankingu i poziomu cen, „none” nie.
insert into public.reviews
  (restaurant_id, food, service, ambience, body, verification, seed_author, price_per_person, created_at)
values
  ('0a000000-0000-4000-8000-000000000009', 5, 4, 5, 'Kwaśnica jak w górach, placek ogromny.', 'receipt', 'Grzegorz', 55, now() - interval '2 days'),
  ('0a000000-0000-4000-8000-000000000009', 4, 4, 4, 'Dobre jedzenie, w weekend tłoczno.', 'receipt', 'Monika', 48, now() - interval '12 days'),
  ('0a000000-0000-4000-8000-000000000009', 5, 5, 5, 'Oscypek z żurawiną to hit.', 'none', 'Hania', null, now() - interval '1 day'),

  ('0a000000-0000-4000-8000-000000000010', 5, 5, 4, 'Cacio e pepe idealne, jak w Rzymie.', 'receipt', 'Dawid', 75, now() - interval '3 days'),
  ('0a000000-0000-4000-8000-000000000010', 5, 4, 5, 'Pappardelle z dzikiem zostaną w pamięci.', 'receipt', 'Karolina', 82, now() - interval '9 days'),
  ('0a000000-0000-4000-8000-000000000010', 4, 5, 5, 'Świetna obsługa i wina.', 'receipt', 'Adrian', 70, now() - interval '21 days'),

  ('0a000000-0000-4000-8000-000000000011', 4, 3, 4, 'Ramen dobry, karaage jeszcze lepsze.', 'receipt', 'Sebastian', 60, now() - interval '4 days'),
  ('0a000000-0000-4000-8000-000000000011', 3, 3, 4, 'Bulion trochę za mdły.', 'none', 'Maja', null, now() - interval '6 days'),

  ('0a000000-0000-4000-8000-000000000012', 4, 4, 3, 'Thali za takie pieniądze to okazja.', 'receipt', 'Wojtek', 32, now() - interval '5 days'),
  ('0a000000-0000-4000-8000-000000000012', 5, 3, 3, 'Tikka masala bardzo aromatyczna.', 'receipt', 'Dominika', 28, now() - interval '15 days'),

  ('0a000000-0000-4000-8000-000000000013', 5, 5, 4, 'Najlepsze wegańskie śniadanie w Krakowie.', 'receipt', 'Alicja', 45, now() - interval '2 days'),
  ('0a000000-0000-4000-8000-000000000013', 4, 4, 4, 'Burger z buraka zaskakująco sycący.', 'receipt', 'Marek', 42, now() - interval '17 days'),

  ('0a000000-0000-4000-8000-000000000014', 5, 5, 5, 'Degustacja dopracowana w każdym szczególe.', 'receipt', 'Beata', 420, now() - interval '8 days'),
  ('0a000000-0000-4000-8000-000000000014', 5, 4, 5, 'Drogo, ale warto na wyjątkową okazję.', 'receipt', 'Jan', 380, now() - interval '19 days');
