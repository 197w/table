-- Inwentaryzacja, druga wersja (10.2026). Wszystko liczy się samo z ruchów składników:
-- * dostawy (kiedy przyjechały, co przyjechało) dodają stan, usunięcia (z powodem i wyjaśnieniem, np. przekazanie
--   do drugiego lokalu) go odejmują; jedno i drugie to dokumenty `inventory_docs` z ruchami w `inventory_movements`,
-- * składnik ma lokalizację, nazwę opakowania (zgrzewka, worek, puszka) i zwykły pojemnik do ważenia,
-- * pojemniki lokalu (mały, średni, duży) z wagą: przy „ważone w pojemniku” waga pojemnika odejmuje się sama,
-- * spis pokazuje dostawy i usunięcia z okresu, a stan „powinno być” uwzględnia sprzedaż, dostawy i usunięcia,
-- * spis działa też w Table for employees (uprawnienie pracownika, `private.inventory_allowed`).

-- ---------------------------------------------------------------
-- Pojemniki do ważenia
-- ---------------------------------------------------------------

create table if not exists public.inventory_containers (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants (id) on delete cascade,
  name          text not null check (char_length(btrim(name)) between 1 and 40),
  tare_g        numeric not null check (tare_g >= 0 and tare_g <= 100000),
  sort          int not null default 0,
  created_at    timestamptz not null default now()
);

alter table public.inventory_containers enable row level security;
drop policy if exists "Obsługa widzi pojemniki lokalu" on public.inventory_containers;
create policy "Obsługa widzi pojemniki lokalu" on public.inventory_containers
  for select to authenticated using (private.has_staff_role(restaurant_id));

-- ---------------------------------------------------------------
-- Składnik: lokalizacja, opakowanie, zwykły pojemnik
-- ---------------------------------------------------------------

alter table public.inventory_items
  add column if not exists location text check (location is null or char_length(location) <= 60),
  add column if not exists pack_name text check (pack_name is null or char_length(pack_name) <= 30),
  add column if not exists container_id uuid references public.inventory_containers (id) on delete set null;

-- Pozycja spisu: pojemnik z chwili spisu, jego waga i waga z pojemnikiem (w gramach).
alter table public.inventory_count_lines
  add column if not exists container_id uuid references public.inventory_containers (id) on delete set null,
  add column if not exists container_name text,
  add column if not exists tare numeric,
  add column if not exists gross numeric;

-- ---------------------------------------------------------------
-- Dostawy i usunięcia
-- ---------------------------------------------------------------

create table if not exists public.inventory_docs (
  id                uuid primary key default gen_random_uuid(),
  restaurant_id     uuid not null references public.restaurants (id) on delete cascade,
  kind              text not null check (kind in ('delivery', 'removal')),
  -- Kiedy dostawa przyjechała albo składnik zniknął z lokalu (ruchy mają tę samą chwilę).
  happened_at       timestamptz not null default now(),
  -- Usunięcie: przekazanie do innego lokalu, zwrot do dostawcy, strata, posiłek pracowniczy, inny.
  reason            text check (reason in ('transfer', 'return', 'loss', 'staff', 'other')),
  supplier          text check (supplier is null or char_length(supplier) <= 120),
  document_no       text check (document_no is null or char_length(document_no) <= 60),
  note              text check (note is null or char_length(note) <= 500),
  created_by_member uuid references public.staff_members (id) on delete set null,
  created_at        timestamptz not null default now(),
  check (kind = 'delivery' or reason is not null)
);

create index if not exists inventory_docs_restaurant_idx on public.inventory_docs (restaurant_id, happened_at desc);

create table if not exists public.inventory_doc_lines (
  doc_id   uuid not null references public.inventory_docs (id) on delete cascade,
  item_id  uuid not null references public.inventory_items (id) on delete cascade,
  packages numeric check (packages is null or packages >= 0),
  loose    numeric check (loose is null or loose >= 0),
  -- Razem w jednostce składnika (z jednostką i pojemnością z chwili wpisu).
  amount   numeric not null check (amount > 0),
  unit     text not null,
  capacity numeric not null,
  primary key (doc_id, item_id)
);

alter table public.inventory_docs enable row level security;
alter table public.inventory_doc_lines enable row level security;
drop policy if exists "Obsługa widzi dostawy i usunięcia" on public.inventory_docs;
create policy "Obsługa widzi dostawy i usunięcia" on public.inventory_docs
  for select to authenticated using (private.has_staff_role(restaurant_id));
