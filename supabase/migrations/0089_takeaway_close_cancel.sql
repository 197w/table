-- Management → Niezamknięte zamówienia: zamknięcie i anulowanie dostawy albo odbioru (20.11.2026, prośba
-- użytkownika: „nie da się zamknąć albo anulować dostawy”).
-- Dotąd dostawę zamykał tylko dostawca w Table for employees (`staff_delivery_done`), odbiór `panel_takeaway_handed`
-- (tylko „w przygotowaniu” i „gotowe”), a odrzucić dało się `panel_takeaway_reject` tylko przed wyjazdem. Zamówienie
-- „w drodze”, po którym dostawca zgubił aplikację albo skończył zmianę, zostawało otwarte na zawsze.

-- Zamyka zamówienie na wynos jako dostarczone i opłacone w dowolnym etapie od „nowe” do „w drodze”. Forma
-- płatności: przy gotówce i karcie przy odbiorze wybiera ją osoba zamykająca ([p_method]: cash, card, other), przy
-- karcie online i opłaconym wcześniej wynika z zamówienia. Dostawca przypisany do zamówienia zostaje przy nim
-- (rozliczenia dostawców) i wraca do kolejki.
create or replace function public.panel_takeaway_finish(
  p_order_id uuid,
  p_method text default 'cash',
  p_member_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order   orders%rowtype;
  v_method  text;
begin
  v_order := private.takeaway_order(p_order_id);
  perform private.require_permission(v_order.restaurant_id, 'orders_close');
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.status <> 'open' or v_order.fulfillment in ('delivered', 'rejected', 'cancelled') then
    raise exception 'To zamówienie jest już zamknięte.';
  end if;
  if v_order.fulfillment in ('draft', 'awaiting_payment') then
    raise exception 'To zamówienie nie zostało jeszcze przyjęte. Anuluj je albo dokończ w Zamówieniach.';
  end if;
  if p_method is null or p_method not in ('cash', 'card', 'other') then
    raise exception 'Wybierz formę płatności.';
  end if;
  v_method := case v_order.payment_choice
    when 'card_online' then 'card'
    when 'prepaid' then 'other'
    else p_method
  end;

  update order_items set status = 'served' where order_id = p_order_id and status in ('new', 'sent', 'ready');
  update orders
  set fulfillment = 'delivered',
      delivered_at = coalesce(delivered_at, now()),
      status = 'paid',
      payment_status = 'paid',
      payment_method = v_method,
      closed_at = now(),
      closed_by = auth.uid(),
      closed_by_member = p_member_id
  where id = p_order_id;

  -- Dostawca, który był w drodze, wraca do kolejki jak po zwykłym dowiezieniu.
  if v_order.courier_member is not null and v_order.fulfillment = 'on_the_way' then
    update staff_members set courier_ready_at = now() where id = v_order.courier_member;
  end if;
  perform private.dispatch_deliveries(v_order.restaurant_id);
end;
$$;

-- Anuluje zamówienie na wynos w dowolnym etapie (także szkic, czekające na płatność i „w drodze”): pozycje są
-- anulowane, dostawca zwolniony. Gość widzi „Odwołane” z powodem. Zwrot za kartę online robi operator płatności.
create or replace function public.panel_takeaway_cancel(
  p_order_id uuid,
  p_reason text default null,
  p_member_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order  orders%rowtype;
begin
  v_order := private.takeaway_order(p_order_id);
  perform private.require_permission(v_order.restaurant_id, 'orders_close');
  perform private.check_member(v_order.restaurant_id, p_member_id);
  if v_order.status <> 'open' or v_order.fulfillment in ('delivered', 'rejected', 'cancelled') then
    raise exception 'To zamówienie jest już zamknięte.';
  end if;

  update order_items set status = 'cancelled' where order_id = p_order_id and status <> 'cancelled';
  update orders
  set fulfillment = 'cancelled',
      status = 'cancelled',
      closed_at = now(),
      closed_by = auth.uid(),
      closed_by_member = p_member_id,
      reject_reason = left(nullif(btrim(p_reason), ''), 200),
      courier_member = null,
      courier_assigned_at = null
  where id = p_order_id;

  -- Dostawca, który był w drodze, wraca do kolejki jak po zwykłym dowiezieniu.
  if v_order.courier_member is not null and v_order.fulfillment = 'on_the_way' then
    update staff_members set courier_ready_at = now() where id = v_order.courier_member;
  end if;
  perform private.dispatch_deliveries(v_order.restaurant_id);
end;
$$;

revoke execute on function public.panel_takeaway_finish(uuid, text, uuid) from public, anon;
revoke execute on function public.panel_takeaway_cancel(uuid, text, uuid) from public, anon;
grant execute on function public.panel_takeaway_finish(uuid, text, uuid) to authenticated;
grant execute on function public.panel_takeaway_cancel(uuid, text, uuid) to authenticated;
