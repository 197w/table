-- Table · migracja 0037
-- Receptury: składniki z inwentaryzacji przypisane do dań w menu (ile czego zużywa jedna porcja).
-- Widzi je tylko obsługa lokalu, aplikacja Table dla gości ich nie dostaje (RLS).
-- Wysłanie pozycji zamówienia (na kuchnię albo od razu do wydania) zapisuje zużycie w inventory_movements,
-- anulowanie je cofa. Stan składnika = ostatnia inwentaryzacja + ruchy od chwili, gdy go policzono.

-- Przelicznik jednostek: ml ↔ l, g ↔ kg. Null: jednostek nie da się przeliczyć.
create or replace function private.inventory_factor(p_from text, p_to text)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case
    when p_from = p_to then 1
    when p_from = 'ml' and p_to = 'l' then 0.001
    when p_from = 'l' and p_to = 'ml' then 1000
    when p_from = 'g' and p_to = 'kg' then 0.001
    when p_from = 'kg' and p_to = 'g' then 1000
  end
$$;

create table public.menu_item_ingredients (
  menu_item_id  uuid not null references public.menu_items (id) on delete cascade,
  item_id       uuid not null references public.inventory_items (id) on delete cascade,
  -- Zużycie na jedną porcję w jednostce unit, np. 50 ml wódki, gdy składnik liczymy w litrach.
  amount        numeric(12, 3) not null check (amount > 0),
  unit          text not null check (unit in ('ml', 'l', 'g', 'kg', 'szt')),
  primary key (menu_item_id, item_id)
);

create index menu_item_ingredients_item_idx on public.menu_item_ingredients (item_id);
alter table public.menu_item_ingredients enable row level security;

create policy "Obsługa widzi receptury lokalu"
  on public.menu_item_ingredients for select to authenticated
  using (exists (
    select 1 from public.menu_items i
    join public.menu_sections s on s.id = i.section_id
    where i.id = menu_item_ingredients.menu_item_id and private.has_staff_role(s.restaurant_id)
  ));

-- Nowy składnik można dodać także z okna dania w Menu.
create policy "Edycja menu dodaje składniki"
  on public.inventory_items for insert to authenticated
  with check (private.has_permission(restaurant_id, 'menu_edit'));

create table public.inventory_movements (
  id             uuid primary key default gen_random_uuid(),
  restaurant_id  uuid not null references public.restaurants (id) on delete cascade,
  item_id        uuid not null references public.inventory_items (id) on delete cascade,
  -- Zmiana stanu w jednostce składnika: sprzedaż jest ujemna.
  amount         numeric(14, 4) not null,
  kind           text not null default 'sale' check (kind in ('sale')),
  order_item_id  uuid references public.order_items (id) on delete cascade,
  created_at     timestamptz not null default now()
);

create index inventory_movements_item_idx on public.inventory_movements (item_id, created_at);
create index inventory_movements_order_item_idx on public.inventory_movements (order_item_id);
alter table public.inventory_movements enable row level security;

create policy "Obsługa widzi ruchy składników"
  on public.inventory_movements for select to authenticated
  using (private.has_staff_role(restaurant_id));