drop policy if exists "Obsługa widzi pozycje dostaw i usunięć" on public.inventory_doc_lines;
create policy "Obsługa widzi pozycje dostaw i usunięć" on public.inventory_doc_lines
  for select to authenticated using (
    exists (select 1 from public.inventory_docs d where d.id = doc_id and private.has_staff_role(d.restaurant_id))
  );

alter table public.inventory_movements
  add column if not exists doc_id uuid references public.inventory_docs (id) on delete cascade;
alter table public.inventory_movements drop constraint if exists inventory_movements_kind_check;
alter table public.inventory_movements
  add constraint inventory_movements_kind_check check (kind in ('sale', 'delivery', 'removal'));

-- ---------------------------------------------------------------
-- Pomocnicze
-- ---------------------------------------------------------------

-- Panel: uprawnienie konta albo zalogowanego pracownika. Table for employees: własny pracownik z uprawnieniem.
create or replace function private.inventory_allowed(p_restaurant_id uuid, p_member_id uuid, p_permission text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if private.has_permission(p_restaurant_id, p_permission) then
    return;
  end if;
  if p_member_id is not null and exists (
    select 1 from private.my_members() m
    where m.id = p_member_id and m.restaurant_id = p_restaurant_id
      and p_permission = any (private.member_permissions(m.id))
  ) then
    return;
  end if;
  raise exception 'Nie masz uprawnień do tej części panelu.';
end;
$$;

-- Ilość w jednostce składnika z pełnych opakowań i reszty w mniejszej jednostce (g, ml, szt.).
create or replace function private.inventory_amount(p_unit text, p_capacity numeric, p_packages numeric, p_loose numeric)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_packages, 0) * p_capacity
       + coalesce(p_loose, 0) * private.inventory_factor(private.inventory_portion(p_unit), p_unit)
$$;

-- ---------------------------------------------------------------
-- Spis
-- ---------------------------------------------------------------

