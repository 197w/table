-- Paczka zmian z 10.2026:
-- 1. Historia zamówień: wyszukiwanie po imieniu, telefonie i adresie (wszystkie dni).
-- 2. Statystyki sprzedaży w godzinach: liczba zamówień z podziałem na salę, dostawę i odbiór.
-- 3. Kompletowanie: chwila wydania pozycji (order_items.served_at), żeby wydaną pozycję przekreślać, a nie chować.
-- 4. Informacje dla pracowników: wpisy z odbiorcami (wszyscy, pracujący danego dnia, stanowiska, osoby)
--    i zaplanowaną datą wysłania. Pisze osoba z uprawnieniem „announcements”, reszta tylko czyta.
-- 5. Grafik: godziny po północy (koniec wcześniej niż początek = następnego dnia, np. 18:00–02:00).

-- ---------------------------------------------------------------
-- 1. Wyszukiwanie w historii zamówień
-- ---------------------------------------------------------------

-- Zamknięte i anulowane zamówienia pasujące do imienia (także nazwy firmy i gościa z rezerwacji),
-- telefonu (same cyfry, dowolny zapis) albo adresu dostawy. Najnowsze pierwsze, najwyżej 100.
create or replace function public.panel_order_search(p_restaurant_id uuid, p_query text)
returns setof uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_q      text := btrim(coalesce(p_query, ''));
  v_digits text := regexp_replace(v_q, '\D', '', 'g');
begin
  if not (private.has_permission(p_restaurant_id, 'orders') or private.has_permission(p_restaurant_id, 'stats')) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
  if char_length(v_q) < 2 then
    return;
  end if;
  -- Telefon: wpisane cyfry (bez +48 na początku) gdziekolwiek w numerze zapisanym z dowolnymi odstępami.
  if char_length(v_digits) >= 3 then
    v_digits := right(v_digits, 9);
  else
    v_digits := null;
  end if;
  return query
    select o.id
    from orders o
    left join reservations r on r.id = o.reservation_id
    where o.restaurant_id = p_restaurant_id
      and o.status in ('paid', 'cancelled')
      and (
        o.customer_name ilike '%' || v_q || '%'
        or o.customer_company ilike '%' || v_q || '%'
        or o.delivery_address ilike '%' || v_q || '%'
        or r.guest_name ilike '%' || v_q || '%'
        or (v_digits is not null and (
          regexp_replace(coalesce(o.customer_phone, ''), '\D', '', 'g') like '%' || v_digits || '%'
          or regexp_replace(coalesce(r.guest_phone, ''), '\D', '', 'g') like '%' || v_digits || '%'
        ))
      )
    order by o.closed_at desc nulls last
    limit 100;
end;
$$;

-- ---------------------------------------------------------------
-- 2. Sprzedaż w godzinach z podziałem na salę, dostawę i odbiór
-- ---------------------------------------------------------------

