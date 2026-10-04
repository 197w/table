-- Management: nowe uprawnienia, poprawki zmian co do minuty z zapamiętanym oryginałem, gramy i mililitry
-- w spisie inwentaryzacji, podsumowanie dnia z raportami kasy i terminali oraz petty cash.

-- ---------------------------------------------------------------
-- 1. Uprawnienia
-- ---------------------------------------------------------------

create or replace function private.all_permissions()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['reservations', 'floor', 'floor_edit', 'orders', 'orders_close', 'orders_cancel', 'deliveries', 'fleet',
               'kitchen', 'kitchen_settings', 'serving', 'staff', 'staff_logins', 'schedule', 'timesheet', 'positions',
               'profile', 'menu', 'menu_edit', 'menu_availability', 'inventory_edit', 'inventory_count',
               'customers', 'reviews', 'stats', 'revenue', 'day_close', 'discounts', 'export']
$$;

update public.staff_positions set permissions = private.all_permissions() where system_key = 'all';

-- Kierownicy i właściciele (stanowiska z „Pracownicy” albo „Statystyki”) dostają nowe uprawnienia Management,
-- żeby dalej widzieli przychody. Kelner bez tych uprawnień nie widzi obrotu w historii zamówień.
update public.staff_positions p
set permissions = (
  select array_agg(distinct x) from unnest(p.permissions || array['revenue', 'day_close', 'discounts', 'export']) x
)
where p.system_key is distinct from 'all'
  and ('staff' = any(p.permissions) or 'stats' = any(p.permissions));

-- ---------------------------------------------------------------
-- 2. Poprawki zmian: co do minuty, z oryginałem i różnicą
-- ---------------------------------------------------------------

alter table public.staff_shifts
  add column if not exists original_started_at timestamptz,
  add column if not exists original_ended_at   timestamptz,
  add column if not exists edited_at           timestamptz,
  add column if not exists edited_by_member    uuid references public.staff_members (id) on delete set null;

