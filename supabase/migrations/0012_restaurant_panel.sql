-- Table · migracja 0012
-- Panel restauracji: personel z rolami, plan sali, rezerwacje telefoniczne i z ulicy,
-- zmiany statusu i stolika, odpowiedzi na opinie, godziny, menu i statystyki.

-- ---------------------------------------------------------------
-- Personel restauracji
-- ---------------------------------------------------------------

create type public.staff_role as enum ('owner', 'manager', 'staff');

create table public.restaurant_staff (
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  user_id        uuid not null references auth.users (id) on delete cascade,
  role           public.staff_role not null default 'staff',
  created_at     timestamptz not null default now(),
  primary key (restaurant_id, user_id)
);

create index restaurant_staff_user_idx on public.restaurant_staff (user_id);

alter table public.restaurant_staff enable row level security;

create policy "Pracownik widzi swoje członkostwa"
  on public.restaurant_staff for select to authenticated
  using (user_id = (select auth.uid()));

-- Czy zalogowana osoba pracuje w lokalu co najmniej w danej roli.
-- Kolejność ról: owner > manager > staff.
create or replace function private.has_staff_role(
  p_restaurant_id  uuid,
  p_min            public.staff_role default 'staff'
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.restaurant_staff s
    where s.restaurant_id = p_restaurant_id
      and s.user_id = (select auth.uid())
      and case p_min
            when 'staff' then true
            when 'manager' then s.role in ('owner', 'manager')
            else s.role = 'owner'
          end
  )
$$;

grant usage on schema private to authenticated;
revoke execute on function private.has_staff_role(uuid, public.staff_role) from public, anon;
grant execute on function private.has_staff_role(uuid, public.staff_role) to authenticated;

create or replace function private.require_staff(
  p_restaurant_id  uuid,
  p_min            public.staff_role default 'staff'
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Zaloguj się do panelu restauracji.';
  end if;
  if not private.has_staff_role(p_restaurant_id, p_min) then
    raise exception 'Nie masz uprawnień do tej operacji w tym lokalu.';
  end if;
end;
$$;

revoke execute on function private.require_staff(uuid, public.staff_role) from public, anon, authenticated;

-- ---------------------------------------------------------------
-- Plan sali
-- ---------------------------------------------------------------

create table public.floor_zones (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  name           text not null check (char_length(btrim(name)) between 1 and 40),
  width_cm       integer not null default 1000 check (width_cm between 200 and 10000),
  height_cm      integer not null default 700 check (height_cm between 200 and 10000),
  position       smallint not null default 0,
  unique (restaurant_id, name)
);

alter table public.floor_zones enable row level security;

-- Pozycja to środek blatu w centymetrach od lewego górnego rogu strefy.
alter table public.dining_tables
  add column x_cm      integer not null default 100 check (x_cm between 0 and 10000),
  add column y_cm      integer not null default 100 check (y_cm between 0 and 10000),
  add column rotation  smallint not null default 0 check (rotation between 0 and 359),
  add column shape     text not null default 'rect' check (shape in ('rect', 'round'));

update public.dining_tables set width_cm = coalesce(width_cm, 80), height_cm = coalesce(height_cm, 80);

alter table public.dining_tables
  alter column width_cm set default 80,
  alter column width_cm set not null,
  alter column height_cm set default 80,
  alter column height_cm set not null;

create or replace function private.protect_booked_table()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.table_holds h
    where h.table_id = old.id and h.active and upper(h.slot) > now()
  ) then
    raise exception 'Stolik % ma przyszłe rezerwacje. Przenieś je albo wyłącz stolik zamiast go usuwać.', old.label;
  end if;
  return old;
end;
$$;

create trigger dining_tables_protect_booked
  before delete on public.dining_tables
  for each row execute function private.protect_booked_table();

revoke execute on function private.protect_booked_table() from public, anon, authenticated;

-- ---------------------------------------------------------------
-- Rezerwacje: dane gościa spoza aplikacji, notatka obsługi
-- ---------------------------------------------------------------