create or replace function public.panel_sales_stats(p_restaurant_id uuid, p_days integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz     text;
  v_days   integer := greatest(1, least(coalesce(p_days, 30), 366));
  v_start  timestamptz;
  v_prev   timestamptz;
begin
  if not (
    private.has_permission(p_restaurant_id, 'stats')
    or private.has_permission(p_restaurant_id, 'orders')
  ) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;

  select timezone into v_tz from restaurants where id = p_restaurant_id;
  v_tz := coalesce(v_tz, 'Europe/Warsaw');
  v_start := (date_trunc('day', now() at time zone v_tz) - make_interval(days => v_days - 1)) at time zone v_tz;
  v_prev := v_start - make_interval(days => v_days);

  return (
    with paid as (
      select o.*,
             (select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
              from order_items i where i.order_id = o.id and i.status <> 'cancelled') as total
      from orders o
      where o.restaurant_id = p_restaurant_id and o.status = 'paid' and o.closed_at >= v_prev
    ),
    cur as (select * from paid where closed_at >= v_start),
    prev as (select * from paid where closed_at < v_start),
    items as (
      select i.* from order_items i
      join cur o on o.id = i.order_id
      where i.status <> 'cancelled'
    ),
    days as (
      select d::date as day
      from generate_series((v_start at time zone v_tz)::date, (now() at time zone v_tz)::date, interval '1 day') d
    )
    select jsonb_build_object(
      'revenue', coalesce((select sum(total) from cur), 0),
      'orders', (select count(*) from cur),
      'items', coalesce((select sum(quantity) from items), 0),
      'gift_cards', coalesce((select sum(gift_card_grosze) from cur), 0),
      'cancelled', (select count(*) from orders o where o.restaurant_id = p_restaurant_id
                    and o.status = 'cancelled' and o.closed_at >= v_start),
      'avg_table_minutes', (select round(avg(extract(epoch from closed_at - opened_at)) / 60) from cur),
      'prev_revenue', coalesce((select sum(total) from prev), 0),
      'prev_orders', (select count(*) from prev),
      'daily', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'day', d.day,
          'revenue', coalesce((select sum(c.total) from cur c where (c.closed_at at time zone v_tz)::date = d.day), 0),
          'orders', (select count(*) from cur c where (c.closed_at at time zone v_tz)::date = d.day)
        ) order by d.day), '[]'::jsonb)
        from days d
      ),
      -- Godzina złożenia (otwarcia) zamówienia: kwota, liczba i podział na salę, dostawę i odbiór.
      'hourly', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'hour', h,
          'revenue', coalesce(x.revenue, 0),
          'orders', coalesce(x.orders, 0),
          'dine_in', coalesce(x.dine_in, 0),
          'delivery', coalesce(x.delivery, 0),
          'pickup', coalesce(x.pickup, 0)
        ) order by h), '[]'::jsonb)
        from generate_series(0, 23) h
        left join (
          select extract(hour from c.opened_at at time zone v_tz)::integer as hour,
                 sum(c.total) as revenue, count(*) as orders,
                 count(*) filter (where c.kind = 'delivery') as delivery,
                 count(*) filter (where c.kind = 'pickup') as pickup,
                 count(*) filter (where c.kind is distinct from 'delivery' and c.kind is distinct from 'pickup') as dine_in
          from cur c group by 1
        ) x on x.hour = h
      ),
      'weekdays', (
        select coalesce(jsonb_agg(jsonb_build_object('weekday', w, 'revenue', coalesce(x.revenue, 0), 'orders', coalesce(x.orders, 0)) order by w), '[]'::jsonb)
        from generate_series(1, 7) w
        left join (
          select extract(isodow from c.closed_at at time zone v_tz)::integer as weekday,
                 sum(c.total) as revenue, count(*) as orders
          from cur c group by 1
        ) x on x.weekday = w
      ),
      'top_items', (
        select coalesce(jsonb_agg(t order by t.quantity desc, t.revenue desc), '[]'::jsonb)
        from (
          select name, sum(quantity)::integer as quantity, sum(unit_price_grosze * quantity)::integer as revenue
          from items group by name order by sum(quantity) desc, sum(unit_price_grosze * quantity) desc limit 10
        ) t
      ),
      'payments', (
        select coalesce(jsonb_agg(p), '[]'::jsonb)
        from (
          select method, sum(amount)::integer as amount, count(*)::integer as orders from (
            select payment_method as method, total - coalesce(gift_card_grosze, 0) as amount
            from cur where payment_method <> 'gift_card'
            union all
            select 'gift_card', coalesce(gift_card_grosze, total) from cur
            where gift_card_grosze is not null or payment_method = 'gift_card'
          ) a
          group by method order by sum(amount) desc
        ) p
      ),
      'vat', (
        select coalesce(jsonb_agg(v order by v.rate desc), '[]'::jsonb)
        from (
          select vat_rate as rate, sum(unit_price_grosze * quantity)::integer as gross
          from items group by vat_rate
        ) v
      ),
      'staff', (
        select coalesce(jsonb_agg(s order by s.revenue desc), '[]'::jsonb)
        from (
          select coalesce(m.name, 'Bez przypisania') as name, sum(c.total)::integer as revenue,
                 count(*)::integer as orders
          from cur c
          left join staff_members m on m.id = c.opened_by_member
          group by m.name
        ) s
      ),
      'kitchen_seconds', (
        select round(avg(extract(epoch from done - sent)))
        from (
          select i.sent_at as sent, max(i.ready_at) as done
          from order_items i
          where i.restaurant_id = p_restaurant_id and i.sent_at >= v_start and i.ready_at is not null
          group by i.order_id, i.sent_at
        ) k
      )
    )
  );
end;
$$;

-- ---------------------------------------------------------------
-- 3. Kompletowanie: kiedy pozycję wydano
-- ---------------------------------------------------------------

alter table public.order_items add column served_at timestamptz;

create or replace function private.order_item_served_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'served' and old.status is distinct from 'served' then
    new.served_at := now();
  elsif new.status is distinct from 'served' then
    new.served_at := null;
  end if;
  return new;
