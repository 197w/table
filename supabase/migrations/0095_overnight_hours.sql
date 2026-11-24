-- Godziny otwarcia po północy (24.11.2026, prośba użytkownika: „dalej nie da się ustawić godziny zamknięcia lokalu po
-- północy”). Zamknięcie wcześniejsze niż otwarcie (12:00–02:00) albo równe otwarciu to zamknięcie następnego dnia;
-- zamknięcie o 24:00 (północ) działało już wcześniej. Do tej pory baza wymagała `closes > opens`, więc 12:00–02:00
-- było odrzucane, a przy odczycie godzin brakowało nocnej końcówki poprzedniego dnia.
--
-- Okno otwarcia dnia ([private.open_window]) to początek i koniec jako chwile czasu lokalnego, koniec po północy
-- następnego dnia. Wolne godziny rezerwacji, rezerwacja stolika i zamówienie na godzinę liczą się na tych oknach:
-- chwila po północy należy do okna poprzedniego dnia.

alter table public.opening_hours drop constraint opening_hours_check;
alter table public.opening_hours add constraint opening_hours_check check (closes <> opens);
alter table public.opening_exceptions drop constraint opening_exceptions_check;
alter table public.opening_exceptions
  add constraint opening_exceptions_check check (closed or (opens is not null and closes is not null and closes <> opens));

create or replace function private.open_window(p_restaurant_id uuid, p_date date)
returns table (starts timestamp, ends timestamp)
language sql
stable
security definer
set search_path = 'public'
as $$
  select p_date + x.opens,
         p_date + x.closes + case when x.closes <= x.opens then interval '1 day' else interval '0' end
  from private.hours_on(p_restaurant_id, p_date) as x
$$;
revoke execute on function private.open_window(uuid, date) from public, anon;

-- Wolne godziny stolika w dniu [p_date], także te po północy (do końca okna otwarcia).
create or replace function public.available_slots(p_restaurant_id uuid, p_date date, p_party_size integer)
returns table (slot_start timestamp with time zone)
language sql
stable
security definer
set search_path = 'public'
as $$
  with r as (
    select id, timezone, slot_interval_min, max_party_size
    from restaurants
    where id = p_restaurant_id and plan = 'pro'
  ),
  h as (
    select w.starts, w.ends
    from r, private.open_window(r.id, p_date) as w
  ),
  d as (
    select private.visit_minutes(p_party_size) as visit,
           private.cleanup_minutes(p_party_size) as cleanup
  ),
  series as (
    select (gs at time zone r.timezone) as starts_at, d.visit, d.cleanup
    from r, h, d,
      generate_series(
        h.starts,
        h.ends - make_interval(mins => d.visit),
        make_interval(mins => r.slot_interval_min)
      ) as gs
  )
  select s.starts_at
  from series s
  where p_party_size between 1 and (select max_party_size from r)
    and s.starts_at > now() + interval '30 minutes'
    and private.find_tables(
          p_restaurant_id,
          p_party_size,
          tstzrange(s.starts_at, s.starts_at + make_interval(mins => s.visit + s.cleanup))
        ) is not null
  order by s.starts_at
$$;

-- Zamówienie na godzinę: godzina musi mieścić się w oknie otwarcia tego dnia albo nocnej końcówce poprzedniego.
-- Liczą się też dni wyjątkowe (zamknięte dni blokują zamówienie).
create or replace function private.check_scheduled(p_restaurant_id uuid, p_kind text, p_when timestamp with time zone, p_guest boolean)
returns timestamp with time zone
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r      public.restaurants%rowtype;
  v_when   timestamptz := date_trunc('minute', p_when);
  v_min    timestamptz;
  v_local  timestamp;
begin
  if p_when is null then
    return null;
  end if;
  if p_kind not in ('delivery', 'pickup') then
    raise exception 'Na godzinę można zamówić tylko na wynos albo z dostawą.';
  end if;
  select * into v_r from public.restaurants where id = p_restaurant_id;
  if v_when > now() + interval '7 days' then
    raise exception 'Na godzinę można zamówić najwyżej 7 dni naprzód.';
  end if;
  if not p_guest then
    if v_when <= now() then
      raise exception 'Wybierz godzinę, która jeszcze nie minęła.';
    end if;
    return v_when;
  end if;

  v_min := now() + make_interval(mins => greatest(15,
    case when p_kind = 'delivery' then v_r.kitchen_lead_delivery_min else v_r.kitchen_lead_pickup_min end));
  if v_when < v_min then
    raise exception 'Na tę godzinę lokal nie zdąży. Najwcześniej na %.',
      to_char(v_min at time zone coalesce(v_r.timezone, 'Europe/Warsaw'), 'HH24:MI');
  end if;
  v_local := v_when at time zone coalesce(v_r.timezone, 'Europe/Warsaw');
  if exists (select 1 from public.opening_hours where restaurant_id = p_restaurant_id)
     and not exists (
       select 1
       from (
         select * from private.open_window(p_restaurant_id, v_local::date)
         union all
         select * from private.open_window(p_restaurant_id, v_local::date - 1)
       ) w
       where v_local between w.starts and w.ends
     ) then
    raise exception 'Lokal jest wtedy zamknięty. Wybierz godzinę otwarcia.';
  end if;
  return v_when;
end;
$$;

-- Zapis godzin otwarcia: zamknięcie inne niż otwarcie (wcześniejsze znaczy: następnego dnia).
create or replace function public.panel_set_hours(p_restaurant_id uuid, p_hours jsonb)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  perform private.require_staff(p_restaurant_id, 'manager');

  delete from opening_hours where restaurant_id = p_restaurant_id;

  insert into opening_hours (restaurant_id, weekday, opens, closes)
  select p_restaurant_id, (h ->> 'weekday')::smallint, (h ->> 'opens')::time, (h ->> 'closes')::time
  from jsonb_array_elements(coalesce(p_hours, '[]'::jsonb)) as h;
exception
  when check_violation then
    raise exception 'Godzina zamknięcia musi być inna niż otwarcia (wcześniejsza oznacza zamknięcie po północy).';
  when unique_violation then
    raise exception 'Każdy dzień tygodnia może mieć tylko jedne godziny otwarcia.';
end;
$$;

-- Rezerwacja stolika w aplikacji: wizyta mieści się w oknie otwarcia swojego dnia albo w nocnej końcówce poprzedniego.
do $$
declare
  v_def text;
  v_old text := E'  select x.opens, x.closes into v_hours\n  from private.hours_on(p_restaurant_id, v_local::date) as x;\n\n  if not found\n     or v_local::time < v_hours.opens\n     or v_local + make_interval(mins => v_visit) > v_local::date + v_hours.closes then\n    raise exception ''Restauracja jest wtedy zamknięta.'';\n  end if;';
  v_new text := E'  select w.starts, w.ends into v_hours\n  from (\n    select * from private.open_window(p_restaurant_id, v_local::date)\n    union all\n    select * from private.open_window(p_restaurant_id, v_local::date - 1)\n  ) w\n  where v_local >= w.starts and v_local + make_interval(mins => v_visit) <= w.ends\n  limit 1;\n\n  if not found then\n    raise exception ''Restauracja jest wtedy zamknięta.'';\n  end if;';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'book_table';
  if position(v_old in v_def) = 0 then
    raise exception 'book_table nie ma oczekiwanego sprawdzenia godzin';
  end if;
  execute replace(v_def, v_old, v_new);
end;
$$;
