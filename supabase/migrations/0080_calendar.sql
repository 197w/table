-- Kalendarz (8.11.2026, prośba użytkownika i zadanie „Kalendarz” z Todoist): Management → Kalendarz w panelu
-- (wygląd jak Notion Calendar) i kalendarz w Table for employees. Osoba z uprawnieniem „Kalendarz” dodaje:
-- - wydarzenia specjalne lokalu (promocje, zimowe menu…): goście widzą je w aplikacji Table nad godzinami otwarcia,
--   a do wydarzenia można przypiąć dział menu, który jest tylko na czas wydarzenia;
-- - wydarzenia tylko dla pracowników (spotkanie, szkolenie).

create table public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants (id) on delete cascade,
  kind text not null check (kind in ('special', 'staff')),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  description text check (description is null or char_length(description) <= 2000),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  all_day boolean not null default false,
  color text not null default 'green' check (color in ('green', 'blue', 'violet', 'amber', 'rose', 'teal', 'gray')),
  created_by_member uuid references public.staff_members (id) on delete set null,
  created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index calendar_events_range on public.calendar_events (restaurant_id, starts_at, ends_at);

-- Odczyt: wydarzenia specjalne widzi każdy (strona lokalu w aplikacji Table), wszystkie widzi obsługa lokalu.
-- Zapis tylko funkcjami.
alter table public.calendar_events enable row level security;

create policy calendar_events_public on public.calendar_events
  for select to anon, authenticated
  using (kind = 'special');

create policy calendar_events_staff on public.calendar_events
  for select to authenticated
  using (private.has_staff_role(restaurant_id, 'staff'));

grant select on public.calendar_events to anon, authenticated;

-- Dział menu tylko na wydarzenie specjalne: poza czasem wydarzenia goście i obsługa go nie widzą,
-- a baza nie przyjmuje z niego nowych pozycji (trigger niżej).
alter table public.menu_sections
  add column event_id uuid references public.calendar_events (id) on delete set null;
grant select (event_id) on public.menu_sections to anon, authenticated;
grant insert (event_id), update (event_id) on public.menu_sections to authenticated;

-- Nowe uprawnienie „Kalendarz” (dodawanie i zmiana wydarzeń).
create or replace function private.all_permissions()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['reservations', 'floor', 'floor_edit', 'orders', 'orders_close', 'orders_cancel', 'deliveries', 'fleet',
               'kitchen', 'kitchen_settings', 'serving', 'staff', 'staff_logins', 'schedule', 'timesheet', 'positions',
               'announcements',
               'profile', 'menu', 'menu_edit', 'menu_availability', 'inventory_edit', 'inventory_count',
               'customers', 'reviews', 'stats', 'revenue', 'day_close', 'discounts', 'export', 'fraud', 'activity',
               'calendar']
$$;

update public.staff_positions
set permissions = array_append(permissions, 'calendar')
where not ('calendar' = any (permissions))
  and ('staff' = any (permissions) or 'day_close' = any (permissions) or 'schedule' = any (permissions));

-- Zapis wydarzenia: nowe (bez [p_id]) albo zmiana. Zwraca numer wydarzenia.
create or replace function public.panel_save_calendar_event(
  p_restaurant_id uuid,
  p_id uuid,
  p_kind text,
  p_title text,
  p_description text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_all_day boolean,
  p_color text,
  p_member_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform private.require_permission(p_restaurant_id, 'calendar');
  if p_kind not in ('special', 'staff') then
    raise exception 'Nieznany rodzaj wydarzenia.';
  end if;
  if coalesce(btrim(p_title), '') = '' then
    raise exception 'Wpisz nazwę wydarzenia.';
  end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception 'Koniec wydarzenia musi być po początku.';
  end if;
  if p_ends_at - p_starts_at > interval '400 days' then
    raise exception 'Wydarzenie może trwać najwyżej 400 dni.';
  end if;
  if p_id is null then
    insert into calendar_events (restaurant_id, kind, title, description, starts_at, ends_at, all_day, color,
                                 created_by_member, created_by_name)
    values (p_restaurant_id, p_kind, left(btrim(p_title), 120), nullif(btrim(coalesce(p_description, '')), ''),
            p_starts_at, p_ends_at, coalesce(p_all_day, false), coalesce(p_color, 'green'),
            p_member_id, private.note_author(p_restaurant_id, p_member_id))
    returning id into v_id;
  else
    update calendar_events
       set kind = p_kind, title = left(btrim(p_title), 120),
           description = nullif(btrim(coalesce(p_description, '')), ''),
           starts_at = p_starts_at, ends_at = p_ends_at, all_day = coalesce(p_all_day, false),
           color = coalesce(p_color, color), updated_at = now()
     where id = p_id and restaurant_id = p_restaurant_id
    returning id into v_id;
    if v_id is null then
      raise exception 'Nie znaleziono wydarzenia.';
    end if;
  end if;
  return v_id;
end;
$$;

-- Usunięcie wydarzenia. Z przypiętym działem menu nie: dział stałby się zwykłym działem.
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
    raise exception 'Do wydarzenia jest przypięty dział menu. Odepnij go w Menu albo usuń dział.';
  end if;
  delete from calendar_events where id = p_id;
end;
$$;

revoke execute on function public.panel_save_calendar_event(uuid, uuid, text, text, text, timestamptz, timestamptz,
  boolean, text, uuid) from public, anon;
grant execute on function public.panel_save_calendar_event(uuid, uuid, text, text, text, timestamptz, timestamptz,
  boolean, text, uuid) to authenticated;
revoke execute on function public.panel_delete_calendar_event(uuid) from public, anon;
grant execute on function public.panel_delete_calendar_event(uuid) to authenticated;

-- Dania z działu na wydarzenie da się nabić tylko w czasie wydarzenia (przy zamówieniu na godzinę: o tej godzinie).
-- Sprawdzamy tylko nowe pozycje (stan „new”): kopie przy płatności za część rachunku przechodzą.
create or replace function private.event_menu_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title  text;
  v_starts timestamptz;
  v_ends   timestamptz;
  v_at     timestamptz;
begin
  if new.menu_item_id is null or new.status is distinct from 'new' then
    return new;
  end if;
  select e.title, e.starts_at, e.ends_at into v_title, v_starts, v_ends
  from public.menu_items mi
  join public.menu_sections s on s.id = mi.section_id
  join public.calendar_events e on e.id = s.event_id
  where mi.id = new.menu_item_id;
  if v_title is null then
    return new;
  end if;
  select coalesce(o.scheduled_for, now()) into v_at from public.orders o where o.id = new.order_id;
  if v_at < v_starts or v_at >= v_ends then
    raise exception 'To danie jest tylko na wydarzenie „%”.', v_title;
  end if;
  return new;
end;
$$;

create trigger order_items_event_menu
  before insert on public.order_items
  for each row execute function private.event_menu_check();
