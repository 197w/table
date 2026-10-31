-- Logi i Time Machine (10.2026). Zdarzenia dnia i stan lokalu w dowolnej chwili liczą się z chwil zapisanych
-- przy zamówieniach, pozycjach, płatnościach, dostawach, rezerwacjach, zmianach i inwentaryzacji, więc działają
-- też wstecz. Brakowało tylko chwili anulowania pozycji (`order_items.cancelled_at`, od teraz).
-- Uprawnienie `activity` („Logi i Time Machine”).

alter table public.order_items add column if not exists cancelled_at timestamptz;

create or replace function private.order_item_cancelled_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    new.cancelled_at := coalesce(new.cancelled_at, now());
  elsif new.status <> 'cancelled' then
    new.cancelled_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists order_items_cancelled_at on public.order_items;
create trigger order_items_cancelled_at
  before update of status on public.order_items
  for each row execute function private.order_item_cancelled_at();

-- Nazwa stolika albo zamówienia na wynos do zdarzeń.
create or replace function private.order_label(p_order public.orders)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_order.kind = 'dine_in' then
      coalesce((select case when t.kind = 'seat' then 'Miejsce ' else 'Stolik ' end || t.label
                from public.dining_tables t where t.id = p_order.table_id), 'Bez stolika')
    else '#' || coalesce(p_order.number::text, '?') || case when p_order.kind = 'delivery' then ' dostawa' else ' odbiór' end
  end
$$;

