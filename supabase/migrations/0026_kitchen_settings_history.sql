-- Table · migracja 0026
-- 1. Kuchnia zbija danie do stanu „do wydania” (ready), kelner oznacza je jako wydane.
--    Cofnięte przez kuchnię danie jest oznaczone (recalled_at), żeby kuchnia widziała je innym kolorem.
-- 2. Ustawienia kuchni: progi czasu (żółty i czerwony) i pozycje menu, których kuchnia nie widzi
--    (np. napoje, które nalewa kelner: od razu są „do wydania”).
-- 3. Średni czas przygotowania zamówienia na pasek kuchni.
-- 4. Płatność kartą podarunkową przy zamykaniu rachunku, także częściowa.

-- ---------------------------------------------------------------
-- Kolumny
-- ---------------------------------------------------------------

alter table public.order_items
  add column ready_at    timestamptz,
  add column recalled_at timestamptz;

alter table public.menu_items
  add column show_in_kitchen boolean not null default true;

alter table public.restaurants
  add column kitchen_warn_minutes smallint not null default 4 check (kitchen_warn_minutes between 1 and 120),
  add column kitchen_late_minutes smallint not null default 6 check (kitchen_late_minutes between 1 and 180),
  add constraint restaurants_kitchen_thresholds check (kitchen_late_minutes > kitchen_warn_minutes);

alter table public.orders
  add column gift_card_id     uuid references public.gift_cards (id) on delete set null,
  add column gift_card_grosze integer check (gift_card_grosze > 0);

create index order_items_ready_idx on public.order_items (restaurant_id, sent_at) where ready_at is not null;

-- ---------------------------------------------------------------
-- Wysyłka na kuchnię i zbijanie
-- ---------------------------------------------------------------

-- Wysyła nowe pozycje na kuchnię. Pozycje ukryte przed kuchnią od razu czekają na kelnera.
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
    update order_items i
    set status = case
          when coalesce((select m.show_in_kitchen from menu_items m where m.id = i.menu_item_id), true)
            then 'sent'::order_item_status
          else 'ready'::order_item_status
        end,
        sent_at = now()
    where i.order_id = p_order_id
      and i.status = 'new'
    returning 1
  )
  select count(*) into v_count from sent;
  return v_count;
end;
$$;

-- Kuchnia zbija pozycje (sent → ready) albo je cofa (ready → sent, oznaczone jako cofnięte).
create or replace function public.panel_kitchen_set(p_item_ids uuid[], p_done boolean)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant  uuid;
  v_count       integer;
begin
  for v_restaurant in
    select distinct restaurant_id from order_items where id = any (p_item_ids)
  loop
    if not (
      private.has_permission(v_restaurant, 'kitchen')
      or private.has_permission(v_restaurant, 'orders')
    ) then
      raise exception 'Nie masz uprawnień do tej części panelu.';
    end if;
  end loop;

  with changed as (
    update order_items i
    set status = case when p_done then 'ready'::order_item_status else 'sent'::order_item_status end,
        ready_at = case when p_done then now() else null end,
        recalled_at = case when p_done then null else now() end
    from orders o
    where o.id = i.order_id
      and o.status = 'open'
      and i.id = any (p_item_ids)
      and i.status = case when p_done then 'sent'::order_item_status else 'ready'::order_item_status end
    returning 1
  )
  select count(*) into v_count from changed;
  return v_count;
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
  if exists (
    select 1 from order_items where order_id = p_order_id and status in ('sent', 'ready', 'served')
  ) then
    perform private.require_staff(v_order.restaurant_id, 'manager');
  end if;

  update order_items set status = 'cancelled' where order_id = p_order_id and status <> 'cancelled';
  update orders set status = 'cancelled', closed_at = now(), closed_by = auth.uid() where id = p_order_id;
end;
$$;

-- ---------------------------------------------------------------
-- Zamknięcie rachunku, także kartą podarunkową
-- ---------------------------------------------------------------

drop function public.panel_close_order(uuid, text);