drop function if exists public.panel_save_shift(uuid, uuid, timestamptz, timestamptz);
create or replace function public.panel_save_shift(
  p_id          uuid,
  p_member_id   uuid,
  p_started_at  timestamptz,
  p_ended_at    timestamptz,
  p_editor_id   uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_shift   staff_shifts%rowtype;
  v_start   timestamptz := date_trunc('minute', p_started_at);
  v_end     timestamptz := date_trunc('minute', p_ended_at);
begin
  select * into v_member from staff_members where id = p_member_id;
  if not found then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_staff(v_member.restaurant_id, 'manager');
  perform private.check_inventory_member(v_member.restaurant_id, p_editor_id);
  if v_start is null or (v_end is not null and v_end <= v_start) then
    raise exception 'Koniec zmiany musi być po jej początku.';
  end if;
  if v_end is not null and v_end > now() + interval '1 minute' then
    raise exception 'Koniec zmiany nie może być w przyszłości.';
  end if;

  if p_id is null then
    insert into staff_shifts (restaurant_id, member_id, started_at, ended_at, source)
    values (v_member.restaurant_id, p_member_id, v_start, v_end, 'panel');
    return;
  end if;

  select * into v_shift from staff_shifts where id = p_id and restaurant_id = v_member.restaurant_id;
  if not found then
    raise exception 'Nie znaleziono zmiany.';
  end if;
  if v_shift.started_at is not distinct from v_start and v_shift.ended_at is not distinct from v_end then
    return;
  end if;
  -- Pierwsza poprawka zapamiętuje, jak było; kolejne zostawiają ten sam oryginał.
  update staff_shifts
  set started_at = v_start,
      ended_at = v_end,
      original_started_at = coalesce(original_started_at, v_shift.started_at),
      original_ended_at = case when edited_at is null then v_shift.ended_at else original_ended_at end,
      edited_at = now(),
      edited_by_member = p_editor_id
  where id = p_id;
exception
  when unique_violation then
    raise exception 'Ten pracownik ma już otwartą zmianę. Najpierw ją zakończ.';
end;
$$;
revoke execute on function public.panel_save_shift(uuid, uuid, timestamptz, timestamptz, uuid) from public, anon;
grant execute on function public.panel_save_shift(uuid, uuid, timestamptz, timestamptz, uuid) to authenticated;

-- ---------------------------------------------------------------
-- 3. Spis inwentaryzacji: opakowania i gramy albo mililitry
-- ---------------------------------------------------------------

alter table public.inventory_count_lines
  add column if not exists packages numeric,
  add column if not exists loose    numeric;

-- Mniejsza jednostka do wpisywania reszty: g dla kg, ml dla l, sama jednostka dla g, ml i szt.
create or replace function private.inventory_portion(p_unit text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_unit when 'kg' then 'g' when 'l' then 'ml' else p_unit end
$$;

drop function if exists public.panel_inventory_set(uuid, uuid, numeric, uuid);
create or replace function public.panel_inventory_set(
  p_count_id   uuid,
  p_item_id    uuid,
  p_quantity   numeric,
  p_member_id  uuid default null,
  p_loose      numeric default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count     inventory_counts%rowtype;
  v_item      inventory_items%rowtype;
  v_per_pack  numeric;
  v_total     numeric;
begin
  select * into v_count from inventory_counts where id = p_count_id;
  if not found then
    raise exception 'Nie znaleziono inwentaryzacji.';
  end if;
  perform private.require_permission(v_count.restaurant_id, 'inventory_count');
  perform private.check_inventory_member(v_count.restaurant_id, p_member_id);
  if v_count.finished_at is not null then
    raise exception 'Ta inwentaryzacja jest już zakończona.';
  end if;
  select * into v_item from inventory_items
  where id = p_item_id and restaurant_id = v_count.restaurant_id and deleted_at is null;
  if not found then
    raise exception 'Nie znaleziono składnika.';
  end if;

  if p_quantity is null and p_loose is null then
    delete from inventory_count_lines where count_id = p_count_id and item_id = p_item_id;
    return;
  end if;
  if coalesce(p_quantity, 0) < 0 or coalesce(p_quantity, 0) > 1000000
     or coalesce(p_loose, 0) < 0 or coalesce(p_loose, 0) > 100000000 then
    raise exception 'Wpisz ilość od 0.';
  end if;

  -- Opakowanie w mniejszej jednostce, np. mąka 50 kg = 50 000 g. Reszta w gramach dolicza się do opakowań.
  v_per_pack := v_item.capacity * private.inventory_factor(v_item.unit, private.inventory_portion(v_item.unit));
  if coalesce(p_loose, 0) > 0 and (v_per_pack is null or v_per_pack <= 0) then
    raise exception 'Składnik nie ma pojemności opakowania.';
  end if;
  v_total := coalesce(p_quantity, 0) + case when coalesce(p_loose, 0) = 0 then 0 else p_loose / v_per_pack end;

  insert into inventory_count_lines (count_id, item_id, quantity, packages, loose, unit, capacity, counted_by_member)
  values (p_count_id, p_item_id, round(v_total, 6), p_quantity, p_loose, v_item.unit, v_item.capacity, p_member_id)
  on conflict (count_id, item_id) do update
    set quantity = excluded.quantity, packages = excluded.packages, loose = excluded.loose,
        unit = excluded.unit, capacity = excluded.capacity,
        counted_by_member = excluded.counted_by_member, updated_at = now();
end;
$$;
revoke execute on function public.panel_inventory_set(uuid, uuid, numeric, uuid, numeric) from public, anon;
grant execute on function public.panel_inventory_set(uuid, uuid, numeric, uuid, numeric) to authenticated;

create or replace function public.panel_inventory_counts(p_restaurant_id uuid, p_limit integer default 20)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (private.has_permission(p_restaurant_id, 'inventory_count')
          or private.has_permission(p_restaurant_id, 'inventory_edit')) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
  return (
    select coalesce(jsonb_agg(x.j order by x.started_at desc), '[]'::jsonb)
    from (
      select c.started_at, jsonb_build_object(
        'id', c.id,
        'started_at', c.started_at,
        'finished_at', c.finished_at,
        'started_by', sm.name,
        'finished_by', fm.name,
        'lines', coalesce((
          select jsonb_agg(jsonb_build_object(
            'item_id', l.item_id, 'name', i.name, 'unit', l.unit, 'capacity', l.capacity,
            'quantity', l.quantity, 'packages', l.packages, 'loose', l.loose, 'counted_by', cm.name,
            'used', case when p.updated_at is null then null else u.used end,
            'expected', case when p.updated_at is null then null else p.total - u.used end
          ) order by i.sort, lower(i.name))
          from inventory_count_lines l
          join inventory_items i on i.id = l.item_id
          left join staff_members cm on cm.id = l.counted_by_member
          left join lateral (
            select pl.quantity * pl.capacity * private.inventory_factor(pl.unit, l.unit) as total, pl.updated_at
            from inventory_count_lines pl
            join inventory_counts pc on pc.id = pl.count_id
            where pl.item_id = l.item_id and pc.id <> c.id and pc.finished_at is not null
              and pc.finished_at < coalesce(c.finished_at, now())
            order by pc.finished_at desc
            limit 1
          ) p on true
          left join lateral (
            select -coalesce(sum(m.amount), 0) * private.inventory_factor(i.unit, l.unit) as used
            from inventory_movements m
            where m.item_id = l.item_id and m.created_at > p.updated_at and m.created_at <= l.updated_at
          ) u on true
          where l.count_id = c.id
        ), '[]'::jsonb)
      ) as j
      from inventory_counts c
      left join staff_members sm on sm.id = c.started_by_member
      left join staff_members fm on fm.id = c.finished_by_member
      where c.restaurant_id = p_restaurant_id
      order by c.started_at desc
      limit greatest(1, least(coalesce(p_limit, 20), 100))
    ) x
  );
end;
$$;

-- ---------------------------------------------------------------
-- 4. Podsumowanie dnia: raporty kasy fiskalnej i terminali, petty cash
-- ---------------------------------------------------------------

create table public.day_reports (
  id                  uuid primary key default gen_random_uuid(),
  restaurant_id       uuid not null references public.restaurants (id) on delete cascade,
  day                 date not null,
  fiscal_grosze       integer check (fiscal_grosze is null or fiscal_grosze between 0 and 100000000),
  terminals           jsonb not null default '[]'::jsonb,
  cash_counted_grosze integer check (cash_counted_grosze is null or cash_counted_grosze between 0 and 100000000),
  note                text check (note is null or char_length(note) <= 2000),
  updated_at          timestamptz not null default now(),
  updated_by_member   uuid references public.staff_members (id) on delete set null,
  updated_by_name     text,
  unique (restaurant_id, day)
);
alter table public.day_reports enable row level security;
create policy day_reports_read on public.day_reports
  for select to authenticated using (private.has_permission(restaurant_id, 'day_close'));

create table public.petty_cash (
  id              uuid primary key default gen_random_uuid(),
  restaurant_id   uuid not null references public.restaurants (id) on delete cascade,
  day             date not null,
  kind            text not null default 'out' check (kind in ('out', 'in')),
  description     text not null check (char_length(description) between 1 and 200),
  amount_grosze   integer not null check (amount_grosze between 1 and 10000000),
  author_member   uuid references public.staff_members (id) on delete set null,
  author_name     text,
  created_at      timestamptz not null default now()
);
create index petty_cash_day_idx on public.petty_cash (restaurant_id, day);
alter table public.petty_cash enable row level security;
create policy petty_cash_read on public.petty_cash
  for select to authenticated using (private.has_permission(restaurant_id, 'day_close'));

-- Dzień lokalu w jego strefie czasowej: od północy do północy.
create or replace function private.day_range(p_restaurant_id uuid, p_day date, out starts timestamptz, out ends timestamptz)
language sql
stable
set search_path = ''
as $$
  select
    (p_day::timestamp at time zone coalesce(r.timezone, 'Europe/Warsaw')),
    ((p_day + 1)::timestamp at time zone coalesce(r.timezone, 'Europe/Warsaw'))
  from public.restaurants r
  where r.id = p_restaurant_id
$$;

-- Sprzedaż dnia według sposobu płatności, raport kasy i terminali, petty cash i gotówka, która powinna być w kasie.
create or replace function public.panel_day_summary(p_restaurant_id uuid, p_day date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_start timestamptz;
  v_end   timestamptz;
begin
  perform private.require_permission(p_restaurant_id, 'day_close');
  select starts, ends into v_start, v_end from private.day_range(p_restaurant_id, p_day);
  return (
    with paid as (
      select o.id, o.kind, o.payment_method, o.payment_choice,
             (select coalesce(sum(i.unit_price_grosze * i.quantity), 0)
              from order_items i where i.order_id = o.id and i.status <> 'cancelled')
             + coalesce(o.delivery_fee_grosze, 0) as total
      from orders o
      where o.restaurant_id = p_restaurant_id and o.status = 'paid'
        and o.closed_at >= v_start and o.closed_at < v_end
    ),
    methods as (
      select case
               when payment_choice = 'card_online' then 'card_online'
               when payment_method in ('cash', 'card') then payment_method
               else 'other'
             end as method,
             total
      from paid
    ),
    petty as (
      select * from petty_cash where restaurant_id = p_restaurant_id and day = p_day
    )
    select jsonb_build_object(
      'day', p_day,
      'revenue', coalesce((select sum(total) from paid), 0),
      'orders', (select count(*) from paid),
      'dine_in', (select count(*) from paid where kind = 'dine_in'),
      'takeaway', (select count(*) from paid where kind <> 'dine_in'),
      'cash', coalesce((select sum(total) from methods where method = 'cash'), 0),
      'card', coalesce((select sum(total) from methods where method = 'card'), 0),
      'card_online', coalesce((select sum(total) from methods where method = 'card_online'), 0),
      'other', coalesce((select sum(total) from methods where method = 'other'), 0),
      'cancelled', (select count(*) from orders o where o.restaurant_id = p_restaurant_id and o.status = 'cancelled'
                    and o.closed_at >= v_start and o.closed_at < v_end),
      'petty_out', coalesce((select sum(amount_grosze) from petty where kind = 'out'), 0),
      'petty_in', coalesce((select sum(amount_grosze) from petty where kind = 'in'), 0),
      'petty', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', id, 'kind', kind, 'description', description, 'amount_grosze', amount_grosze,
          'author_name', author_name, 'created_at', created_at
        ) order by created_at)
        from petty
      ), '[]'::jsonb),
      'report', (
        select jsonb_build_object(
          'fiscal_grosze', r.fiscal_grosze, 'terminals', r.terminals, 'cash_counted_grosze', r.cash_counted_grosze,
          'note', r.note, 'updated_at', r.updated_at, 'updated_by_name', r.updated_by_name
        )
        from day_reports r where r.restaurant_id = p_restaurant_id and r.day = p_day
      )
    )
  );