end;
$$;
create trigger order_items_served_at
  before update of status on public.order_items
  for each row execute function private.order_item_served_at();

-- ---------------------------------------------------------------
-- 4. Informacje dla pracowników
-- ---------------------------------------------------------------

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
               'customers', 'reviews', 'stats', 'revenue', 'day_close', 'discounts', 'export']
$$;
update public.staff_positions set permissions = private.all_permissions() where system_key = 'all';
-- Kierownicy (stanowiska z „Pracownicy”) piszą informacje; pozostali tylko je czytają.
update public.staff_positions p
set permissions = (select array_agg(distinct x) from unnest(p.permissions || array['announcements']) x)
where p.system_key is distinct from 'all' and 'staff' = any (p.permissions);

create table public.staff_announcements (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  title          text not null check (char_length(btrim(title)) between 1 and 120),
  body           text not null default '' check (char_length(body) <= 4000),
  -- all: wszyscy, working: pracujący w dniu wysłania, positions: wybrane stanowiska, members: wybrane osoby.
  audience       text not null check (audience in ('all', 'working', 'positions', 'members')),
  position_ids   uuid[] not null default '{}',
  member_ids     uuid[] not null default '{}',
  -- Od kiedy odbiorcy widzą wpis (zaplanowane wysłanie).
  publish_at     timestamptz not null default now(),
  author_member  uuid references public.staff_members (id) on delete set null,
  author_name    text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (audience <> 'positions' or cardinality(position_ids) > 0),
  check (audience <> 'members' or cardinality(member_ids) > 0)
);
create index staff_announcements_restaurant on public.staff_announcements (restaurant_id, publish_at desc);
alter table public.staff_announcements enable row level security;

create table public.staff_announcement_reads (
  announcement_id  uuid not null references public.staff_announcements (id) on delete cascade,
  member_id        uuid not null references public.staff_members (id) on delete cascade,
  read_at          timestamptz not null default now(),
  primary key (announcement_id, member_id)
);
alter table public.staff_announcement_reads enable row level security;