create or replace function public.panel_inventory_start(p_restaurant_id uuid, p_member_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_id uuid;
begin
  perform private.inventory_allowed(p_restaurant_id, p_member_id, 'inventory_count');
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

create or replace function public.panel_inventory_finish(p_count_id uuid, p_member_id uuid default null)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_count inventory_counts%rowtype;
begin
  select * into v_count from inventory_counts where id = p_count_id;
  if not found then
    raise exception 'Nie znaleziono inwentaryzacji.';
  end if;
  perform private.inventory_allowed(v_count.restaurant_id, p_member_id, 'inventory_count');
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

-- Ilość składnika w spisie: pełne opakowania i reszta. Z pojemnikiem reszta to waga z pojemnikiem (g),
-- a zapisuje się waga bez niego.
drop function if exists public.panel_inventory_set(uuid, uuid, numeric, uuid, numeric);
create or replace function public.panel_inventory_set(
  p_count_id uuid,
  p_item_id uuid,
  p_quantity numeric,
  p_member_id uuid default null,
  p_loose numeric default null,
  p_container_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_count    inventory_counts%rowtype;
  v_item     inventory_items%rowtype;
  v_box      inventory_containers%rowtype;
  v_per_pack numeric;
  v_net      numeric := p_loose;
  v_total    numeric;
begin
  select * into v_count from inventory_counts where id = p_count_id;
  if not found then
    raise exception 'Nie znaleziono inwentaryzacji.';
  end if;
  perform private.inventory_allowed(v_count.restaurant_id, p_member_id, 'inventory_count');
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

  if p_container_id is not null then
    if v_item.unit not in ('g', 'kg') then
      raise exception 'Pojemnik odejmuje się tylko przy ważeniu (g, kg).';
    end if;
    select * into v_box from inventory_containers where id = p_container_id and restaurant_id = v_count.restaurant_id;
    if not found then
      raise exception 'Nie znaleziono pojemnika.';
    end if;
    if p_loose is null then
      raise exception 'Wpisz wagę z pojemnikiem.';
    end if;
    if p_loose < v_box.tare_g then
      raise exception 'Waga % g jest mniejsza niż sam pojemnik „%” (% g).', p_loose, v_box.name, v_box.tare_g;
    end if;
    v_net := p_loose - v_box.tare_g;
  end if;

  v_per_pack := v_item.capacity * private.inventory_factor(v_item.unit, private.inventory_portion(v_item.unit));
  if coalesce(v_net, 0) > 0 and (v_per_pack is null or v_per_pack <= 0) then
    raise exception 'Składnik nie ma pojemności opakowania.';
  end if;
  v_total := coalesce(p_quantity, 0) + case when coalesce(v_net, 0) = 0 then 0 else v_net / v_per_pack end;

  insert into inventory_count_lines (
    count_id, item_id, quantity, packages, loose, unit, capacity, counted_by_member,
    container_id, container_name, tare, gross
  )
  values (
    p_count_id, p_item_id, round(v_total, 6), p_quantity, v_net, v_item.unit, v_item.capacity, p_member_id,
    p_container_id, v_box.name, v_box.tare_g, case when p_container_id is null then null else p_loose end
  )
  on conflict (count_id, item_id) do update
    set quantity = excluded.quantity, packages = excluded.packages, loose = excluded.loose,
        unit = excluded.unit, capacity = excluded.capacity, counted_by_member = excluded.counted_by_member,
        container_id = excluded.container_id, container_name = excluded.container_name,
        tare = excluded.tare, gross = excluded.gross, updated_at = now();
end;
$$;

-- Stan teraz: ostatnia inwentaryzacja składnika i ruchy od niej (sprzedaż, dostawy, usunięcia).
drop function if exists public.panel_inventory_stock(uuid);
create or replace function public.panel_inventory_stock(p_restaurant_id uuid, p_member_id uuid default null)
returns table (
  item_id uuid,
  counted numeric,
  counted_at timestamptz,
  used numeric,
  delivered numeric,
  removed numeric,
  stock numeric
)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  begin
    perform private.inventory_allowed(p_restaurant_id, p_member_id, 'inventory_count');
  exception when others then
    perform private.inventory_allowed(p_restaurant_id, p_member_id, 'inventory_edit');
  end;
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
    ),
    moves as (
      select i.id,
             coalesce(sum(-m.amount) filter (where m.kind = 'sale'), 0) as sold,
             coalesce(sum(m.amount) filter (where m.kind = 'delivery'), 0) as delivered,
             coalesce(sum(-m.amount) filter (where m.kind = 'removal'), 0) as removed,
             coalesce(sum(m.amount), 0) as net
      from inventory_items i
      left join last_line ll on ll.item_id = i.id
      left join inventory_movements m on m.item_id = i.id and m.created_at > coalesce(ll.updated_at, i.created_at)
      where i.restaurant_id = p_restaurant_id and i.deleted_at is null
      group by i.id
    )
    select i.id, ll.total, ll.updated_at, mv.sold, mv.delivered, mv.removed, ll.total + mv.net
    from inventory_items i
    join moves mv on mv.id = i.id
    left join last_line ll on ll.item_id = i.id
    where i.restaurant_id = p_restaurant_id and i.deleted_at is null;
end;
$$;

-- Spisy z pozycjami (ilość, pojemnik, poprzednio, sprzedaż, dostawy, usunięcia, „powinno być”) i dokumentami
-- z okresu: dostawy i usunięcia od poprzedniej zakończonej inwentaryzacji do tej.
drop function if exists public.panel_inventory_counts(uuid, integer);
create or replace function public.panel_inventory_counts(
  p_restaurant_id uuid,
  p_limit integer default 20,
  p_member_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  begin
    perform private.inventory_allowed(p_restaurant_id, p_member_id, 'inventory_count');
  exception when others then
    perform private.inventory_allowed(p_restaurant_id, p_member_id, 'inventory_edit');
  end;
  return (
    select coalesce(jsonb_agg(x.j order by x.started_at desc), '[]'::jsonb)
    from (
      select c.started_at, jsonb_build_object(
        'id', c.id,
        'started_at', c.started_at,
        'finished_at', c.finished_at,
        'started_by', sm.name,
        'finished_by', fm.name,
        'period_from', pr.finished_at,
        'lines', coalesce((
          select jsonb_agg(jsonb_build_object(
            'item_id', l.item_id, 'name', i.name, 'unit', l.unit, 'capacity', l.capacity,
            'location', i.location, 'pack_name', i.pack_name,
            'quantity', l.quantity, 'packages', l.packages, 'loose', l.loose, 'counted_by', cm.name,
            'container', l.container_name, 'tare', l.tare, 'gross', l.gross,
            'previous', case when p.updated_at is null then null else p.total end,
            'used', case when p.updated_at is null then null else u.sold end,
            'delivered', case when p.updated_at is null then null else u.delivered end,
            'removed', case when p.updated_at is null then null else u.removed end,
            'expected', case when p.updated_at is null then null else p.total + u.net end
          ) order by coalesce(i.location, ''), i.sort, lower(i.name))
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
            select coalesce(sum(-m.amount) filter (where m.kind = 'sale'), 0) * private.inventory_factor(i.unit, l.unit) as sold,
                   coalesce(sum(m.amount) filter (where m.kind = 'delivery'), 0) * private.inventory_factor(i.unit, l.unit) as delivered,
                   coalesce(sum(-m.amount) filter (where m.kind = 'removal'), 0) * private.inventory_factor(i.unit, l.unit) as removed,
                   coalesce(sum(m.amount), 0) * private.inventory_factor(i.unit, l.unit) as net
            from inventory_movements m
            where m.item_id = l.item_id and m.created_at > p.updated_at and m.created_at <= l.updated_at
          ) u on true
          where l.count_id = c.id
        ), '[]'::jsonb),
        'docs', coalesce((
          select jsonb_agg(private.inventory_doc_json(d.id) order by d.happened_at)
          from inventory_docs d
          where d.restaurant_id = c.restaurant_id
            and d.happened_at > coalesce(pr.finished_at, date_trunc('day', c.started_at))
            and d.happened_at <= coalesce(c.finished_at, now())
        ), '[]'::jsonb)
      ) as j
      from inventory_counts c
      left join staff_members sm on sm.id = c.started_by_member
      left join staff_members fm on fm.id = c.finished_by_member
      left join lateral (
        select pc.finished_at from inventory_counts pc
        where pc.restaurant_id = c.restaurant_id and pc.finished_at is not null and pc.id <> c.id
          and pc.finished_at < coalesce(c.finished_at, now())
        order by pc.finished_at desc limit 1
      ) pr on true
      where c.restaurant_id = p_restaurant_id
      order by c.started_at desc
      limit greatest(1, least(coalesce(p_limit, 20), 100))
    ) x
  );
end;
$$;

-- ---------------------------------------------------------------
-- Dostawy i usunięcia: zapis, lista, usuwanie
-- ---------------------------------------------------------------

create or replace function private.inventory_doc_json(p_doc_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', d.id, 'kind', d.kind, 'happened_at', d.happened_at, 'reason', d.reason,
    'supplier', d.supplier, 'document_no', d.document_no, 'note', d.note,
    'created_by', m.name, 'created_at', d.created_at,
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
        'item_id', l.item_id, 'name', i.name, 'unit', l.unit, 'capacity', l.capacity, 'pack_name', i.pack_name,
        'packages', l.packages, 'loose', l.loose, 'amount', l.amount
      ) order by lower(i.name))
      from public.inventory_doc_lines l join public.inventory_items i on i.id = l.item_id
      where l.doc_id = d.id
    ), '[]'::jsonb)
  )
  from public.inventory_docs d
  left join public.staff_members m on m.id = d.created_by_member
  where d.id = p_doc_id