end;
$$;

create or replace function public.panel_save_day_report(
  p_restaurant_id  uuid,
  p_day            date,
  p_fiscal         integer,
  p_terminals      jsonb,
  p_cash_counted   integer,
  p_note           text,
  p_member_id      uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_terminals jsonb;
begin
  perform private.require_permission(p_restaurant_id, 'day_close');
  perform private.check_inventory_member(p_restaurant_id, p_member_id);
  if p_day > (now() at time zone 'Europe/Warsaw')::date + 1 then
    raise exception 'Nie można wpisać raportu na przyszły dzień.';
  end if;
  -- Terminale: lista nazw i kwot, puste wiersze odpadają.
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', left(coalesce(nullif(trim(t->>'name'), ''), 'Terminal'), 60),
           'grosze', greatest(0, least((t->>'grosze')::integer, 100000000))
         )), '[]'::jsonb)
  into v_terminals
  from jsonb_array_elements(coalesce(p_terminals, '[]'::jsonb)) t
  where (t->>'grosze') is not null;

  insert into day_reports (restaurant_id, day, fiscal_grosze, terminals, cash_counted_grosze, note,
                           updated_at, updated_by_member, updated_by_name)
  values (p_restaurant_id, p_day, p_fiscal, v_terminals, p_cash_counted, nullif(trim(p_note), ''),
          now(), p_member_id, private.note_author(p_restaurant_id, p_member_id))
  on conflict (restaurant_id, day) do update
    set fiscal_grosze = excluded.fiscal_grosze, terminals = excluded.terminals,
        cash_counted_grosze = excluded.cash_counted_grosze, note = excluded.note,
        updated_at = now(), updated_by_member = excluded.updated_by_member, updated_by_name = excluded.updated_by_name;
