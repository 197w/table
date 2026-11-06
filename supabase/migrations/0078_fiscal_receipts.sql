-- Paragony fiskalne z panelu (6.11.2026, prośba użytkownika: kasa fiskalna, kasoterminal albo terminal ma
-- odczytać to, co nabito w zamówieniu). Drukarka fiskalna stoi przy jednym komputerze („Drukarki” → „Paragony”);
-- ten komputer drukuje paragon za każdy opłacony rachunek lokalu. Żeby żaden rachunek nie dostał dwóch paragonów
-- (dwa komputery, ponowne uruchomienie), paragon najpierw się rezerwuje wierszem w `fiscal_receipts`, a po
-- wydruku dostaje numer z drukarki. Nieudany wydruk zwalnia rezerwację.

create table public.fiscal_receipts (
  order_id uuid primary key references public.orders (id) on delete cascade,
  restaurant_id uuid not null references public.restaurants (id) on delete cascade,
  claimed_at timestamptz not null default now(),
  printed_at timestamptz,
  receipt_no text,
  device text
);

create index fiscal_receipts_restaurant on public.fiscal_receipts (restaurant_id, claimed_at desc);

alter table public.fiscal_receipts enable row level security;

create policy fiscal_receipts_read on public.fiscal_receipts
  for select to authenticated
  using (private.has_staff_role(restaurant_id, 'staff'));

grant select on public.fiscal_receipts to authenticated;

-- Rezerwacja paragonu dla opłaconego rachunku. False: paragon już jest (albo ktoś go właśnie drukuje).
-- [p_force]: ponowna próba po rezerwacji bez wydruku (np. panel zamknięto w trakcie), tylko ręcznie.
create or replace function public.panel_fiscal_claim(p_order_id uuid, p_force boolean default false)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant uuid;
  v_status text;
begin
  select restaurant_id, status into v_restaurant, v_status from orders where id = p_order_id;
  if v_restaurant is null or not private.has_staff_role(v_restaurant, 'staff') then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
  if v_status <> 'paid' then
    raise exception 'Paragon drukuje się tylko za opłacony rachunek.';
  end if;
  if p_force then
    delete from fiscal_receipts where order_id = p_order_id and printed_at is null;
  end if;
  insert into fiscal_receipts (order_id, restaurant_id) values (p_order_id, v_restaurant)
  on conflict (order_id) do nothing;
  return found;
end;
$$;

-- Paragon wydrukowany: numer z drukarki i nazwa urządzenia.
create or replace function public.panel_fiscal_done(p_order_id uuid, p_receipt_no text, p_device text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update fiscal_receipts
     set printed_at = now(), receipt_no = left(p_receipt_no, 40), device = left(p_device, 80)
   where order_id = p_order_id and private.has_staff_role(restaurant_id, 'staff');
end;
$$;

-- Wydruk się nie udał: rezerwacja znika, rachunek wraca do kolejki.
create or replace function public.panel_fiscal_release(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from fiscal_receipts
   where order_id = p_order_id and printed_at is null and private.has_staff_role(restaurant_id, 'staff');
end;
$$;

-- Opłacone rachunki bez paragonu zamknięte od [p_since], najstarsze pierwsze (kolejka komputera z drukarką).
create or replace function public.panel_fiscal_pending(p_restaurant_id uuid, p_since timestamptz)
returns setof uuid
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not private.has_staff_role(p_restaurant_id, 'staff') then
    raise exception 'Nie masz uprawnień do tej części panelu.';
  end if;
  return query
    select o.id
      from orders o
     where o.restaurant_id = p_restaurant_id
       and o.status = 'paid'
       and o.closed_at >= p_since
       and not exists (select 1 from fiscal_receipts f where f.order_id = o.id)
     order by o.closed_at
     limit 50;
end;
$$;

revoke execute on function public.panel_fiscal_claim(uuid, boolean) from public, anon;
revoke execute on function public.panel_fiscal_done(uuid, text, text) from public, anon;
revoke execute on function public.panel_fiscal_release(uuid) from public, anon;
revoke execute on function public.panel_fiscal_pending(uuid, timestamptz) from public, anon;
grant execute on function public.panel_fiscal_claim(uuid, boolean) to authenticated;
grant execute on function public.panel_fiscal_done(uuid, text, text) to authenticated;
grant execute on function public.panel_fiscal_release(uuid) to authenticated;
grant execute on function public.panel_fiscal_pending(uuid, timestamptz) to authenticated;