$$;

create or replace function public.panel_inventory_save_doc(
  p_restaurant_id uuid,
  p_kind text,
  p_lines jsonb,
  p_happened_at timestamptz default null,
  p_reason text default null,
  p_supplier text default null,
  p_document_no text default null,
  p_note text default null,
  p_member_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_id     uuid;
  v_at     timestamptz := coalesce(p_happened_at, now());
  v_line   jsonb;
  v_item   inventory_items%rowtype;
  v_pk     numeric;
  v_lo     numeric;
  v_amount numeric;
begin
  perform private.inventory_allowed(p_restaurant_id, p_member_id, 'inventory_count');
  perform private.check_inventory_member(p_restaurant_id, p_member_id);
  if p_kind not in ('delivery', 'removal') then
    raise exception 'Wybierz dostawę albo usunięcie.';
  end if;
  if v_at > now() + interval '5 minutes' then
    raise exception 'Data nie może być z przyszłości.';
  end if;
  if v_at < now() - interval '60 days' then
    raise exception 'Można wpisać najwyżej 60 dni wstecz.';
  end if;
  if p_kind = 'removal' then
    if p_reason is null or p_reason not in ('transfer', 'return', 'loss', 'staff', 'other') then
      raise exception 'Wybierz powód usunięcia.';
    end if;
    if nullif(btrim(p_note), '') is null then
      raise exception 'Wpisz wyjaśnienie: dlaczego i dokąd składniki zniknęły z lokalu.';
    end if;
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Dodaj co najmniej jeden składnik.';
  end if;
  if jsonb_array_length(p_lines) > 200 then
    raise exception 'Najwyżej 200 składników naraz.';
  end if;

  insert into inventory_docs (restaurant_id, kind, happened_at, reason, supplier, document_no, note, created_by_member)
  values (
    p_restaurant_id, p_kind, v_at,
    case when p_kind = 'removal' then p_reason end,
    case when p_kind = 'delivery' then left(nullif(btrim(p_supplier), ''), 120) end,
    case when p_kind = 'delivery' then left(nullif(btrim(p_document_no), ''), 60) end,
    left(nullif(btrim(p_note), ''), 500),
    p_member_id
  )
  returning id into v_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    select * into v_item from inventory_items
    where id = (v_line ->> 'item_id')::uuid and restaurant_id = p_restaurant_id and deleted_at is null;
    if not found then
      raise exception 'Nie znaleziono składnika.';
    end if;
    v_pk := nullif(v_line ->> 'packages', '')::numeric;
    v_lo := nullif(v_line ->> 'loose', '')::numeric;
    if coalesce(v_pk, 0) < 0 or coalesce(v_lo, 0) < 0 or coalesce(v_pk, 0) > 1000000 or coalesce(v_lo, 0) > 100000000 then
      raise exception 'Ilość od 0 (%).', v_item.name;
    end if;
    v_amount := private.inventory_amount(v_item.unit, v_item.capacity, v_pk, v_lo);
    if v_amount is null or v_amount <= 0 then
      raise exception 'Wpisz ilość: %.', v_item.name;
    end if;
    if exists (select 1 from inventory_doc_lines where doc_id = v_id and item_id = v_item.id) then
      raise exception '„%” jest na liście dwa razy.', v_item.name;
    end if;
    insert into inventory_doc_lines (doc_id, item_id, packages, loose, amount, unit, capacity)
    values (v_id, v_item.id, v_pk, v_lo, round(v_amount, 6), v_item.unit, v_item.capacity);
    insert into inventory_movements (restaurant_id, item_id, amount, kind, doc_id, created_at)
    values (
      p_restaurant_id, v_item.id,
      case when p_kind = 'delivery' then round(v_amount, 6) else -round(v_amount, 6) end,
      p_kind, v_id, v_at
    );
  end loop;
  return v_id;
end;
$$;

create or replace function public.panel_inventory_docs(
  p_restaurant_id uuid,
  p_from timestamptz,
  p_to timestamptz default null,
  p_member_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  begin
    perform private.inventory_allowed(p_restaurant_id, p_member_id, 'inventory_count');
  exception when others then
    perform private.inventory_allowed(p_restaurant_id, p_member_id, 'inventory_edit');
  end;
  return coalesce((
    select jsonb_agg(private.inventory_doc_json(d.id) order by d.happened_at desc)
    from inventory_docs d
    where d.restaurant_id = p_restaurant_id
      and d.happened_at >= p_from
      and (p_to is null or d.happened_at <= p_to)
  ), '[]'::jsonb);
end;
$$;

-- Usunięcie wpisu dostawy albo usunięcia (pomyłka). Ruchy znikają razem z nim.
create or replace function public.panel_inventory_delete_doc(p_doc_id uuid, p_member_id uuid default null)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_restaurant uuid;
begin
  select restaurant_id into v_restaurant from inventory_docs where id = p_doc_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono wpisu.';
  end if;
  perform private.inventory_allowed(v_restaurant, p_member_id, 'inventory_edit');
  delete from inventory_docs where id = p_doc_id;
end;
$$;

-- ---------------------------------------------------------------
-- Pojemniki: zapis i usuwanie (uprawnienie „Edytowanie składników”)
-- ---------------------------------------------------------------

create or replace function public.panel_save_inventory_container(
  p_restaurant_id uuid,
  p_id uuid,
  p_name text,
  p_tare_g numeric
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_id uuid := p_id;
begin
  perform private.require_permission(p_restaurant_id, 'inventory_edit');
  if nullif(btrim(p_name), '') is null then
    raise exception 'Wpisz nazwę pojemnika.';
  end if;
  if p_tare_g is null or p_tare_g < 0 or p_tare_g > 100000 then
    raise exception 'Wpisz wagę pojemnika w gramach.';
  end if;
  if v_id is null then
    insert into inventory_containers (restaurant_id, name, tare_g, sort)
    values (
      p_restaurant_id, left(btrim(p_name), 40), p_tare_g,
      coalesce((select max(sort) + 1 from inventory_containers where restaurant_id = p_restaurant_id), 0)
    )
    returning id into v_id;
  else
    update inventory_containers set name = left(btrim(p_name), 40), tare_g = p_tare_g
    where id = v_id and restaurant_id = p_restaurant_id;
    if not found then
      raise exception 'Nie znaleziono pojemnika.';
    end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.panel_delete_inventory_container(p_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_restaurant uuid;
begin
  select restaurant_id into v_restaurant from inventory_containers where id = p_id;
  if v_restaurant is null then
    raise exception 'Nie znaleziono pojemnika.';
  end if;
  perform private.require_permission(v_restaurant, 'inventory_edit');
  delete from inventory_containers where id = p_id;
end;
$$;

-- ---------------------------------------------------------------
-- Table for employees: wszystko do spisu na telefonie jednym zapytaniem
-- ---------------------------------------------------------------

create or replace function public.staff_inventory(p_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_member staff_members%rowtype;
  v_count  inventory_counts%rowtype;
begin
  v_member := private.my_member(p_member_id);
  perform private.inventory_allowed(v_member.restaurant_id, p_member_id, 'inventory_count');
  select * into v_count from inventory_counts where restaurant_id = v_member.restaurant_id and finished_at is null;

  return jsonb_build_object(
    'count_id', v_count.id,
    'started_at', v_count.started_at,
    'containers', coalesce((
      select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'tare_g', b.tare_g) order by b.sort, b.name)
      from inventory_containers b where b.restaurant_id = v_member.restaurant_id
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'name', i.name, 'unit', i.unit, 'capacity', i.capacity, 'location', i.location,
        'pack_name', i.pack_name, 'container_id', i.container_id, 'expected', s.stock,
        'line', case when l.item_id is null then null else jsonb_build_object(
          'quantity', l.quantity, 'packages', l.packages, 'loose', l.loose, 'gross', l.gross,
          'container_id', l.container_id
        ) end
      ) order by coalesce(i.location, ''), i.sort, lower(i.name))
      from inventory_items i
      left join public.panel_inventory_stock(v_member.restaurant_id, p_member_id) s on s.item_id = i.id
      left join inventory_count_lines l on l.count_id = v_count.id and l.item_id = i.id
      where i.restaurant_id = v_member.restaurant_id and i.deleted_at is null
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.panel_inventory_save_doc(uuid, text, jsonb, timestamptz, text, text, text, text, uuid) from public, anon;
revoke all on function public.panel_inventory_docs(uuid, timestamptz, timestamptz, uuid) from public, anon;
revoke all on function public.panel_inventory_delete_doc(uuid, uuid) from public, anon;
revoke all on function public.panel_save_inventory_container(uuid, uuid, text, numeric) from public, anon;
revoke all on function public.panel_delete_inventory_container(uuid) from public, anon;
revoke all on function public.staff_inventory(uuid) from public, anon;
revoke all on function public.panel_inventory_set(uuid, uuid, numeric, uuid, numeric, uuid) from public, anon;
revoke all on function public.panel_inventory_stock(uuid, uuid) from public, anon;
revoke all on function public.panel_inventory_counts(uuid, integer, uuid) from public, anon;
grant execute on function public.panel_inventory_save_doc(uuid, text, jsonb, timestamptz, text, text, text, text, uuid) to authenticated;
grant execute on function public.panel_inventory_docs(uuid, timestamptz, timestamptz, uuid) to authenticated;
grant execute on function public.panel_inventory_delete_doc(uuid, uuid) to authenticated;
grant execute on function public.panel_save_inventory_container(uuid, uuid, text, numeric) to authenticated;
grant execute on function public.panel_delete_inventory_container(uuid) to authenticated;
grant execute on function public.staff_inventory(uuid) to authenticated;
grant execute on function public.panel_inventory_set(uuid, uuid, numeric, uuid, numeric, uuid) to authenticated;
grant execute on function public.panel_inventory_stock(uuid, uuid) to authenticated;
grant execute on function public.panel_inventory_counts(uuid, integer, uuid) to authenticated;
