-- Table · migracja 0036
-- Inwentaryzacja (zakładka „Inwentaryzacja” w panelu):
-- 1. Składniki lokalu z pojemnością opakowania (np. 0,7 l butelki, 25 kg worka).
-- 2. Spisy: ilość każdego składnika w opakowaniach, najwyżej jeden otwarty spis na lokal.
-- 3. Okres, co ile lokal robi inwentaryzację (restaurants.inventory_period).
-- Uprawnienia: inventory_edit („Edytowanie składników”: dodawanie, zmiana i usuwanie składników)
-- i inventory_count („Wpisywanie ilości składników”).

alter table public.restaurants
  add column inventory_period text not null default 'week'
    check (inventory_period in ('day', 'week', 'two_weeks', 'month'));

create table public.inventory_items (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  name           text not null check (char_length(btrim(name)) between 1 and 80),
  -- Jednostka pojemności: ml, l, g, kg albo szt (sztuki w opakowaniu).
  unit           text not null check (unit in ('ml', 'l', 'g', 'kg', 'szt')),
  -- Pojemność jednego opakowania w jednostce.
  capacity       numeric(12, 3) not null check (capacity > 0),
  sort           integer not null default 0,
  -- Usunięty składnik znika z listy, ale zostaje w historii spisów.
  deleted_at     timestamptz,
  created_at     timestamptz not null default now()
);

create unique index inventory_items_name_idx
  on public.inventory_items (restaurant_id, lower(btrim(name))) where deleted_at is null;
alter table public.inventory_items enable row level security;

create policy "Obsługa widzi składniki lokalu"
  on public.inventory_items for select to authenticated
  using (private.has_staff_role(restaurant_id));

create policy "Edytowanie składników dodaje składniki"
  on public.inventory_items for insert to authenticated
  with check (private.has_permission(restaurant_id, 'inventory_edit'));

create policy "Edytowanie składników zmienia i usuwa składniki"
  on public.inventory_items for update to authenticated
  using (private.has_permission(restaurant_id, 'inventory_edit'))
  with check (private.has_permission(restaurant_id, 'inventory_edit'));

create table public.inventory_counts (
  id                  uuid primary key default gen_random_uuid(),
  restaurant_id       uuid not null references public.restaurants (id) on delete cascade,
  started_at          timestamptz not null default now(),
  started_by_member   uuid references public.staff_members (id) on delete set null,
  -- Null: spis trwa.
  finished_at         timestamptz,
  finished_by_member  uuid references public.staff_members (id) on delete set null
);

create unique index inventory_counts_open_idx on public.inventory_counts (restaurant_id) where finished_at is null;
create index inventory_counts_restaurant_idx on public.inventory_counts (restaurant_id, started_at desc);
alter table public.inventory_counts enable row level security;

create policy "Obsługa widzi spisy lokalu"
  on public.inventory_counts for select to authenticated
  using (private.has_staff_role(restaurant_id));

create table public.inventory_count_lines (
  count_id           uuid not null references public.inventory_counts (id) on delete cascade,
  item_id            uuid not null references public.inventory_items (id) on delete cascade,
  -- Liczba opakowań, także częściowa (np. 2,5 butelki).
  quantity           numeric(12, 3) not null check (quantity >= 0),
  -- Jednostka i pojemność z chwili spisu: późniejsza zmiana składnika nie zmienia historii.
  unit               text not null,
  capacity           numeric(12, 3) not null,
  counted_by_member  uuid references public.staff_members (id) on delete set null,
  updated_at         timestamptz not null default now(),
  primary key (count_id, item_id)
);

alter table public.inventory_count_lines enable row level security;

create policy "Obsługa widzi pozycje spisów"
  on public.inventory_count_lines for select to authenticated
  using (exists (
    select 1 from public.inventory_counts c
    where c.id = inventory_count_lines.count_id and private.has_staff_role(c.restaurant_id)
  ));