-- Czy wpis jest dla pracownika. „Pracujący” w dniu wysłania (strefa lokalu): przyjęte godziny w grafiku
-- albo zmiana, która trwa choć część tego dnia (także rozpoczęta wcześniej i jeszcze niezakończona).
create or replace function private.announcement_for(a public.staff_announcements, p_member_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz  text;
  v_day date;
begin
  if not exists (
    select 1 from public.staff_members m where m.id = p_member_id and m.restaurant_id = a.restaurant_id and m.active
  ) then
    return false;
  end if;
  case a.audience
    when 'all' then
      return true;
    when 'members' then
      return p_member_id = any (a.member_ids);
    when 'positions' then
      return exists (select 1 from private.member_position_ids(p_member_id) as t(pid) where t.pid = any (a.position_ids));
    else
      select coalesce(r.timezone, 'Europe/Warsaw') into v_tz from public.restaurants r where r.id = a.restaurant_id;
      v_day := (a.publish_at at time zone v_tz)::date;
      return exists (
        select 1 from public.staff_schedule s
        where s.member_id = p_member_id and s.day = v_day and s.status = 'accepted'
      ) or exists (
        select 1 from public.staff_shifts s
        where s.member_id = p_member_id
          and (s.started_at at time zone v_tz)::date <= v_day
          and (s.ended_at is null or (s.ended_at at time zone v_tz)::date >= v_day)
      );
  end case;
end;
$$;

-- Liczba odbiorców wpisu (do „Przeczytało 3 z 8”).
create or replace function private.announcement_recipients(a public.staff_announcements)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from public.staff_members m
  where m.restaurant_id = a.restaurant_id and m.active and private.announcement_for(a, m.id)
$$;

create or replace function private.announcement_json(a public.staff_announcements, p_member_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', a.id,
    'title', a.title,
    'body', a.body,
    'audience', a.audience,
    'position_ids', a.position_ids,
    'member_ids', a.member_ids,
    'publish_at', a.publish_at,
    'author_member', a.author_member,
    'author_name', a.author_name,
    'created_at', a.created_at,
    'updated_at', a.updated_at,
    'read', p_member_id is not null and exists (
      select 1 from public.staff_announcement_reads r where r.announcement_id = a.id and r.member_id = p_member_id
    ),
    'for_me', p_member_id is not null and private.announcement_for(a, p_member_id)
  )
$$;

-- Panel: wszystkie wpisy lokalu (z liczbą odbiorców i przeczytań). Kto ich nie pisze, widzi w panelu
-- tylko wysłane do siebie (filtr po stronie panelu według zalogowanego pracownika).
create or replace function public.panel_announcements(p_restaurant_id uuid, p_member_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not private.has_staff_role(p_restaurant_id) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
  return coalesce((
    select jsonb_agg(
      private.announcement_json(a, p_member_id) || jsonb_build_object(
        'recipients', private.announcement_recipients(a),
        'reads', (select count(*) from staff_announcement_reads r where r.announcement_id = a.id)
      )
      order by a.publish_at desc
    )
    from staff_announcements a
    where a.restaurant_id = p_restaurant_id
  ), '[]'::jsonb);
end;
$$;

-- Zapis wpisu (nowy albo zmiana). [p_member_id]: zalogowany w panelu pracownik (autor), null: konto restauracji.
create or replace function public.panel_save_announcement(
  p_restaurant_id  uuid,
  p_id             uuid,
  p_title          text,
  p_body           text,
  p_audience       text,
  p_position_ids   uuid[],
  p_member_ids     uuid[],
  p_publish_at     timestamptz,
  p_member_id      uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id     uuid := p_id;
  v_author text;
begin
  perform private.require_permission(p_restaurant_id, 'announcements');
  if p_member_id is not null and not ('announcements' = any (private.member_permissions(p_member_id))) then
    raise exception 'Informacje pisze osoba z uprawnieniem „Informacje dla pracowników”.';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) = 0 then
    raise exception 'Wpisz tytuł informacji.';
  end if;
  if p_audience = 'positions' and cardinality(coalesce(p_position_ids, '{}')) = 0 then
    raise exception 'Wybierz co najmniej jedno stanowisko.';
  end if;
  if p_audience = 'members' and cardinality(coalesce(p_member_ids, '{}')) = 0 then
    raise exception 'Wybierz co najmniej jedną osobę.';
  end if;
  v_author := coalesce((select name from staff_members where id = p_member_id), 'Konto restauracji');
  if v_id is null then
    insert into staff_announcements (restaurant_id, title, body, audience, position_ids, member_ids, publish_at,
                                     author_member, author_name)
    values (p_restaurant_id, btrim(p_title), coalesce(p_body, ''), p_audience,
            case when p_audience = 'positions' then p_position_ids else '{}' end,
            case when p_audience = 'members' then p_member_ids else '{}' end,
            coalesce(p_publish_at, now()), p_member_id, v_author)
    returning id into v_id;
  else
    update staff_announcements
    set title = btrim(p_title), body = coalesce(p_body, ''), audience = p_audience,
        position_ids = case when p_audience = 'positions' then p_position_ids else '{}' end,
        member_ids = case when p_audience = 'members' then p_member_ids else '{}' end,
        publish_at = coalesce(p_publish_at, publish_at), updated_at = now()
    where id = v_id and restaurant_id = p_restaurant_id;
    if not found then
      raise exception 'Nie znaleziono informacji.';
    end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.panel_delete_announcement(p_id uuid, p_member_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant uuid;
begin
  select restaurant_id into v_restaurant from staff_announcements where id = p_id;
  if v_restaurant is null then
    return;
  end if;
  perform private.require_permission(v_restaurant, 'announcements');
  if p_member_id is not null and not ('announcements' = any (private.member_permissions(p_member_id))) then
    raise exception 'Informacje usuwa osoba z uprawnieniem „Informacje dla pracowników”.';
  end if;
  delete from staff_announcements where id = p_id;
end;
$$;

-- Pracownik zalogowany w panelu przeczytał informację.
create or replace function public.panel_read_announcement(p_id uuid, p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_a staff_announcements%rowtype;
begin
  select * into v_a from staff_announcements where id = p_id;
  if not found or not private.has_staff_role(v_a.restaurant_id) then
    return;
  end if;
  if private.announcement_for(v_a, p_member_id) and v_a.publish_at <= now() then
    insert into staff_announcement_reads (announcement_id, member_id) values (p_id, p_member_id)
    on conflict do nothing;
  end if;
end;
$$;

-- Table for employees: wysłane już informacje dla pracownika, najnowsze pierwsze.
create or replace function public.staff_announcements(p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_member staff_members%rowtype;
begin
  v_member := private.my_member(p_member_id);
  return coalesce((
    select jsonb_agg(private.announcement_json(a, p_member_id) order by a.publish_at desc)
    from staff_announcements a
    where a.restaurant_id = v_member.restaurant_id
      and a.publish_at <= now()
      and a.publish_at > now() - interval '60 days'
      and private.announcement_for(a, p_member_id)
  ), '[]'::jsonb);
end;
$$;

create or replace function public.staff_read_announcement(p_member_id uuid, p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member staff_members%rowtype;
  v_a      staff_announcements%rowtype;
begin
  v_member := private.my_member(p_member_id);
  select * into v_a from staff_announcements where id = p_id and restaurant_id = v_member.restaurant_id;
  if found and v_a.publish_at <= now() and private.announcement_for(v_a, p_member_id) then
    insert into staff_announcement_reads (announcement_id, member_id) values (p_id, p_member_id)
    on conflict do nothing;
  end if;
end;
$$;

-- ---------------------------------------------------------------
-- 5. Grafik: godziny po północy
-- ---------------------------------------------------------------

-- Koniec wcześniej niż początek znaczy: następnego dnia (np. 18:00–02:00). Nie mogą być równe.
alter table public.staff_schedule drop constraint staff_schedule_hours_check;
alter table public.staff_schedule add constraint staff_schedule_hours_check check (
  ((status in ('off', 'unavailable')) and starts is null and ends is null)
  or ((status not in ('off', 'unavailable')) and starts is not null and ends is not null and ends <> starts)
);
alter table public.staff_schedule drop constraint staff_schedule_check1;
alter table public.staff_schedule add constraint staff_schedule_check1 check (
  requested_starts is null or requested_ends <> requested_starts
);

create or replace function public.panel_add_hours(p_member_id uuid, p_day date, p_starts time, p_ends time, p_answer text default null, p_position_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_status      text;
begin
  select restaurant_id into v_restaurant from staff_members where id = p_member_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_schedule(v_restaurant);
  if p_starts is null or p_ends is null or p_ends = p_starts then
    raise exception 'Początek i koniec nie mogą być takie same.';
  end if;
  select status into v_status from staff_schedule where member_id = p_member_id and day = p_day;
  if v_status is null or v_status in ('unavailable', 'proposed') then
    raise exception 'Pracownik jest niedostępny w tym dniu. Wyślij mu propozycję.';
  end if;
  update staff_schedule
  set starts = p_starts, ends = p_ends, status = 'accepted', answer = nullif(btrim(p_answer), ''),
      position_id = coalesce(p_position_id, position_id),
      decided_by = auth.uid(), decided_at = now(), updated_at = now()
  where member_id = p_member_id and day = p_day;
end;
$$;

create or replace function public.panel_decide_hours(p_id uuid, p_accept boolean, p_starts time default null, p_ends time default null, p_answer text default null, p_position_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row  staff_schedule%rowtype;
begin
  select * into v_row from staff_schedule where id = p_id;
  if not found then
    raise exception 'Nie znaleziono wpisu w grafiku.';
  end if;
  perform private.require_schedule(v_row.restaurant_id);

  if p_accept then
    if v_row.status in ('unavailable', 'proposed') then
      raise exception 'Pracownik jest niedostępny w tym dniu. Wyślij mu propozycję.';
    end if;
    if coalesce(p_starts, v_row.starts) is null or coalesce(p_ends, v_row.ends) is null then
      raise exception 'Podaj godziny.';
    end if;
    if coalesce(p_ends, v_row.ends) = coalesce(p_starts, v_row.starts) then
      raise exception 'Początek i koniec nie mogą być takie same.';
    end if;
    update staff_schedule
    set status = 'accepted', starts = coalesce(p_starts, starts), ends = coalesce(p_ends, ends),
        position_id = coalesce(p_position_id, position_id),
        answer = nullif(btrim(p_answer), ''), decided_by = auth.uid(), decided_at = now(), updated_at = now()
    where id = p_id;
  else
    if v_row.status in ('off', 'unavailable') then
      raise exception 'W tym dniu nie ma godzin do odrzucenia.';
    end if;
    update staff_schedule
    set status = 'rejected', answer = nullif(btrim(p_answer), ''),
        decided_by = auth.uid(), decided_at = now(), updated_at = now()
    where id = p_id;
  end if;
end;
$$;

create or replace function public.panel_propose_hours(p_member_id uuid, p_day date, p_starts time, p_ends time, p_answer text default null, p_position_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_status      text;
begin
  select restaurant_id into v_restaurant from staff_members where id = p_member_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_schedule(v_restaurant);
  if p_day is null then
    raise exception 'Wybierz dzień.';
  end if;
  if p_starts is null or p_ends is null or p_ends = p_starts then
    raise exception 'Początek i koniec nie mogą być takie same.';
  end if;
  select status into v_status from staff_schedule where member_id = p_member_id and day = p_day;
  if v_status = 'accepted' then
    raise exception 'Ten dzień ma już przyjęte godziny.';
  end if;
  insert into staff_schedule (restaurant_id, member_id, day, starts, ends, status, answer, position_id, decided_by, decided_at)
  values (v_restaurant, p_member_id, p_day, p_starts, p_ends, 'proposed', nullif(btrim(p_answer), ''), p_position_id,
          auth.uid(), now())
  on conflict (member_id, day) do update
    set starts = excluded.starts, ends = excluded.ends, status = 'proposed', answer = excluded.answer,
        position_id = excluded.position_id, decided_by = excluded.decided_by, decided_at = now(), updated_at = now();
end;
$$;

create or replace function public.staff_submit_hours(p_member_id uuid, p_day date, p_starts time, p_ends time, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_status  text;
begin
  select * into v_member from private.my_members() m where m.id = p_member_id;
  if not found then
    raise exception 'Nie ma Cię na liście pracowników tego lokalu.';
  end if;
  if p_day is null or p_day < current_date then
    raise exception 'Godziny można zgłaszać od dziś.';
  end if;
  if p_day > current_date + 90 then
    raise exception 'Godziny można zgłaszać najwyżej 90 dni do przodu.';
  end if;
  -- Koniec wcześniej niż początek: praca do następnego dnia (np. 18:00–02:00).
  if p_starts is null or p_ends is null or p_ends = p_starts then
    raise exception 'Początek i koniec nie mogą być takie same.';
  end if;
  perform private.check_schedule_deadline(v_member.restaurant_id, p_day);

  select status into v_status from staff_schedule where member_id = p_member_id and day = p_day;
  if v_status = 'off' then
    raise exception 'Przełożony dał Ci wolne w tym dniu.';
  end if;
  if v_status = 'proposed' then
    raise exception 'Przełożony wysłał Ci propozycję na ten dzień. Przyjmij ją albo odrzuć.';
  end if;
  if v_status is not null and v_status not in ('pending', 'unavailable') then
    raise exception 'Przełożony już zdecydował o tym dniu. Tych godzin nie można już zmienić.';
  end if;

  insert into staff_schedule (restaurant_id, member_id, day, starts, ends, requested_starts, requested_ends, note, status)
  values (v_member.restaurant_id, p_member_id, p_day, p_starts, p_ends, p_starts, p_ends, nullif(btrim(p_note), ''), 'pending')
  on conflict (member_id, day) do update
    set starts = excluded.starts, ends = excluded.ends, status = 'pending',
        requested_starts = excluded.requested_starts, requested_ends = excluded.requested_ends,
        note = excluded.note, updated_at = now();
end;
$$;

-- ---------------------------------------------------------------
-- Uprawnienia
-- ---------------------------------------------------------------

revoke execute on function private.order_item_served_at() from public, anon, authenticated;
revoke execute on function private.announcement_for(public.staff_announcements, uuid) from public, anon, authenticated;
revoke execute on function private.announcement_recipients(public.staff_announcements) from public, anon, authenticated;
revoke execute on function private.announcement_json(public.staff_announcements, uuid) from public, anon, authenticated;

revoke execute on function public.panel_order_search(uuid, text) from public, anon;
revoke execute on function public.panel_announcements(uuid, uuid) from public, anon;
revoke execute on function public.panel_save_announcement(uuid, uuid, text, text, text, uuid[], uuid[], timestamptz, uuid) from public, anon;
revoke execute on function public.panel_delete_announcement(uuid, uuid) from public, anon;
revoke execute on function public.panel_read_announcement(uuid, uuid) from public, anon;
revoke execute on function public.staff_announcements(uuid) from public, anon;
revoke execute on function public.staff_read_announcement(uuid, uuid) from public, anon;

grant execute on function public.panel_order_search(uuid, text) to authenticated;
grant execute on function public.panel_announcements(uuid, uuid) to authenticated;
grant execute on function public.panel_save_announcement(uuid, uuid, text, text, text, uuid[], uuid[], timestamptz, uuid) to authenticated;
grant execute on function public.panel_delete_announcement(uuid, uuid) to authenticated;
grant execute on function public.panel_read_announcement(uuid, uuid) to authenticated;
grant execute on function public.staff_announcements(uuid) to authenticated;
grant execute on function public.staff_read_announcement(uuid, uuid) to authenticated;