alter table public.reservations
  add column guest_name   text check (char_length(guest_name) <= 120),
  add column guest_phone  text check (char_length(guest_phone) <= 20),
  add column staff_note   text check (char_length(staff_note) <= 500),
  add column seated_at    timestamptz,
  add column updated_at   timestamptz not null default now();

create index reservations_restaurant_time_idx on public.reservations (restaurant_id, starts_at);

-- ---------------------------------------------------------------
-- Odpowiedzi restauracji na opinie
-- ---------------------------------------------------------------

alter table public.reviews
  add column reply_body  text check (char_length(reply_body) <= 1000),
  add column reply_at    timestamptz;

-- ---------------------------------------------------------------
-- Uprawnienia personelu w tabelach
-- ---------------------------------------------------------------

-- Profil lokalu: tylko wybrane kolumny. Plan, przykładowość i poziom cen zmienia system.
revoke update on public.restaurants from anon, authenticated;
grant update (name, description, address, city, phone, cuisine, slot_interval_min)
  on public.restaurants to authenticated;

create policy "Kierownik zmienia profil lokalu"
  on public.restaurants for update to authenticated
  using (private.has_staff_role(id, 'manager'))
  with check (private.has_staff_role(id, 'manager'));

create policy "Kierownik zmienia godziny"
  on public.opening_hours for all to authenticated
  using (private.has_staff_role(restaurant_id, 'manager'))
  with check (private.has_staff_role(restaurant_id, 'manager'));

create policy "Kierownik zmienia sekcje menu"
  on public.menu_sections for all to authenticated
  using (private.has_staff_role(restaurant_id, 'manager'))
  with check (private.has_staff_role(restaurant_id, 'manager'));

create policy "Kierownik zmienia pozycje menu"
  on public.menu_items for all to authenticated
  using (exists (
    select 1 from public.menu_sections s
    where s.id = section_id and private.has_staff_role(s.restaurant_id, 'manager')
  ))
  with check (exists (
    select 1 from public.menu_sections s
    where s.id = section_id and private.has_staff_role(s.restaurant_id, 'manager')
  ));

create policy "Personel widzi strefy sali"
  on public.floor_zones for select to authenticated
  using (private.has_staff_role(restaurant_id));

create policy "Kierownik zmienia strefy sali"
  on public.floor_zones for all to authenticated
  using (private.has_staff_role(restaurant_id, 'manager'))
  with check (private.has_staff_role(restaurant_id, 'manager'));

create policy "Personel widzi stoliki"
  on public.dining_tables for select to authenticated
  using (private.has_staff_role(restaurant_id));

create policy "Kierownik zmienia stoliki"
  on public.dining_tables for all to authenticated
  using (private.has_staff_role(restaurant_id, 'manager'))
  with check (private.has_staff_role(restaurant_id, 'manager'));

-- Odczyt potrzebny do powiadomień na żywo. Pełne dane gościa idą przez panel_reservations.
create policy "Personel widzi rezerwacje lokalu"
  on public.reservations for select to authenticated
  using (private.has_staff_role(restaurant_id));

create policy "Personel widzi zajęte stoliki"
  on public.table_holds for select to authenticated
  using (exists (
    select 1 from public.dining_tables t
    where t.id = table_id and private.has_staff_role(t.restaurant_id)
  ));

alter publication supabase_realtime add table public.reservations, public.table_holds;

-- ---------------------------------------------------------------
-- Funkcje panelu
-- ---------------------------------------------------------------