-- Pracownik zapisany przy spisie musi być z tego lokalu.
create or replace function private.check_inventory_member(p_restaurant_id uuid, p_member_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_member_id is not null and not exists (
    select 1 from public.staff_members where id = p_member_id and restaurant_id = p_restaurant_id
  ) then
    raise exception 'Nie znaleziono pracownika.';
  end if;
end;
$$;

-- Co ile lokal robi inwentaryzację.
create or replace function public.panel_set_inventory_period(p_restaurant_id uuid, p_period text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.require_permission(p_restaurant_id, 'inventory_edit');
  if p_period is null or p_period not in ('day', 'week', 'two_weeks', 'month') then
    raise exception 'Wybierz, co ile robicie inwentaryzację.';
  end if;
  update restaurants set inventory_period = p_period where id = p_restaurant_id;
end;
$$;

-- Zaczyna spis albo zwraca ten, który już trwa.
create or replace function public.panel_inventory_start(p_restaurant_id uuid, p_member_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  uuid;
begin
  perform private.require_permission(p_restaurant_id, 'inventory_count');
  perform private.check_inventory_member(p_restaurant_id, p_member_id);
  select id into v_id from inventory_counts where restaurant_id = p_restaurant_id and finished_at is null;
  if v_id is not null then
    return v_id;
  end if;
  if not exists (select 1 from inventory_items where restaurant_id = p_restaurant_id and deleted_at is null) then
    raise exception 'Najpierw dodaj składniki.';
  end if;
  insert into inventory_counts (restaurant_id, started_by_member)
  values (p_restaurant_id, p_member_id)
  returning id into v_id;
  return v_id;
end;
$$;

-- Ilość składnika w trwającym spisie (w opakowaniach). Null czyści wpis.
create or replace function public.panel_inventory_set(
  p_count_id   uuid,
  p_item_id    uuid,
  p_quantity   numeric,
  p_member_id  uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count  inventory_counts%rowtype;
  v_item   inventory_items%rowtype;
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

  if p_quantity is null then
    delete from inventory_count_lines where count_id = p_count_id and item_id = p_item_id;
    return;
  end if;
  if p_quantity < 0 or p_quantity > 1000000 then
    raise exception 'Wpisz ilość od 0.';
  end if;
  insert into inventory_count_lines (count_id, item_id, quantity, unit, capacity, counted_by_member)
  values (p_count_id, p_item_id, round(p_quantity, 3), v_item.unit, v_item.capacity, p_member_id)
  on conflict (count_id, item_id) do update
    set quantity = excluded.quantity, unit = excluded.unit, capacity = excluded.capacity,
        counted_by_member = excluded.counted_by_member, updated_at = now();
end;
$$;

create or replace function public.panel_inventory_finish(p_count_id uuid, p_member_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count  inventory_counts%rowtype;
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
  if not exists (select 1 from inventory_count_lines where count_id = p_count_id) then
    raise exception 'Wpisz ilość choć jednego składnika.';
  end if;
  update inventory_counts set finished_at = now(), finished_by_member = p_member_id where id = p_count_id;
end;
$$;

-- Anulowanie trwającego spisu (zakończonych nie da się usunąć).
create or replace function public.panel_inventory_discard(p_count_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count  inventory_counts%rowtype;
begin
  select * into v_count from inventory_counts where id = p_count_id;
  if not found then
    return;
  end if;
  perform private.require_permission(v_count.restaurant_id, 'inventory_count');
  if v_count.finished_at is not null then
    raise exception 'Zakończonej inwentaryzacji nie można anulować.';
  end if;
  delete from inventory_counts where id = p_count_id;
end;
$$;

-- Spisy lokalu od najnowszego (trwający pierwszy) z pozycjami i imionami pracowników.
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
            'quantity', l.quantity, 'counted_by', cm.name
          ) order by i.sort, lower(i.name))
          from inventory_count_lines l
          join inventory_items i on i.id = l.item_id
          left join staff_members cm on cm.id = l.counted_by_member
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

revoke execute on function private.check_inventory_member(uuid, uuid) from public, anon;
revoke execute on function public.panel_set_inventory_period(uuid, text) from public, anon;
revoke execute on function public.panel_inventory_start(uuid, uuid) from public, anon;
revoke execute on function public.panel_inventory_set(uuid, uuid, numeric, uuid) from public, anon;
revoke execute on function public.panel_inventory_finish(uuid, uuid) from public, anon;
revoke execute on function public.panel_inventory_discard(uuid) from public, anon;
revoke execute on function public.panel_inventory_counts(uuid, integer) from public, anon;
grant execute on function private.check_inventory_member(uuid, uuid) to authenticated;
grant execute on function public.panel_set_inventory_period(uuid, text) to authenticated;
grant execute on function public.panel_inventory_start(uuid, uuid) to authenticated;
grant execute on function public.panel_inventory_set(uuid, uuid, numeric, uuid) to authenticated;
grant execute on function public.panel_inventory_finish(uuid, uuid) to authenticated;
grant execute on function public.panel_inventory_discard(uuid) to authenticated;
grant execute on function public.panel_inventory_counts(uuid, integer) to authenticated;

-- Nowe uprawnienia. „ALL” dostaje je samo (private.position_permissions), pozostałe stanowiska nadaje osoba
-- z uprawnieniem „Stanowiska”.
create or replace function private.all_permissions()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['reservations', 'floor', 'floor_edit', 'orders', 'orders_close', 'orders_cancel', 'deliveries',
               'kitchen', 'kitchen_settings', 'staff', 'staff_logins', 'schedule', 'timesheet', 'positions',
               'profile', 'menu', 'menu_edit', 'menu_availability', 'gift_cards', 'inventory_edit', 'inventory_count',
               'reviews', 'stats']
$$;

update public.staff_positions set permissions = private.all_permissions() where system_key = 'all';
