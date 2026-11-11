-- Inwentaryzacja (11.11.2026, prośby użytkownika):
-- 1. Próg zamówienia przy składniku: „Powiadom o zamówieniu przy” (w jednostce składnika). Panel powiadamia,
--    gdy stan teraz spadnie do tej ilości. Null: bez powiadomień.
-- 2. Statystyki → Inwentaryzacja: zużycie dzień po dniu (sprzedaż z receptur, straty i posiłki pracownicze),
--    średnie zużycie dziennie i prognoza „wystarczy na ok. X dni” (`panel_inventory_usage`).
-- Stan teraz liczy jedna funkcja `private.inventory_stock`, wspólna dla Inwentaryzacji i Statystyk.

alter table public.inventory_items
  add column reorder_at numeric check (reorder_at is null or reorder_at >= 0);

grant insert (reorder_at), update (reorder_at) on public.inventory_items to authenticated;

-- Stan składników teraz bez sprawdzania uprawnień (sprawdzają je funkcje publiczne).
create or replace function private.inventory_stock(p_restaurant_id uuid)
returns table(item_id uuid, counted numeric, counted_at timestamptz, used numeric, delivered numeric,
              removed numeric, stock numeric)
language sql
stable
security definer
set search_path = ''
as $$
  with last_line as (
    select distinct on (l.item_id)
           l.item_id,
           l.quantity * l.capacity * private.inventory_factor(l.unit, i.unit) as total,
           l.updated_at
    from public.inventory_count_lines l
    join public.inventory_counts c on c.id = l.count_id and c.finished_at is not null
    join public.inventory_items i on i.id = l.item_id
    where c.restaurant_id = p_restaurant_id
    order by l.item_id, c.finished_at desc
  ),
  moves as (
    select i.id,
           coalesce(sum(-m.amount) filter (where m.kind = 'sale'), 0) as sold,
           coalesce(sum(m.amount) filter (where m.kind = 'delivery'), 0) as delivered,
           coalesce(sum(-m.amount) filter (where m.kind = 'removal'), 0) as removed,
           coalesce(sum(m.amount), 0) as net
    from public.inventory_items i
    left join last_line ll on ll.item_id = i.id
    left join public.inventory_movements m
      on m.item_id = i.id and m.created_at > coalesce(ll.updated_at, i.created_at)
    where i.restaurant_id = p_restaurant_id and i.deleted_at is null
    group by i.id
  )
  select i.id, ll.total, ll.updated_at, mv.sold, mv.delivered, mv.removed, ll.total + mv.net
  from public.inventory_items i
  join moves mv on mv.id = i.id
  left join last_line ll on ll.item_id = i.id
  where i.restaurant_id = p_restaurant_id and i.deleted_at is null;
$$;

revoke all on function private.inventory_stock(uuid) from public, anon, authenticated;

create or replace function public.panel_inventory_stock(p_restaurant_id uuid, p_member_id uuid default null)
returns table(item_id uuid, counted numeric, counted_at timestamptz, used numeric, delivered numeric,
              removed numeric, stock numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  begin
    perform private.inventory_allowed(p_restaurant_id, p_member_id, 'inventory_count');
  exception when others then
    perform private.inventory_allowed(p_restaurant_id, p_member_id, 'inventory_edit');
  end;
  return query select * from private.inventory_stock(p_restaurant_id);
end;
$$;

-- Zużycie składników w Statystykach: każdy składnik ze stanem teraz, progiem zamówienia, dniem dodania (żeby
-- średnia nowego składnika liczyła się od jego dodania) i zużyciem dzień po dniu w dniach lokalu (z zamknięciem
-- dnia, 0079). Zużycie: sprzedaż z receptur oraz usunięcia ze stratą albo posiłkiem pracowniczym; przekazania do
-- innego lokalu, zwroty do dostawcy i inne powody to nie zużycie.
create or replace function public.panel_inventory_usage(p_restaurant_id uuid, p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz    text;
  v_close interval;
  v_days  integer := least(greatest(coalesce(p_days, 30), 1), 366);
  v_today date;
  v_from  date;
begin
  if not (private.has_permission(p_restaurant_id, 'stats')
          or private.has_permission(p_restaurant_id, 'inventory_count')
          or private.has_permission(p_restaurant_id, 'inventory_edit')) then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;

  select coalesce(timezone, 'Europe/Warsaw') into v_tz from restaurants where id = p_restaurant_id;
  v_close := private.day_close(p_restaurant_id);
  v_today := ((now() at time zone v_tz) - v_close)::date;
  v_from := v_today - (v_days - 1);

  return jsonb_build_object(
    'today', v_today,
    'from', v_from,
    'items', coalesce((
      with usage as (
        select m.item_id,
               ((m.created_at at time zone v_tz) - v_close)::date as day,
               coalesce(sum(-m.amount) filter (where m.kind = 'sale'), 0) as sold,
               coalesce(sum(-m.amount) filter (where m.kind = 'removal' and d.reason in ('loss', 'staff')), 0) as lost
        from inventory_movements m
        left join inventory_docs d on d.id = m.doc_id
        where m.restaurant_id = p_restaurant_id
          and m.kind in ('sale', 'removal')
          and m.created_at >= ((v_from + v_close) at time zone v_tz)
        group by 1, 2
      )
      select jsonb_agg(jsonb_build_object(
        'id', i.id,
        'name', i.name,
        'unit', i.unit,
        'capacity', i.capacity,
        'location', i.location,
        'pack_name', i.pack_name,
        'reorder_at', i.reorder_at,
        'since', ((i.created_at at time zone v_tz) - v_close)::date,
        'stock', s.stock,
        'days', coalesce((
          select jsonb_agg(jsonb_build_object('day', u.day, 'sold', u.sold, 'lost', u.lost) order by u.day)
          from usage u
          where u.item_id = i.id and (u.sold <> 0 or u.lost <> 0)
        ), '[]'::jsonb)
      ) order by lower(i.name))
      from inventory_items i
      left join private.inventory_stock(p_restaurant_id) s on s.item_id = i.id
      where i.restaurant_id = p_restaurant_id and i.deleted_at is null
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.panel_inventory_usage(uuid, integer) from public, anon;
grant execute on function public.panel_inventory_usage(uuid, integer) to authenticated;