create or replace function public.panel_my_restaurants()
returns table (
  id           uuid,
  name         text,
  city         text,
  plan         public.restaurant_plan,
  role         public.staff_role,
  timezone     text
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.name, r.city, r.plan, s.role, r.timezone
  from restaurant_staff s
  join restaurants r on r.id = s.restaurant_id
  where s.user_id = auth.uid()
  order by r.name
$$;

create or replace function public.panel_reservations(
  p_restaurant_id  uuid,
  p_from           timestamptz,
  p_to             timestamptz
)
returns table (
  id             uuid,
  starts_at      timestamptz,
  ends_at        timestamptz,
  party_size     smallint,
  status         public.reservation_status,
  source         public.reservation_source,
  occasion       public.reservation_occasion,
  message        text,
  diet           text,
  guest_name     text,
  guest_phone    text,
  staff_note     text,
  seated_at      timestamptz,
  created_at     timestamptz,
  table_ids      uuid[],
  table_labels   text[],
  from_app       boolean,
  guest_visits   integer,
  guest_no_shows integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_staff(p_restaurant_id);

  if p_to <= p_from or p_to - p_from > interval '93 days' then
    raise exception 'Wybierz zakres do 3 miesięcy.';
  end if;

  return query
  select
    r.id, r.starts_at, r.ends_at, r.party_size, r.status, r.source, r.occasion,
    case when coalesce(r.message_delete_after, 'infinity') > now() then r.message end,
    case when d.delete_after > now() then d.details end,
    coalesce(
      nullif(btrim(r.guest_name), ''),
      nullif(btrim(p.full_name), ''),
      nullif(btrim(p.first_name), ''),
      case when r.source = 'block' then 'Blokada stolika' else 'Gość' end
    ),
    coalesce(r.guest_phone, case when u.phone is not null and u.phone <> '' then '+' || u.phone end),
    r.staff_note,
    r.seated_at,
    r.created_at,
    coalesce(h.ids, '{}'),
    coalesce(h.labels, '{}'),
    r.user_id is not null,
    coalesce(g.visits, 0),
    coalesce(g.no_shows, 0)
  from reservations r
  left join reservation_diets d on d.reservation_id = r.id
  left join profiles p on p.id = r.user_id
  left join auth.users u on u.id = r.user_id
  left join lateral (
    select array_agg(t.id order by t.label) as ids, array_agg(t.label order by t.label) as labels
    from table_holds th
    join dining_tables t on t.id = th.table_id
    where th.reservation_id = r.id
  ) h on true
  left join lateral (
    select
      count(*) filter (where o.status in ('seated', 'completed'))::integer as visits,
      count(*) filter (where o.status = 'no_show')::integer as no_shows
    from reservations o
    where r.user_id is not null
      and o.user_id = r.user_id
      and o.restaurant_id = r.restaurant_id
      and o.starts_at < r.starts_at
  ) g on true
  where r.restaurant_id = p_restaurant_id
    and r.starts_at >= p_from
    and r.starts_at < p_to
  order by r.starts_at, r.created_at;
end;
$$;

create or replace function private.validate_tables(
  p_restaurant_id  uuid,
  p_table_ids      uuid[],
  p_party_size     integer
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_count  integer;
  v_seats  integer;
begin
  select count(*), coalesce(sum(t.seats), 0)
  into v_count, v_seats
  from public.dining_tables t
  where t.id = any (p_table_ids)
    and t.restaurant_id = p_restaurant_id
    and t.active;

  if v_count = 0 or v_count <> cardinality(p_table_ids) then
    raise exception 'Wybrany stolik nie należy do tego lokalu albo jest wyłączony.';
  end if;

  if v_seats < p_party_size then
    raise exception 'Za mało miejsc: % przy wybranych stolikach, a gości jest %.', v_seats, p_party_size;
  end if;
end;
$$;

revoke execute on function private.validate_tables(uuid, uuid[], integer) from public, anon, authenticated;

create or replace function public.panel_create_reservation(
  p_restaurant_id  uuid,
  p_starts_at      timestamptz,
  p_party_size     integer,
  p_source         public.reservation_source,
  p_guest_name     text default null,
  p_guest_phone    text default null,
  p_occasion       public.reservation_occasion default null,
  p_message        text default null,
  p_staff_note     text default null,
  p_table_ids      uuid[] default null,
  p_duration_min   integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_visit    integer;
  v_cleanup  integer;
  v_ends     timestamptz;
  v_slot     tstzrange;
  v_ids      uuid[];
  v_id       uuid;
begin
  perform private.require_staff(p_restaurant_id);

  if p_source = 'app' then
    raise exception 'Rezerwacje z aplikacji tworzą goście.';
  end if;

  if p_party_size is null or p_party_size not between 1 and 30 then
    raise exception 'Liczba osób musi mieścić się między 1 a 30.';
  end if;

  if p_source <> 'block' and nullif(btrim(p_guest_name), '') is null then
    raise exception 'Wpisz imię gościa.';
  end if;

  if p_starts_at is null
     or p_starts_at < now() - interval '12 hours'
     or p_starts_at > now() + interval '365 days' then
    raise exception 'Wybierz termin od dziś do roku naprzód.';
  end if;

  if p_duration_min is not null and p_duration_min not between 15 and 720 then
    raise exception 'Czas wizyty musi mieścić się między 15 minutami a 12 godzinami.';
  end if;

  v_visit   := coalesce(p_duration_min, private.visit_minutes(p_party_size));
  v_cleanup := private.cleanup_minutes(p_party_size);
  v_ends    := p_starts_at + make_interval(mins => v_visit);
  v_slot    := tstzrange(p_starts_at, v_ends + make_interval(mins => v_cleanup));

  if p_table_ids is not null and cardinality(p_table_ids) > 0 then
    perform private.validate_tables(p_restaurant_id, p_table_ids, p_party_size);
    v_ids := p_table_ids;
  else
    v_ids := private.find_tables(p_restaurant_id, p_party_size, v_slot);
    if v_ids is null then
      raise exception 'Brak wolnego stolika dla % os. o tej godzinie. Wybierz stolik ręcznie albo inną godzinę.', p_party_size;
    end if;
  end if;

  insert into reservations (
    restaurant_id, party_size, starts_at, ends_at, status, source, occasion,
    message, message_delete_after, guest_name, guest_phone, staff_note, seated_at
  )
  values (
    p_restaurant_id, p_party_size, p_starts_at, v_ends,
    case when p_source = 'walk_in' then 'seated'::reservation_status else 'confirmed'::reservation_status end,
    p_source, p_occasion,
    nullif(btrim(p_message), ''), v_ends + interval '30 days',
    nullif(btrim(p_guest_name), ''), nullif(btrim(p_guest_phone), ''),
    nullif(btrim(p_staff_note), ''),
    case when p_source = 'walk_in' then now() end
  )
  returning id into v_id;

  begin
    insert into table_holds (reservation_id, table_id, slot)
    select v_id, t.table_id, v_slot from unnest(v_ids) as t(table_id);
  exception
    when exclusion_violation then
      raise exception 'Wybrany stolik jest zajęty w tym czasie.';
  end;

  return v_id;
end;
$$;

create or replace function public.panel_set_reservation_status(
  p_reservation_id  uuid,
  p_status          public.reservation_status
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res  reservations%rowtype;
begin
  select * into v_res from reservations where id = p_reservation_id;
  if not found then
    raise exception 'Nie znaleziono rezerwacji.';
  end if;

  perform private.require_staff(v_res.restaurant_id);

  update reservations
  set status = p_status,
      seated_at = case
        when p_status = 'seated' then coalesce(seated_at, now())
        when p_status = 'confirmed' then null
        else seated_at
      end,
      updated_at = now()
  where id = p_reservation_id;

  begin
    if p_status in ('cancelled', 'no_show') then
      update table_holds set active = false where reservation_id = p_reservation_id;
    elsif p_status = 'completed' then
      -- Stolik zwalnia się od teraz, a nie dopiero po planowanym końcu wizyty.
      update table_holds
      set slot = tstzrange(lower(slot), greatest(lower(slot), now()) + interval '1 second'),
          active = false
      where reservation_id = p_reservation_id;
    else
      update table_holds set active = true where reservation_id = p_reservation_id;
    end if;
  exception
    when exclusion_violation then
      raise exception 'Nie można przywrócić rezerwacji: jej stolik jest już zajęty. Przenieś ją na inny stolik.';
  end;
end;
$$;

create or replace function public.panel_move_reservation(
  p_reservation_id  uuid,
  p_table_ids       uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res   reservations%rowtype;
  v_slot  tstzrange;
begin
  select * into v_res from reservations where id = p_reservation_id;
  if not found then
    raise exception 'Nie znaleziono rezerwacji.';
  end if;

  perform private.require_staff(v_res.restaurant_id);

  if v_res.status in ('cancelled', 'no_show', 'completed') then
    raise exception 'Tej rezerwacji nie można już przenieść.';
  end if;

  if p_table_ids is null or cardinality(p_table_ids) = 0 then
    raise exception 'Wybierz co najmniej jeden stolik.';
  end if;

  perform private.validate_tables(v_res.restaurant_id, p_table_ids, v_res.party_size);

  select slot into v_slot from table_holds where reservation_id = p_reservation_id limit 1;
  v_slot := coalesce(
    v_slot,
    tstzrange(v_res.starts_at, v_res.ends_at + make_interval(mins => private.cleanup_minutes(v_res.party_size)))
  );

  delete from table_holds where reservation_id = p_reservation_id;

  begin
    insert into table_holds (reservation_id, table_id, slot)
    select p_reservation_id, t.table_id, v_slot from unnest(p_table_ids) as t(table_id);
  exception
    when exclusion_violation then
      raise exception 'Wybrany stolik jest zajęty w tym czasie.';
  end;

  update reservations set updated_at = now() where id = p_reservation_id;
end;
$$;

create or replace function public.panel_set_staff_note(
  p_reservation_id  uuid,
  p_note            text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
begin
  select restaurant_id into v_restaurant from reservations where id = p_reservation_id;
  if not found then
    raise exception 'Nie znaleziono rezerwacji.';
  end if;

  perform private.require_staff(v_restaurant);

  update reservations
  set staff_note = nullif(btrim(p_note), ''), updated_at = now()
  where id = p_reservation_id;
end;
$$;

create or replace function public.panel_set_hours(
  p_restaurant_id  uuid,
  p_hours          jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.require_staff(p_restaurant_id, 'manager');

  delete from opening_hours where restaurant_id = p_restaurant_id;

  insert into opening_hours (restaurant_id, weekday, opens, closes)
  select p_restaurant_id, (h ->> 'weekday')::smallint, (h ->> 'opens')::time, (h ->> 'closes')::time
  from jsonb_array_elements(coalesce(p_hours, '[]'::jsonb)) as h;
exception
  when check_violation then
    raise exception 'Godzina zamknięcia musi być późniejsza niż otwarcia.';
  when unique_violation then
    raise exception 'Każdy dzień tygodnia może mieć tylko jedne godziny otwarcia.';
end;
$$;

create or replace function public.panel_reviews(
  p_restaurant_id  uuid,
  p_limit          integer default 50,
  p_offset         integer default 0
)
returns table (
  id                uuid,
  food              smallint,
  service           smallint,
  ambience          smallint,
  body              text,
  verification      public.review_verification,
  author            text,
  price_per_person  smallint,
  created_at        timestamptz,
  reply_body        text,
  reply_at          timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform private.require_staff(p_restaurant_id);

  return query
  select
    rv.id, rv.food, rv.service, rv.ambience, rv.body, rv.verification,
    coalesce(
      nullif(btrim(p.first_name), ''),
      rv.seed_author,
      case when rv.user_id is null then 'Były gość' else 'Gość' end
    ),
    rv.price_per_person, rv.created_at, rv.reply_body, rv.reply_at
  from reviews rv
  left join profiles p on p.id = rv.user_id
  where rv.restaurant_id = p_restaurant_id
  order by rv.created_at desc
  limit least(greatest(p_limit, 1), 200)
  offset greatest(p_offset, 0);
end;
$$;

create or replace function public.panel_reply_review(
  p_review_id  uuid,
  p_body       text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_body        text := nullif(btrim(p_body), '');
begin
  select restaurant_id into v_restaurant from reviews where id = p_review_id;
  if not found then
    raise exception 'Nie znaleziono opinii.';
  end if;

  perform private.require_staff(v_restaurant, 'manager');

  if char_length(v_body) > 1000 then
    raise exception 'Odpowiedź może mieć najwyżej 1000 znaków.';
  end if;

  update reviews
  set reply_body = v_body,
      reply_at = case when v_body is null then null else now() end
  where id = p_review_id;
end;
$$;

create or replace function public.panel_stats(
  p_restaurant_id  uuid,
  p_days           integer default 30
)
returns table (
  day            date,
  views          integer,
  call_clicks    integer,
  reservations   integer,
  covers         integer,
  cancellations  integer,
  no_shows       integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz    text;
  v_days  integer := least(greatest(coalesce(p_days, 30), 1), 366);
begin
  perform private.require_staff(p_restaurant_id);

  select timezone into v_tz from restaurants where id = p_restaurant_id;

  return query
  with days as (
    select generate_series(
      (now() at time zone v_tz)::date - (v_days - 1),
      (now() at time zone v_tz)::date,
      interval '1 day'
    )::date as day
  ),
  ev as (
    select (e.created_at at time zone v_tz)::date as day,
           count(*) filter (where e.kind = 'view') as views,
           count(*) filter (where e.kind = 'call_click') as calls
    from restaurant_events e
    where e.restaurant_id = p_restaurant_id
      and e.created_at >= now() - make_interval(days => v_days + 1)
    group by 1
  ),
  rs as (
    select (r.starts_at at time zone v_tz)::date as day,
           count(*) filter (where r.status not in ('cancelled')) as res,
           coalesce(sum(r.party_size) filter (where r.status in ('confirmed', 'seated', 'completed')), 0) as covers,
           count(*) filter (where r.status = 'cancelled') as cancels,
           count(*) filter (where r.status = 'no_show') as no_shows
    from reservations r
    where r.restaurant_id = p_restaurant_id
      and r.source <> 'block'
      and r.starts_at >= now() - make_interval(days => v_days + 1)
      and r.starts_at < now() + interval '1 day'
    group by 1
  )
  select d.day,
         coalesce(ev.views, 0)::integer,
         coalesce(ev.calls, 0)::integer,
         coalesce(rs.res, 0)::integer,
         coalesce(rs.covers, 0)::integer,
         coalesce(rs.cancels, 0)::integer,
         coalesce(rs.no_shows, 0)::integer
  from days d
  left join ev on ev.day = d.day
  left join rs on rs.day = d.day
  order by d.day;
end;
$$;

-- ---------------------------------------------------------------
-- Uprawnienia do funkcji panelu
-- ---------------------------------------------------------------

revoke execute on function public.panel_my_restaurants() from public, anon;
revoke execute on function public.panel_reservations(uuid, timestamptz, timestamptz) from public, anon;
revoke execute on function public.panel_create_reservation(uuid, timestamptz, integer, public.reservation_source, text, text, public.reservation_occasion, text, text, uuid[], integer) from public, anon;
revoke execute on function public.panel_set_reservation_status(uuid, public.reservation_status) from public, anon;
revoke execute on function public.panel_move_reservation(uuid, uuid[]) from public, anon;
revoke execute on function public.panel_set_staff_note(uuid, text) from public, anon;
revoke execute on function public.panel_set_hours(uuid, jsonb) from public, anon;
revoke execute on function public.panel_reviews(uuid, integer, integer) from public, anon;
revoke execute on function public.panel_reply_review(uuid, text) from public, anon;
revoke execute on function public.panel_stats(uuid, integer) from public, anon;

grant execute on function public.panel_my_restaurants() to authenticated;
grant execute on function public.panel_reservations(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.panel_create_reservation(uuid, timestamptz, integer, public.reservation_source, text, text, public.reservation_occasion, text, text, uuid[], integer) to authenticated;
grant execute on function public.panel_set_reservation_status(uuid, public.reservation_status) to authenticated;
grant execute on function public.panel_move_reservation(uuid, uuid[]) to authenticated;
grant execute on function public.panel_set_staff_note(uuid, text) to authenticated;
grant execute on function public.panel_set_hours(uuid, jsonb) to authenticated;
grant execute on function public.panel_reviews(uuid, integer, integer) to authenticated;
grant execute on function public.panel_reply_review(uuid, text) to authenticated;
grant execute on function public.panel_stats(uuid, integer) to authenticated;