-- „1× A␟2× B␟1× A” → „2× A, 2× B” (to samo danie w jednym zdarzeniu raz, z sumą sztuk).
create or replace function private.merge_item_names(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select string_agg(s.q || '× ' || s.n, ', ' order by s.first)
  from (
    select substr(x, strpos(x, '× ') + 2) as n, sum(split_part(x, '× ', 1)::int) as q, min(ord) as first
    from unnest(string_to_array(p, chr(31))) with ordinality as t(x, ord)
    group by 1
  ) s
$$;

-- Zdarzenia z dnia (albo innego przedziału), od najstarszych. Każde: chwila, rodzaj, stolik albo numer zamówienia,
-- osoba, liczba sztuk, kwota, pozycje.
create or replace function public.panel_activity(
  p_restaurant_id uuid,
  p_from timestamptz,
  p_to timestamptz,
  p_member_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- Panel: konto albo zalogowany pracownik; Table for employees: własny pracownik z uprawnieniem.
  perform private.inventory_allowed(p_restaurant_id, p_member_id, 'activity');
  if p_to - p_from > interval '3 days' then
    raise exception 'Najwyżej 3 dni naraz.';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(e) order by e.at, e.kind)
    from (
      -- Zmiany pracowników
      select s.started_at as at, 'shift_start' as kind, null::text as label, m.name as member,
             null::int as count, null::int as amount, null::int as tip, null::text as method, null::text as names,
             null::uuid as order_id
      from public.staff_shifts s join public.staff_members m on m.id = s.member_id
      where s.restaurant_id = p_restaurant_id and s.started_at >= p_from and s.started_at < p_to
      union all
      select s.ended_at, 'shift_end', null, m.name, null, null, null, null, null, null
      from public.staff_shifts s join public.staff_members m on m.id = s.member_id
      where s.restaurant_id = p_restaurant_id and s.ended_at >= p_from and s.ended_at < p_to
      -- Rachunki na sali
      union all
      select o.opened_at, 'order_open', private.order_label(o), m.name, o.guests, null, null, null, null, o.id
      from public.orders o left join public.staff_members m on m.id = o.opened_by_member
      where o.restaurant_id = p_restaurant_id and o.kind = 'dine_in' and o.opened_at >= p_from and o.opened_at < p_to
      union all
      select o.closed_at, 'order_close', private.order_label(o), m.name, null,
             (select coalesce(sum(p.amount_grosze), 0)::int from public.order_payments p where p.order_id = o.id),
             null, null, null, o.id
      from public.orders o left join public.staff_members m on m.id = o.closed_by_member
      where o.restaurant_id = p_restaurant_id and o.kind = 'dine_in' and o.closed_at >= p_from and o.closed_at < p_to
      -- Zamówienia na wynos
      union all
      select o.opened_at, case when o.guest_id is null then 'takeaway_new' else 'takeaway_app' end,
             private.order_label(o), m.name, null,
             (select coalesce(sum(i.unit_price_grosze * i.quantity), 0)::int from public.order_items i
              where i.order_id = o.id and i.status <> 'cancelled') + o.delivery_fee_grosze,
             null, null, o.customer_name, o.id
      from public.orders o left join public.staff_members m on m.id = o.opened_by_member
      where o.restaurant_id = p_restaurant_id and o.kind <> 'dine_in' and o.fulfillment <> 'draft'
        and o.opened_at >= p_from and o.opened_at < p_to
      union all
      select o.accepted_at, 'takeaway_accepted', private.order_label(o), null, null, null, null, null, null, o.id
      from public.orders o
      where o.restaurant_id = p_restaurant_id and o.kind <> 'dine_in' and o.accepted_at >= p_from and o.accepted_at < p_to
      union all
      select o.ready_at, 'takeaway_ready', private.order_label(o), null, null, null, null, null, null, o.id
      from public.orders o
      where o.restaurant_id = p_restaurant_id and o.kind <> 'dine_in' and o.ready_at >= p_from and o.ready_at < p_to
      union all
      select o.picked_up_at, 'takeaway_picked', private.order_label(o), m.name, null, null, null, null, null, o.id
      from public.orders o left join public.staff_members m on m.id = o.courier_member
      where o.restaurant_id = p_restaurant_id and o.kind <> 'dine_in' and o.picked_up_at >= p_from and o.picked_up_at < p_to
      union all
      select o.delivered_at, 'takeaway_done', private.order_label(o), m.name, null, null, null, null, null, o.id
      from public.orders o left join public.staff_members m on m.id = o.courier_member
      where o.restaurant_id = p_restaurant_id and o.kind <> 'dine_in' and o.delivered_at >= p_from and o.delivered_at < p_to
      -- Pozycje: dodane, na kuchnię, gotowe, wydane, anulowane (pogrupowane po zamówieniu i minucie)
      union all
      select min(i.created_at), 'items_added', private.order_label(o), m.name, sum(i.quantity)::int,
             sum(i.unit_price_grosze * i.quantity)::int, null, null,
             private.merge_item_names(string_agg(i.quantity || '× ' || i.name, chr(31) order by i.created_at)), o.id
      from public.order_items i join public.orders o on o.id = i.order_id
      left join public.staff_members m on m.id = i.created_by_member
      where i.restaurant_id = p_restaurant_id and i.created_at >= p_from and i.created_at < p_to
        and (o.kind = 'dine_in' or o.guest_id is null)
      group by o.id, m.name, date_trunc('minute', i.created_at)
      union all
      select min(i.sent_at), 'items_sent', private.order_label(o), null, sum(i.quantity)::int, null, null, null,
             private.merge_item_names(string_agg(i.quantity || '× ' || i.name, chr(31) order by i.created_at)), o.id
      from public.order_items i join public.orders o on o.id = i.order_id
      where i.restaurant_id = p_restaurant_id and i.sent_at >= p_from and i.sent_at < p_to
      group by o.id, date_trunc('minute', i.sent_at)
      union all
      select min(i.ready_at), 'items_ready', private.order_label(o), null, sum(i.quantity)::int, null, null, null,
             private.merge_item_names(string_agg(i.quantity || '× ' || i.name, chr(31) order by i.created_at)), o.id
      from public.order_items i join public.orders o on o.id = i.order_id
      where i.restaurant_id = p_restaurant_id and i.ready_at >= p_from and i.ready_at < p_to
      group by o.id, date_trunc('minute', i.ready_at)
      union all
      select min(i.served_at), 'items_served', private.order_label(o), null, sum(i.quantity)::int, null, null, null,
             private.merge_item_names(string_agg(i.quantity || '× ' || i.name, chr(31) order by i.created_at)), o.id
      from public.order_items i join public.orders o on o.id = i.order_id
      where i.restaurant_id = p_restaurant_id and i.served_at >= p_from and i.served_at < p_to
      group by o.id, date_trunc('minute', i.served_at)
      union all
      select min(i.cancelled_at), 'items_cancelled', private.order_label(o), null, sum(i.quantity)::int,
             sum(i.unit_price_grosze * i.quantity)::int, null, null,
             private.merge_item_names(string_agg(i.quantity || '× ' || i.name, chr(31) order by i.created_at)), o.id
      from public.order_items i join public.orders o on o.id = i.order_id
      where i.restaurant_id = p_restaurant_id and i.cancelled_at >= p_from and i.cancelled_at < p_to
      group by o.id, date_trunc('minute', i.cancelled_at)
      -- Płatności
      union all
      select p.created_at, 'payment', private.order_label(o), m.name, null, p.amount_grosze, p.tip_grosze, p.method,
             null, o.id
      from public.order_payments p join public.orders o on o.id = p.order_id
      left join public.staff_members m on m.id = p.member_id
      where p.restaurant_id = p_restaurant_id and p.created_at >= p_from and p.created_at < p_to
      -- Rezerwacje
      union all
      select r.created_at, case when r.source = 'app' then 'reservation_app' else 'reservation_new' end,
             null, null, r.party_size::int, null, null, to_char(r.starts_at at time zone rs.timezone, 'HH24:MI'),
             coalesce(r.guest_name, 'Gość'), null
      from public.reservations r join public.restaurants rs on rs.id = r.restaurant_id
      where r.restaurant_id = p_restaurant_id and r.source <> 'block' and r.created_at >= p_from and r.created_at < p_to
      union all
      select r.seated_at, 'reservation_seated', null, null, r.party_size::int, null, null, null,
             coalesce(r.guest_name, 'Gość'), null
      from public.reservations r
      where r.restaurant_id = p_restaurant_id and r.seated_at >= p_from and r.seated_at < p_to
      -- Inwentaryzacja
      union all
      select d.happened_at, case when d.kind = 'delivery' then 'stock_delivery' else 'stock_removal' end,
             null, m.name, (select count(*)::int from public.inventory_doc_lines l where l.doc_id = d.id), null, null,
             null, coalesce(d.supplier, d.note), null
      from public.inventory_docs d left join public.staff_members m on m.id = d.created_by_member
      where d.restaurant_id = p_restaurant_id and d.happened_at >= p_from and d.happened_at < p_to
      union all
      select c.finished_at, 'stock_count', null, m.name, (select count(*)::int from public.inventory_count_lines l
             where l.count_id = c.id), null, null, null, null, null
      from public.inventory_counts c left join public.staff_members m on m.id = c.finished_by_member
      where c.restaurant_id = p_restaurant_id and c.finished_at >= p_from and c.finished_at < p_to
    ) e
    where e.at is not null
  ), '[]'::jsonb);