end;
$$;

create or replace function public.panel_add_petty(
  p_restaurant_id  uuid,
  p_day            date,
  p_kind           text,
  p_description    text,
  p_amount         integer,
  p_member_id      uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform private.require_permission(p_restaurant_id, 'day_close');
  perform private.check_inventory_member(p_restaurant_id, p_member_id);
  if coalesce(trim(p_description), '') = '' then
    raise exception 'Wpisz, na co poszły pieniądze.';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Wpisz kwotę większą od zera.';
  end if;
  insert into petty_cash (restaurant_id, day, kind, description, amount_grosze, author_member, author_name)
  values (p_restaurant_id, p_day, coalesce(p_kind, 'out'), trim(p_description), p_amount, p_member_id,
          private.note_author(p_restaurant_id, p_member_id))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.panel_delete_petty(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row petty_cash%rowtype;
begin
  select * into v_row from petty_cash where id = p_id;
  if not found then
    raise exception 'Nie znaleziono wpisu.';
  end if;
  perform private.require_permission(v_row.restaurant_id, 'day_close');
  delete from petty_cash where id = p_id;
end;
$$;

revoke execute on function private.inventory_portion(text) from public, anon;
revoke execute on function private.day_range(uuid, date) from public, anon;
revoke execute on function public.panel_day_summary(uuid, date) from public, anon;
revoke execute on function public.panel_save_day_report(uuid, date, integer, jsonb, integer, text, uuid) from public, anon;
revoke execute on function public.panel_add_petty(uuid, date, text, text, integer, uuid) from public, anon;
revoke execute on function public.panel_delete_petty(uuid) from public, anon;
grant execute on function private.inventory_portion(text) to authenticated;
grant execute on function private.day_range(uuid, date) to authenticated;
grant execute on function public.panel_day_summary(uuid, date) to authenticated;
grant execute on function public.panel_save_day_report(uuid, date, integer, jsonb, integer, text, uuid) to authenticated;
grant execute on function public.panel_add_petty(uuid, date, text, text, integer, uuid) to authenticated;
grant execute on function public.panel_delete_petty(uuid) to authenticated;

-- Reszta w gramach dzielona przez duże opakowanie daje ułamki mniejsze niż 0,001 opakowania.
alter table public.inventory_count_lines alter column quantity type numeric(16, 6);