-- Zamyka rachunek. Przy karcie podarunkowej pobiera z niej p_gift_amount. Gdy karta nie pokrywa całości,
-- p_payment_method mówi, jak gość dopłacił resztę. Wszystko w jednej transakcji: albo przejdzie całość, albo nic.
create or replace function public.panel_close_order(
  p_order_id        uuid,
  p_payment_method  text,
  p_gift_card_id    uuid default null,
  p_gift_amount     integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
  v_total  integer;
begin
  select * into v_order from orders where id = p_order_id for update;
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

  select coalesce(sum(unit_price_grosze * quantity), 0) into v_total
  from order_items where order_id = p_order_id and status <> 'cancelled';
  if v_total = 0 then
    raise exception 'Rachunek jest pusty. Anuluj go zamiast zamykać.';
  end if;

  if p_gift_card_id is not null then
    if not exists (
      select 1 from gift_cards where id = p_gift_card_id and restaurant_id = v_order.restaurant_id
    ) then
      raise exception 'Ta karta podarunkowa jest z innego lokalu.';
    end if;
    if p_gift_amount is null or p_gift_amount <= 0 or p_gift_amount > v_total then
      raise exception 'Kwota z karty musi być większa od zera i nie większa niż rachunek.';
    end if;
    if p_gift_amount < v_total and p_payment_method = 'gift_card' then
      raise exception 'Karta nie pokrywa całego rachunku. Wybierz, jak gość dopłaci resztę.';
    end if;
    -- Sprawdza ważność i saldo karty, pobiera kwotę i zapisuje to w historii karty.
    perform panel_redeem_gift_card(p_gift_card_id, p_gift_amount);
  elsif p_payment_method = 'gift_card' then
    raise exception 'Wpisz kod karty podarunkowej.';
  end if;

  update order_items set status = 'served' where order_id = p_order_id and status in ('new', 'sent', 'ready');
  update orders
  set status = 'paid',
      payment_method = p_payment_method,
      gift_card_id = p_gift_card_id,
      gift_card_grosze = case when p_gift_card_id is null then null else p_gift_amount end,
      closed_at = now(),
      closed_by = auth.uid()
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

-- ---------------------------------------------------------------
-- Ustawienia i statystyki kuchni
-- ---------------------------------------------------------------

-- Progi czasu i pozycje ukryte przed kuchnią. Zmienia kierownik albo stanowisko z uprawnieniem „Kuchnia”.
create or replace function public.panel_set_kitchen_config(
  p_restaurant_id  uuid,
  p_warn_minutes   integer,
  p_late_minutes   integer,
  p_hidden_items   uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (
    private.has_staff_role(p_restaurant_id, 'manager')
    or private.has_permission(p_restaurant_id, 'kitchen')
  ) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
  if p_warn_minutes is null or p_late_minutes is null or p_late_minutes <= p_warn_minutes then
    raise exception 'Czas „czerwony” musi być dłuższy niż „żółty”.';
  end if;

  update restaurants
  set kitchen_warn_minutes = p_warn_minutes, kitchen_late_minutes = p_late_minutes
  where id = p_restaurant_id;

  update menu_items i
  set show_in_kitchen = not (i.id = any (coalesce(p_hidden_items, '{}')))
  from menu_sections s
  where s.id = i.section_id and s.restaurant_id = p_restaurant_id;
end;
$$;

-- Średni czas od wysłania na kuchnię do zbicia całego bilecika: dziś i w ostatniej godzinie.
create or replace function public.panel_kitchen_stats(p_restaurant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with allowed as (
    select private.has_permission(p_restaurant_id, 'kitchen')
        or private.has_permission(p_restaurant_id, 'orders') as ok
  ),
  day_start as (
    select (date_trunc('day', now() at time zone coalesce(r.timezone, 'Europe/Warsaw'))
            at time zone coalesce(r.timezone, 'Europe/Warsaw')) as t
    from restaurants r where r.id = p_restaurant_id
  ),
  tickets as (
    select i.order_id, i.sent_at, max(i.ready_at) as done_at
    from order_items i, day_start d
    where i.restaurant_id = p_restaurant_id
      and i.sent_at >= d.t
      and i.ready_at is not null
      -- Bilecik liczy się dopiero, gdy kuchnia zbiła z niego wszystko.
      and not exists (
        select 1 from order_items y
        where y.order_id = i.order_id and y.sent_at = i.sent_at and y.status = 'sent'
      )
    group by i.order_id, i.sent_at
  )
  select case when (select ok from allowed) then jsonb_build_object(
    'today_seconds', (select round(avg(extract(epoch from done_at - sent_at))) from tickets),
    'today_count', (select count(*) from tickets),
    'hour_seconds', (select round(avg(extract(epoch from done_at - sent_at))) from tickets
                     where done_at >= now() - interval '1 hour'),
    'hour_count', (select count(*) from tickets where done_at >= now() - interval '1 hour')
  ) else null end
$$;

revoke execute on function public.panel_close_order(uuid, text, uuid, integer) from public, anon;
revoke execute on function public.panel_set_kitchen_config(uuid, integer, integer, uuid[]) from public, anon;
revoke execute on function public.panel_kitchen_stats(uuid) from public, anon;
grant execute on function public.panel_close_order(uuid, text, uuid, integer) to authenticated;
grant execute on function public.panel_set_kitchen_config(uuid, integer, integer, uuid[]) to authenticated;
grant execute on function public.panel_kitchen_stats(uuid) to authenticated;