end;
$$;

-- Stan lokalu w chwili [p_at]: otwarte rachunki przy stolikach (pozycje ze stanem z tamtej chwili, wpłacone),
-- rezerwacje przy stolikach, zamówienia na wynos z etapem i osoby na zmianie.
create or replace function public.panel_time_machine(p_restaurant_id uuid, p_at timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_permission(p_restaurant_id, 'activity');
  return jsonb_build_object(
    'at', p_at,
    'bills', coalesce((
      select jsonb_agg(jsonb_build_object(
        'order_id', o.id,
        'table_id', o.table_id,
        'label', private.order_label(o),
        'opened_at', o.opened_at,
        'opened_by', m.name,
        'guests', o.guests,
        'paid', (select coalesce(sum(p.amount_grosze), 0) from public.order_payments p
                 where p.order_id = o.id and p.created_at <= p_at),
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'name', i.name, 'variant', i.variant, 'quantity', i.quantity, 'price', i.unit_price_grosze,
            'status', case
              when i.cancelled_at <= p_at or (i.status = 'cancelled' and i.cancelled_at is null) then 'cancelled'
              when i.served_at <= p_at then 'served'
              when i.ready_at <= p_at then 'ready'
              when i.sent_at <= p_at then 'sent'
              else 'new'
            end
          ) order by i.created_at)
          from public.order_items i
          where i.order_id = o.id and i.created_at <= p_at
        ), '[]'::jsonb)
      ) order by o.opened_at)
      from public.orders o
      left join public.staff_members m on m.id = o.opened_by_member
      where o.restaurant_id = p_restaurant_id and o.kind = 'dine_in'
        and o.opened_at <= p_at and (o.closed_at is null or o.closed_at > p_at)
    ), '[]'::jsonb),
    'reservations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', coalesce(r.guest_name, 'Gość'), 'party', r.party_size, 'starts_at', r.starts_at, 'ends_at', r.ends_at,
        'seated', r.seated_at is not null and r.seated_at <= p_at,
        'table_ids', coalesce((select jsonb_agg(h.table_id) from public.table_holds h where h.reservation_id = r.id),
                              '[]'::jsonb)
      ) order by r.starts_at)
      from public.reservations r
      where r.restaurant_id = p_restaurant_id and r.source <> 'block'
        and r.starts_at <= p_at and r.ends_at > p_at and r.created_at <= p_at
        and r.status not in ('cancelled', 'no_show')
    ), '[]'::jsonb),
    'takeaway', coalesce((
      select jsonb_agg(jsonb_build_object(
        'order_id', o.id, 'label', private.order_label(o), 'customer', o.customer_name, 'kind', o.kind,
        'stage', case
          when o.delivered_at <= p_at then 'delivered'
          when o.picked_up_at <= p_at then 'on_the_way'
          when o.ready_at <= p_at then 'ready'
          when o.accepted_at <= p_at then 'accepted'
          else 'placed'
        end,
        'total', (select coalesce(sum(i.unit_price_grosze * i.quantity), 0) from public.order_items i
                  where i.order_id = o.id and i.status <> 'cancelled') + o.delivery_fee_grosze
      ) order by o.opened_at)
      from public.orders o
      where o.restaurant_id = p_restaurant_id and o.kind <> 'dine_in' and o.fulfillment <> 'draft'
        and o.opened_at <= p_at
        -- Jeszcze nie wydane ani nie dostarczone w tamtej chwili.
        and (coalesce(o.delivered_at, o.closed_at) is null or coalesce(o.delivered_at, o.closed_at) > p_at)
        -- Odrzucone, anulowane i nieopłacone liczą się tylko, jeśli wtedy jeszcze trwały.
        and (o.fulfillment not in ('rejected', 'cancelled', 'awaiting_payment') or o.closed_at > p_at)
    ), '[]'::jsonb),
    'staff', coalesce((
      select jsonb_agg(jsonb_build_object('name', m.name, 'since', s.started_at) order by s.started_at)
      from public.staff_shifts s join public.staff_members m on m.id = s.member_id
      where s.restaurant_id = p_restaurant_id and s.started_at <= p_at and (s.ended_at is null or s.ended_at > p_at)
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.panel_activity(uuid, timestamptz, timestamptz, uuid) from public, anon;
revoke all on function public.panel_time_machine(uuid, timestamptz) from public, anon;
grant execute on function public.panel_activity(uuid, timestamptz, timestamptz, uuid) to authenticated;
grant execute on function public.panel_time_machine(uuid, timestamptz) to authenticated;

-- Nowe uprawnienie „Logi i Time Machine”.
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
               'customers', 'reviews', 'stats', 'revenue', 'day_close', 'discounts', 'export', 'fraud', 'activity']
$$;

update public.staff_positions
set permissions = array_append(permissions, 'activity')
where not ('activity' = any (permissions))
  and ('day_close' = any (permissions) or 'staff' = any (permissions));