-- Receptura dania: cała lista naraz, [{item_id, amount, unit}].
create or replace function public.panel_set_menu_item_ingredients(p_menu_item_id uuid, p_lines jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_line        jsonb;
  v_item        inventory_items%rowtype;
  v_amount      numeric;
  v_unit        text;
begin
  select s.restaurant_id into v_restaurant
  from menu_items i
  join menu_sections s on s.id = i.section_id
  where i.id = p_menu_item_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono pozycji w menu.';
  end if;
  perform private.require_permission(v_restaurant, 'menu_edit');

  p_lines := coalesce(p_lines, '[]'::jsonb);
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 50 then
    raise exception 'Danie może mieć najwyżej 50 składników.';
  end if;

  delete from menu_item_ingredients where menu_item_id = p_menu_item_id;
  for v_line in select * from jsonb_array_elements(p_lines) loop
    select * into v_item from inventory_items
    where id = (v_line ->> 'item_id')::uuid and restaurant_id = v_restaurant and deleted_at is null;
    if not found then
      raise exception 'Nie znaleziono składnika.';
    end if;
    v_amount := (v_line ->> 'amount')::numeric;
    v_unit := v_line ->> 'unit';
    if v_amount is null or v_amount <= 0 or v_amount > 1000000 then
      raise exception 'Wpisz, ile składnika „%” zużywa jedna porcja.', v_item.name;
    end if;
    if private.inventory_factor(v_unit, v_item.unit) is null then
      raise exception 'Jednostka nie pasuje do składnika „%”.', v_item.name;
    end if;
    insert into menu_item_ingredients (menu_item_id, item_id, amount, unit)
    values (p_menu_item_id, v_item.id, round(v_amount, 3), v_unit)
    on conflict (menu_item_id, item_id) do update set amount = excluded.amount, unit = excluded.unit;
  end loop;
end;
$$;

-- Zużycie składników przy sprzedaży. Liczy się od wysłania pozycji; kolejne stany (gotowe, wydane)
-- nic nie zmieniają, anulowanie cofa zużycie. Receptura z chwili wysłania.
create or replace function private.order_item_inventory()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.status = old.status and new.quantity = old.quantity then
    return new;
  end if;

  if new.status in ('sent', 'ready', 'served') then
    if tg_op = 'INSERT' or old.status in ('new', 'cancelled') or old.quantity <> new.quantity then
      delete from public.inventory_movements where order_item_id = new.id;
      insert into public.inventory_movements (restaurant_id, item_id, amount, kind, order_item_id)
      select new.restaurant_id, r.item_id, -(new.quantity * r.amount * private.inventory_factor(r.unit, i.unit)), 'sale', new.id
      from public.menu_item_ingredients r
      join public.inventory_items i on i.id = r.item_id and i.deleted_at is null
      where r.menu_item_id = new.menu_item_id
        and private.inventory_factor(r.unit, i.unit) is not null;
    end if;
  else
    delete from public.inventory_movements where order_item_id = new.id;
  end if;
  return new;
end;
$$;

create trigger order_items_inventory
  after insert or update of status, quantity on public.order_items
  for each row execute function private.order_item_inventory();

-- Stan składników teraz: ostatnia inwentaryzacja, w której go policzono, i zużycie od tej chwili.
create or replace function public.panel_inventory_stock(p_restaurant_id uuid)
returns table (item_id uuid, counted numeric, counted_at timestamptz, used numeric, stock numeric)
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
  return query
    with last_line as (
      select distinct on (l.item_id)
             l.item_id,
             l.quantity * l.capacity * private.inventory_factor(l.unit, i.unit) as total,
             l.updated_at
      from inventory_count_lines l
      join inventory_counts c on c.id = l.count_id and c.finished_at is not null
      join inventory_items i on i.id = l.item_id
      where c.restaurant_id = p_restaurant_id
      order by l.item_id, c.finished_at desc
    )
    select i.id,
           ll.total,
           ll.updated_at,
           coalesce((select -sum(m.amount) from inventory_movements m
                     where m.item_id = i.id and m.created_at > coalesce(ll.updated_at, i.created_at)), 0),
           ll.total + coalesce((select sum(m.amount) from inventory_movements m
                                where m.item_id = i.id and m.created_at > ll.updated_at), 0)
    from inventory_items i
    left join last_line ll on ll.item_id = i.id
    where i.restaurant_id = p_restaurant_id and i.deleted_at is null;
end;
$$;

-- Jak w 0036, a przy każdej pozycji także zużycie ze sprzedaży od poprzedniej inwentaryzacji
-- (used) i stan, który z tego wynika (expected). Obie wartości w jednostce pozycji.
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
            'quantity', l.quantity, 'counted_by', cm.name,
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

revoke execute on function private.inventory_factor(text, text) from public, anon;
revoke execute on function public.panel_set_menu_item_ingredients(uuid, jsonb) from public, anon;
revoke execute on function public.panel_inventory_stock(uuid) from public, anon;
grant execute on function private.inventory_factor(text, text) to authenticated;
grant execute on function public.panel_set_menu_item_ingredients(uuid, jsonb) to authenticated;
grant execute on function public.panel_inventory_stock(uuid) to authenticated;
