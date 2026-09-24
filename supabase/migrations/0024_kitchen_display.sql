-- Table · migracja 0024
-- Ekran kuchni: stanowisko z uprawnieniem „Kuchnia” (np. Kucharz) widzi zamówienia wysłane
-- na kuchnię i oznacza je jako gotowe. Kelner od razu widzi to u siebie jako „Wydane”.

drop policy "Obsługa z uprawnieniem widzi zamówienia" on public.orders;
drop policy "Obsługa z uprawnieniem widzi pozycje zamówień" on public.order_items;

create policy "Obsługa i kuchnia widzą zamówienia"
  on public.orders for select to authenticated
  using (
    private.has_permission(restaurant_id, 'orders')
    or private.has_permission(restaurant_id, 'kitchen')
  );

create policy "Obsługa i kuchnia widzą pozycje zamówień"
  on public.order_items for select to authenticated
  using (
    private.has_permission(restaurant_id, 'orders')
    or private.has_permission(restaurant_id, 'kitchen')
  );

-- Oznacza pozycje jako gotowe (sent → served) albo cofa to (served → sent).
-- Działa tylko na otwartych rachunkach. Zwraca liczbę zmienionych pozycji.
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
    set status = case when p_done then 'served'::order_item_status else 'sent'::order_item_status end
    from orders o
    where o.id = i.order_id
      and o.status = 'open'
      and i.id = any (p_item_ids)
      and i.status = case when p_done then 'sent'::order_item_status else 'served'::order_item_status end
    returning 1
  )
  select count(*) into v_count from changed;
  return v_count;
end;
$$;

revoke execute on function public.panel_kitchen_set(uuid[], boolean) from public, anon;
grant execute on function public.panel_kitchen_set(uuid[], boolean) to authenticated;
