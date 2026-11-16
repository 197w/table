-- Sezonowe działy menu i menu przypinane do wydarzenia z Kalendarza (16.11.2026, prośba użytkownika: „zmień wygląd
-- Menu na nowy, dodaj możliwość tworzenia sezonowych sekcji menu na daty okres” i „w Kalendarz dodaj możliwość
-- przypisania menu do danego wydarzenia”).
--
-- Dział sezonowy ma okres od–do (dni, bez godzin). Z „co roku” liczy się tylko miesiąc i dzień, a okres może
-- przechodzić przez Nowy Rok (1 grudnia – 6 stycznia). Poza okresem dział znika u gościa, w Zamówieniach panelu
-- i u kelnera (aplikacje filtrują jak działy na wydarzenie), a baza nie przyjmuje z niego nowych pozycji.
-- Dział ma okres albo wydarzenie, nie oba naraz.

alter table public.menu_sections
  add column season_from   date,
  add column season_to     date,
  add column season_yearly boolean not null default false,
  add constraint menu_sections_season_pair check ((season_from is null) = (season_to is null)),
  add constraint menu_sections_season_order check (season_yearly or season_from is null or season_from <= season_to),
  add constraint menu_sections_season_or_event check (season_from is null or event_id is null);

grant select (season_from, season_to, season_yearly) on public.menu_sections to anon, authenticated;
grant insert (season_from, season_to, season_yearly), update (season_from, season_to, season_yearly)
  on public.menu_sections to authenticated;

-- Czy dzień mieści się w okresie. Bez okresu zawsze tak. „Co roku”: porównujemy miesiąc i dzień (MMDD).
create or replace function private.season_active(p_from date, p_to date, p_yearly boolean, p_day date)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_from is null or p_to is null then true
    when not p_yearly then p_day between p_from and p_to
    else (
      with md as (
        select extract(month from p_from)::int * 100 + extract(day from p_from)::int as f,
               extract(month from p_to)::int * 100 + extract(day from p_to)::int as t,
               extract(month from p_day)::int * 100 + extract(day from p_day)::int as x
      )
      select case when f <= t then x between f and t else (x >= f or x <= t) end from md
    )
  end
$$;

revoke execute on function private.season_active(date, date, boolean, date) from public, anon;
grant execute on function private.season_active(date, date, boolean, date) to authenticated;

-- Dania z działu na wydarzenie albo sezonowego da się nabić tylko w jego czasie (przy zamówieniu na godzinę:
-- o tej godzinie; dzień sezonu liczymy w strefie lokalu). Sprawdzamy tylko nowe pozycje (stan „new”): kopie przy
-- płatności za część rachunku przechodzą.
create or replace function private.event_menu_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  s record;
  v_at timestamptz;
begin
  if new.menu_item_id is null or new.status is distinct from 'new' then
    return new;
  end if;
  select sec.name, sec.season_from, sec.season_to, sec.season_yearly, e.title as event_title,
         e.starts_at, e.ends_at, r.timezone
    into s
  from public.menu_items mi
  join public.menu_sections sec on sec.id = mi.section_id
  join public.restaurants r on r.id = sec.restaurant_id
  left join public.calendar_events e on e.id = sec.event_id
  where mi.id = new.menu_item_id;
  if not found or (s.event_title is null and s.season_from is null) then
    return new;
  end if;
  select coalesce(o.scheduled_for, now()) into v_at from public.orders o where o.id = new.order_id;
  if s.event_title is not null and (v_at < s.starts_at or v_at >= s.ends_at) then
    raise exception 'To danie jest tylko na wydarzenie „%”.', s.event_title;
  end if;
  if s.season_from is not null
     and not private.season_active(s.season_from, s.season_to, s.season_yearly,
                                   (v_at at time zone coalesce(s.timezone, 'Europe/Warsaw'))::date) then
    raise exception 'Dział „%” jest w menu tylko w sezonie od % do %.', s.name,
      to_char(s.season_from, case when s.season_yearly then 'DD.MM' else 'DD.MM.YYYY' end),
      to_char(s.season_to, case when s.season_yearly then 'DD.MM' else 'DD.MM.YYYY' end);
  end if;
  return new;
end;
$$;

-- Menu na wydarzenie z okna wydarzenia w Kalendarzu: ustawia, które działy są tylko na to wydarzenie. Działy
-- z listy zostają przypięte, pozostałe odpięte (wracają do zwykłego menu), a nowe nazwy zakładają puste działy
-- od razu przypięte. Wymaga „Kalendarz” oraz „Edycja menu”, bo zmienia, co goście widzą w menu.
create or replace function public.panel_set_event_menu(
  p_event_id    uuid,
  p_section_ids uuid[],
  p_new_names   text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant uuid;
  v_kind       text;
  v_ids        uuid[] := coalesce(p_section_ids, '{}');
  v_names      text[] := coalesce(p_new_names, '{}');
  v_bad        text;
  v_pos        int;
  v_name       text;
begin
  select restaurant_id, kind into v_restaurant, v_kind from calendar_events where id = p_event_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono wydarzenia.';
  end if;
  perform private.require_permission(v_restaurant, 'calendar');
  perform private.require_permission(v_restaurant, 'menu_edit');
  if v_kind <> 'special' and (cardinality(v_ids) > 0 or cardinality(v_names) > 0) then
    raise exception 'Menu można przypiąć tylko do wydarzenia dla gości.';
  end if;
  select s.name into v_bad
  from menu_sections s
  where s.id = any (v_ids)
    and (s.restaurant_id <> v_restaurant
         or s.season_from is not null
         or (s.event_id is not null and s.event_id <> p_event_id))
  limit 1;
  if v_bad is not null then
    raise exception 'Dział „%” nie może być przypięty do tego wydarzenia (jest sezonowy albo na inne wydarzenie).', v_bad;
  end if;

  update menu_sections set event_id = null where event_id = p_event_id and not (id = any (v_ids));
  update menu_sections set event_id = p_event_id where id = any (v_ids) and restaurant_id = v_restaurant;

  if cardinality(v_names) > 0 then
    select coalesce(max(position), -1) + 1 into v_pos from menu_sections where restaurant_id = v_restaurant;
    foreach v_name in array v_names loop
      if btrim(v_name) <> '' then
        insert into menu_sections (restaurant_id, name, position, event_id)
        values (v_restaurant, left(btrim(v_name), 60), v_pos, p_event_id);
        v_pos := v_pos + 1;
      end if;
    end loop;
  end if;
end;
$$;

revoke execute on function public.panel_set_event_menu(uuid, uuid[], text[]) from public, anon;
grant execute on function public.panel_set_event_menu(uuid, uuid[], text[]) to authenticated;

-- Usunięcie wydarzenia z przypiętym działem nadal jest zablokowane (dział stałby się zwykłym działem); komunikat
-- wskazuje teraz też okno wydarzenia.
create or replace function public.panel_delete_calendar_event(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant uuid;
begin
  select restaurant_id into v_restaurant from calendar_events where id = p_id;
  if v_restaurant is null then
    return;
  end if;
  perform private.require_permission(v_restaurant, 'calendar');
  if exists (select 1 from menu_sections where event_id = p_id) then
    raise exception 'Do wydarzenia jest przypięty dział menu. Odepnij go w oknie wydarzenia (Menu na wydarzenie) albo usuń dział.';
  end if;
  delete from calendar_events where id = p_id;
end;
$$;

revoke execute on function public.panel_delete_calendar_event(uuid) from public, anon;
grant execute on function public.panel_delete_calendar_event(uuid) to authenticated;
