-- Table · migracja 0021
-- 1. Menu: warianty (np. rozmiary), dodatki, stawka VAT i „chwilowo niedostępne”.
-- 2. Konta pracowników: pracownik z listy może dostać konto w panelu, a jego stanowisko
--    decyduje o uprawnieniach (np. Kelner widzi zamówienia).
-- 3. Zamówienia przy stoliku: kelner nabija pozycje z menu, wysyła je na kuchnię i zamyka rachunek.

-- ---------------------------------------------------------------
-- 1. Menu
-- ---------------------------------------------------------------

-- Lista opcji: [{"name": "Duża", "price_grosze": 4500}, ...].
create or replace function private.valid_menu_options(p jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when jsonb_typeof(p) is distinct from 'array' then false
    when jsonb_array_length(p) > 20 then false
    else not exists (
      select 1
      from jsonb_array_elements(p) e
      where jsonb_typeof(e) <> 'object'
         or coalesce(btrim(e ->> 'name'), '') = ''
         or char_length(e ->> 'name') > 40
         or coalesce(e ->> 'price_grosze', '') !~ '^[0-9]{1,7}$'
    )
  end
$$;

revoke execute on function private.valid_menu_options(jsonb) from public, anon;
grant execute on function private.valid_menu_options(jsonb) to authenticated, service_role;

alter table public.menu_items
  add column variants   jsonb not null default '[]' check (private.valid_menu_options(variants)),
  add column addons     jsonb not null default '[]' check (private.valid_menu_options(addons)),
  add column vat_rate   smallint not null default 8 check (vat_rate in (0, 5, 8, 23)),
  add column available  boolean not null default true;

comment on column public.menu_items.variants is
  'Warianty, np. rozmiary. Gdy lista nie jest pusta, cena pozycji to cena wybranego wariantu.';
comment on column public.menu_items.addons is
  'Płatne dodatki doliczane do ceny pozycji.';

-- ---------------------------------------------------------------
-- 2. Konta pracowników i uprawnienia
-- ---------------------------------------------------------------

alter table public.staff_members
  add column user_id uuid references auth.users (id) on delete set null;

create unique index staff_members_user_idx
  on public.staff_members (restaurant_id, user_id)
  where user_id is not null;

-- Kierownik i właściciel mają wszystkie uprawnienia. Konto obsługi ma uprawnienia
-- stanowiska pracownika, z którym jest połączone.
create or replace function private.has_permission(p_restaurant_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_staff_role(p_restaurant_id, 'manager')
    or (
      private.has_staff_role(p_restaurant_id)
      and exists (
        select 1
        from public.staff_members m
        join public.staff_positions p on p.id = m.position_id
        where m.restaurant_id = p_restaurant_id
          and m.user_id = (select auth.uid())
          and m.active
          and p_permission = any (p.permissions)
      )
    )
$$;

revoke execute on function private.has_permission(uuid, text) from public, anon;
grant execute on function private.has_permission(uuid, text) to authenticated;

create or replace function public.panel_my_permissions(p_restaurant_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when private.has_staff_role(p_restaurant_id, 'manager') then
      array['reservations', 'floor', 'floor_edit', 'menu', 'orders', 'kitchen',
            'deliveries', 'gift_cards', 'reviews', 'stats', 'staff']
    else coalesce((
      select p.permissions
      from public.staff_members m
      join public.staff_positions p on p.id = m.position_id
      where m.restaurant_id = p_restaurant_id
        and m.user_id = (select auth.uid())
        and m.active
      limit 1
    ), '{}')
  end
$$;

-- Łączy pracownika z istniejącym kontem (zakłada je właściciel w Supabase) i daje mu dostęp do panelu.
create or replace function public.panel_link_staff_account(p_member_id uuid, p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
  v_user    uuid;
begin
  select * into v_member from staff_members where id = p_member_id;
  if not found then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_staff(v_member.restaurant_id, 'manager');

  select id into v_user from auth.users where lower(email) = lower(btrim(p_email));
  if v_user is null then
    raise exception 'Nie ma konta z adresem %. Najpierw załóż je w Supabase.', btrim(p_email);
  end if;

  if exists (
    select 1 from staff_members
    where restaurant_id = v_member.restaurant_id and user_id = v_user and id <> p_member_id
  ) then
    raise exception 'To konto jest już połączone z innym pracownikiem.';
  end if;

  insert into restaurant_staff (restaurant_id, user_id, role)
  values (v_member.restaurant_id, v_user, 'staff')
  on conflict do nothing;

  update staff_members set user_id = v_user where id = p_member_id;
end;
$$;

-- Odłącza konto. Konto obsługi traci dostęp do lokalu, kierownik i właściciel go zachowują.
create or replace function public.panel_unlink_staff_account(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member  staff_members%rowtype;
begin
  select * into v_member from staff_members where id = p_member_id;
  if not found then
    raise exception 'Nie znaleziono pracownika.';
  end if;
  perform private.require_staff(v_member.restaurant_id, 'manager');

  update staff_members set user_id = null where id = p_member_id;
  if v_member.user_id is not null then
    delete from restaurant_staff
    where restaurant_id = v_member.restaurant_id and user_id = v_member.user_id and role = 'staff';
  end if;
end;
$$;

-- Adresy e-mail kont połączonych z pracownikami. Tylko dla kierownika i właściciela.
create or replace function public.panel_staff_accounts(p_restaurant_id uuid)
returns table (member_id uuid, email text)
language sql
stable
security definer
set search_path = public
as $$
  select m.id, u.email::text
  from staff_members m
  join auth.users u on u.id = m.user_id
  where m.restaurant_id = p_restaurant_id
    and private.has_staff_role(p_restaurant_id, 'manager')
$$;

-- ---------------------------------------------------------------
-- 3. Zamówienia
-- ---------------------------------------------------------------

create type public.order_status as enum ('open', 'paid', 'cancelled');
create type public.order_item_status as enum ('new', 'sent', 'served', 'cancelled');

create table public.orders (
  id              uuid primary key default gen_random_uuid(),
  restaurant_id   uuid not null references public.restaurants (id) on delete cascade,
  table_id        uuid references public.dining_tables (id) on delete set null,
  reservation_id  uuid references public.reservations (id) on delete set null,
  status          public.order_status not null default 'open',
  note            text check (char_length(note) <= 300),
  payment_method  text check (payment_method in ('cash', 'card', 'gift_card', 'other')),
  opened_by       uuid references auth.users (id) on delete set null,
  opened_at       timestamptz not null default now(),
  closed_by       uuid references auth.users (id) on delete set null,
  closed_at       timestamptz
);

-- Przy stoliku jest najwyżej jeden otwarty rachunek.
create unique index orders_open_table_idx on public.orders (table_id) where status = 'open';
create index orders_restaurant_idx on public.orders (restaurant_id, opened_at desc);

create table public.order_items (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid not null references public.orders (id) on delete cascade,
  restaurant_id      uuid not null references public.restaurants (id) on delete cascade,
  menu_item_id       uuid references public.menu_items (id) on delete set null,
  name               text not null check (char_length(name) <= 80),
  variant            text check (char_length(variant) <= 40),
  addons             jsonb not null default '[]' check (private.valid_menu_options(addons)),
  unit_price_grosze  integer not null check (unit_price_grosze >= 0),
  vat_rate           smallint not null check (vat_rate in (0, 5, 8, 23)),
  quantity           smallint not null check (quantity between 1 and 99),
  note               text check (char_length(note) <= 200),
  course             smallint not null default 1 check (course between 1 and 5),
  status             public.order_item_status not null default 'new',
  created_by         uuid references auth.users (id) on delete set null,
  created_at         timestamptz not null default now(),
  sent_at            timestamptz
);

create index order_items_order_idx on public.order_items (order_id, created_at);
create index order_items_restaurant_idx on public.order_items (restaurant_id);

alter table public.orders enable row level security;
alter table public.order_items enable row level security;

-- Czytanie dla osób z uprawnieniem do zamówień. Zapis tylko przez funkcje panel_*,
-- bo cenę liczy baza z menu, a nie urządzenie kelnera.
create policy "Obsługa z uprawnieniem widzi zamówienia"
  on public.orders for select to authenticated
  using (private.has_permission(restaurant_id, 'orders'));

create policy "Obsługa z uprawnieniem widzi pozycje zamówień"
  on public.order_items for select to authenticated
  using (private.has_permission(restaurant_id, 'orders'));

alter publication supabase_realtime add table public.orders, public.order_items;

create or replace function private.require_permission(p_restaurant_id uuid, p_permission text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.has_permission(p_restaurant_id, p_permission) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
end;
$$;

revoke execute on function private.require_permission(uuid, text) from public, anon;
grant execute on function private.require_permission(uuid, text) to authenticated;

-- Otwiera rachunek przy stoliku albo zwraca już otwarty. Rezerwacja, która teraz jest przy
-- stoliku albo zaraz przyjdzie, zostaje dopięta, żeby statystyki widziały obrót z rezerwacji.
create or replace function public.panel_open_order(p_restaurant_id uuid, p_table_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_res  uuid;
begin
  perform private.require_permission(p_restaurant_id, 'orders');

  if not exists (select 1 from dining_tables where id = p_table_id and restaurant_id = p_restaurant_id) then
    raise exception 'Nie znaleziono stolika.';
  end if;

  select id into v_id from orders where table_id = p_table_id and status = 'open';
  if found then
    return v_id;
  end if;

  select h.reservation_id into v_res
  from table_holds h
  join reservations r on r.id = h.reservation_id
  where h.table_id = p_table_id
    and h.active
    and r.status in ('seated', 'confirmed')
    and now() between lower(h.slot) - interval '30 minutes' and upper(h.slot)
  order by (r.status = 'seated') desc, lower(h.slot)
  limit 1;

  begin
    insert into orders (restaurant_id, table_id, reservation_id, opened_by)
    values (p_restaurant_id, p_table_id, v_res, auth.uid())
    returning id into v_id;
  exception
    when unique_violation then
      -- Ktoś inny otworzył rachunek w tej samej chwili: bierzemy jego.
      select id into v_id from orders where table_id = p_table_id and status = 'open';
  end;
  return v_id;
end;
$$;

-- Dodaje pozycję z menu. Cenę, nazwę i VAT bierze z menu w chwili nabicia.
create or replace function public.panel_add_order_item(
  p_order_id      uuid,
  p_menu_item_id  uuid,
  p_variant       text default null,
  p_addons        text[] default '{}',
  p_quantity      integer default 1,
  p_note          text default null,
  p_course        integer default 1
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order    orders%rowtype;
  v_item     record;
  v_option   jsonb;
  v_price    integer;
  v_variant  text;
  v_addons   jsonb := '[]';
  v_name     text;
  v_id       uuid;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;

  select i.id, i.name, i.price_grosze, i.variants, i.addons, i.vat_rate, i.available, s.restaurant_id
  into v_item
  from menu_items i
  join menu_sections s on s.id = i.section_id
  where i.id = p_menu_item_id;
  if not found or v_item.restaurant_id <> v_order.restaurant_id then
    raise exception 'Nie znaleziono pozycji w menu.';
  end if;
  if not v_item.available then
    raise exception 'Ta pozycja jest chwilowo niedostępna.';
  end if;
  if p_quantity is null or p_quantity not between 1 and 99 then
    raise exception 'Ilość od 1 do 99.';
  end if;

  if jsonb_array_length(v_item.variants) > 0 then
    select o into v_option from jsonb_array_elements(v_item.variants) o where o ->> 'name' = p_variant;
    if v_option is null then
      raise exception 'Wybierz wariant pozycji „%”.', v_item.name;
    end if;
    v_price := (v_option ->> 'price_grosze')::integer;
    v_variant := v_option ->> 'name';
  else
    v_price := v_item.price_grosze;
  end if;

  foreach v_name in array coalesce(p_addons, '{}') loop
    v_option := null;
    select o into v_option from jsonb_array_elements(v_item.addons) o where o ->> 'name' = v_name;
    if v_option is null then
      raise exception 'Pozycja „%” nie ma dodatku „%”.', v_item.name, v_name;
    end if;
    v_price := v_price + (v_option ->> 'price_grosze')::integer;
    v_addons := v_addons || jsonb_build_array(v_option);
  end loop;

  insert into order_items (
    order_id, restaurant_id, menu_item_id, name, variant, addons,
    unit_price_grosze, vat_rate, quantity, note, course, created_by
  )
  values (
    p_order_id, v_order.restaurant_id, v_item.id, v_item.name, v_variant, v_addons,
    v_price, v_item.vat_rate, p_quantity, nullif(btrim(p_note), ''),
    greatest(1, least(5, coalesce(p_course, 1))), auth.uid()
  )
  returning id into v_id;
  return v_id;
end;
$$;

-- Zmienia ilość, uwagę albo stan pozycji. Anulowanie nowej pozycji usuwa ją z rachunku,
-- a pozycję wysłaną już na kuchnię może anulować tylko kierownik.
create or replace function public.panel_update_order_item(
  p_item_id   uuid,
  p_quantity  integer default null,
  p_note      text default null,
  p_status    public.order_item_status default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item   order_items%rowtype;
  v_open   boolean;
begin
  select * into v_item from order_items where id = p_item_id;
  if not found then
    raise exception 'Nie znaleziono pozycji.';
  end if;
  perform private.require_permission(v_item.restaurant_id, 'orders');
  select status = 'open' into v_open from orders where id = v_item.order_id;
  if not v_open then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;

  if p_status = 'cancelled' then
    if v_item.status = 'new' then
      delete from order_items where id = p_item_id;
      return;
    end if;
    perform private.require_staff(v_item.restaurant_id, 'manager');
  end if;

  if p_quantity is not null then
    if v_item.status <> 'new' then
      raise exception 'Ilość zmienisz tylko przed wysłaniem na kuchnię.';
    end if;
    if p_quantity not between 1 and 99 then
      raise exception 'Ilość od 1 do 99.';
    end if;
  end if;

  update order_items
  set quantity = coalesce(p_quantity, quantity),
      note = case when p_note is null then note else nullif(btrim(p_note), '') end,
      status = coalesce(p_status, status),
      sent_at = case when p_status = 'sent' and sent_at is null then now() else sent_at end
  where id = p_item_id;
end;
$$;

-- Wysyła nowe pozycje na kuchnię. Zwraca ich liczbę.
create or replace function public.panel_send_order(p_order_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
  v_count  integer;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;

  with sent as (
    update order_items set status = 'sent', sent_at = now()
    where order_id = p_order_id and status = 'new'
    returning 1
  )
  select count(*) into v_count from sent;
  return v_count;
end;
$$;

-- Zamyka rachunek. Rezerwacja, której goście siedzą przy stoliku, kończy się razem z nim
-- i stolik od razu wraca jako wolny.
create or replace function public.panel_close_order(p_order_id uuid, p_payment_method text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;
  if p_payment_method not in ('cash', 'card', 'gift_card', 'other') then
    raise exception 'Wybierz formę płatności.';
  end if;
  if not exists (select 1 from order_items where order_id = p_order_id and status <> 'cancelled') then
    raise exception 'Rachunek jest pusty. Anuluj go zamiast zamykać.';
  end if;

  update order_items set status = 'served' where order_id = p_order_id and status in ('new', 'sent');
  update orders
  set status = 'paid', payment_method = p_payment_method, closed_at = now(), closed_by = auth.uid()
  where id = p_order_id;

  if v_order.reservation_id is not null then
    update reservations set status = 'completed', updated_at = now()
    where id = v_order.reservation_id and status = 'seated';
    if found then
      update table_holds
      set slot = tstzrange(lower(slot), greatest(lower(slot), now()) + interval '1 second'),
          active = false
      where reservation_id = v_order.reservation_id;
    end if;
  end if;
end;
$$;

-- Anuluje cały rachunek. Gdy coś poszło już na kuchnię, potrzebny jest kierownik.
create or replace function public.panel_cancel_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;
  if exists (select 1 from order_items where order_id = p_order_id and status in ('sent', 'served')) then
    perform private.require_staff(v_order.restaurant_id, 'manager');
  end if;

  update order_items set status = 'cancelled' where order_id = p_order_id and status <> 'cancelled';
  update orders set status = 'cancelled', closed_at = now(), closed_by = auth.uid() where id = p_order_id;
end;
$$;

-- Przenosi otwarty rachunek na inny wolny stolik.
create or replace function public.panel_move_order(p_order_id uuid, p_table_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id;
  if not found then
    raise exception 'Nie znaleziono rachunku.';
  end if;
  perform private.require_permission(v_order.restaurant_id, 'orders');
  if v_order.status <> 'open' then
    raise exception 'Ten rachunek jest już zamknięty.';
  end if;
  if not exists (select 1 from dining_tables where id = p_table_id and restaurant_id = v_order.restaurant_id) then
    raise exception 'Nie znaleziono stolika.';
  end if;

  begin
    update orders set table_id = p_table_id where id = p_order_id;
  exception
    when unique_violation then
      raise exception 'Przy tym stoliku jest już otwarty rachunek.';
  end;
end;
$$;

revoke execute on function public.panel_my_permissions(uuid) from public, anon;
revoke execute on function public.panel_link_staff_account(uuid, text) from public, anon;
revoke execute on function public.panel_unlink_staff_account(uuid) from public, anon;
revoke execute on function public.panel_staff_accounts(uuid) from public, anon;
revoke execute on function public.panel_open_order(uuid, uuid) from public, anon;
revoke execute on function public.panel_add_order_item(uuid, uuid, text, text[], integer, text, integer) from public, anon;
revoke execute on function public.panel_update_order_item(uuid, integer, text, public.order_item_status) from public, anon;
revoke execute on function public.panel_send_order(uuid) from public, anon;
revoke execute on function public.panel_close_order(uuid, text) from public, anon;
revoke execute on function public.panel_cancel_order(uuid) from public, anon;
revoke execute on function public.panel_move_order(uuid, uuid) from public, anon;

grant execute on function public.panel_my_permissions(uuid) to authenticated;
grant execute on function public.panel_link_staff_account(uuid, text) to authenticated;
grant execute on function public.panel_unlink_staff_account(uuid) to authenticated;
grant execute on function public.panel_staff_accounts(uuid) to authenticated;
grant execute on function public.panel_open_order(uuid, uuid) to authenticated;
grant execute on function public.panel_add_order_item(uuid, uuid, text, text[], integer, text, integer) to authenticated;
grant execute on function public.panel_update_order_item(uuid, integer, text, public.order_item_status) to authenticated;
grant execute on function public.panel_send_order(uuid) to authenticated;
grant execute on function public.panel_close_order(uuid, text) to authenticated;
grant execute on function public.panel_cancel_order(uuid) to authenticated;
grant execute on function public.panel_move_order(uuid, uuid) to authenticated;
