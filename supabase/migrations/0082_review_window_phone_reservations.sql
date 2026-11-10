-- 0082: Opinie zweryfikowane tylko przez 48 godzin i rezerwacje telefoniczne na koncie (10.11.2026, prośba użytkownika).
-- Gość ma 48 godzin po wizycie z rezerwacji, dostawie albo odbiorze osobistym, żeby napisać zweryfikowaną opinię.
-- Później opinia o tej wizycie albo o tym zamówieniu jest już niezweryfikowana (zapisuje się bez powiązania).
-- Zamówienie z aplikacji (dostawa, odbiór) weryfikuje opinię tak jak rezerwacja (`verification = 'order'`).
-- Rezerwacja telefoniczna (wpisana w panelu z numerem gościa, bez konta) należy do konta Table z tym samym numerem
-- (ostatnie 9 cyfr, `private.phone_key`): gość widzi ją w „Moje” i może o niej napisać zweryfikowaną opinię. Nie
-- może jej odwołać w aplikacji (dzwoni do lokalu) i nie widzi wiadomości ani notatek lokalu.

alter type public.review_verification add value if not exists 'order';

alter table public.reviews
  add column if not exists order_id uuid unique references public.orders (id) on delete set null;

comment on column public.reviews.order_id is
  'Zamówienie z aplikacji (dostawa albo odbiór), które zweryfikowało opinię.';

-- Ile czasu po wizycie, dostawie albo odbiorze opinia jest jeszcze zweryfikowana.
create or replace function private.review_window()
returns interval
language sql
immutable
set search_path = ''
as $$
  select interval '48 hours'
$$;

-- Rezerwacja należy do konta [p_user]: z aplikacji (user_id) albo telefoniczna bez konta z numerem tego konta.
create or replace function private.guest_owns_reservation(p_user uuid, p_owner uuid, p_guest_phone text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user is not null and (
    p_owner = p_user
    or (
      p_owner is null
      and private.phone_key(p_guest_phone) is not null
      and private.phone_key(p_guest_phone) = private.phone_key(private.account_phone(p_user))
    )
  )
$$;

-- Szukanie rezerwacji telefonicznych po numerze.
create index if not exists reservations_phone_key_idx
  on public.reservations (private.phone_key(guest_phone))
  where user_id is null;

-- „Moje” → Rezerwacje: z aplikacji i telefoniczne z numerem konta. Ten sam kształt co wcześniejsze zapytanie
-- aplikacji do tabeli (z `restaurants`), do tego `by_phone`.
create or replace function public.guest_my_reservations()
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select auth.uid() as uid, private.phone_key(private.account_phone(auth.uid())) as phone
  ),
  mine as (
    select r.*, false as by_phone
    from public.reservations r, me
    where r.user_id = me.uid
    union all
    select r.*, true as by_phone
    from public.reservations r, me
    where r.user_id is null
      and me.phone is not null
      and private.phone_key(r.guest_phone) = me.phone
      and r.source <> 'block'
  )
  select jsonb_build_object(
    'id', m.id,
    'restaurant_id', m.restaurant_id,
    'party_size', m.party_size,
    'starts_at', m.starts_at,
    'ends_at', m.ends_at,
    'status', m.status,
    'occasion', m.occasion,
    'message', case when m.by_phone then null else m.message end,
    'by_phone', m.by_phone,
    'restaurants', jsonb_build_object('name', s.name, 'address', s.address, 'phone', s.phone, 'logo_url', s.logo_url)
  )
  from mine m
  join public.restaurants s on s.id = m.restaurant_id
  where (select uid from me) is not null
  order by m.starts_at desc
  limit 100
$$;

-- Szczegóły rezerwacji: także telefonicznej z numerem konta (`by_phone`).
drop function if exists public.reservation_details(uuid);
create function public.reservation_details(p_reservation_id uuid)
returns table (
  id uuid, restaurant_id uuid, restaurant_name text, address text, city text, phone text,
  lat double precision, lng double precision, party_size smallint, starts_at timestamptz, ends_at timestamptz,
  status public.reservation_status, occasion public.reservation_occasion, message text, diet text, reviewed boolean,
  discount_code text, discount_kind text, discount_value integer, deposit_grosze integer, deposit_status text,
  by_phone boolean
)
language sql
stable
security definer
set search_path = 'public', 'extensions'
as $$
  select
    r.id, r.restaurant_id, s.name, s.address, s.city, s.phone,
    st_y(s.location::geometry), st_x(s.location::geometry),
    r.party_size, r.starts_at, r.ends_at, r.status, r.occasion,
    case when r.user_id is null then null else r.message end,
    case when r.user_id is null then null else d.details end,
    exists (select 1 from reviews rv where rv.reservation_id = r.id),
    r.discount_code, r.discount_kind, r.discount_value, r.deposit_grosze, r.deposit_status,
    r.user_id is null
  from reservations r
  join restaurants s on s.id = r.restaurant_id
  left join reservation_diets d on d.reservation_id = r.id
  where r.id = p_reservation_id
    and r.source <> 'block'
    and private.guest_owns_reservation(auth.uid(), r.user_id, r.guest_phone)
$$;

-- Opinia: zweryfikowana przez rezerwację albo zamówienie z aplikacji tylko do 48 godzin po wizycie, dostawie albo
-- odbiorze. Później zapisuje się jako niezweryfikowana (bez powiązania z wizytą albo zamówieniem).
drop function if exists public.submit_review(uuid, integer, integer, integer, text, uuid, integer);
create function public.submit_review(
  p_restaurant_id    uuid,
  p_food             integer,
  p_service          integer,
  p_ambience         integer,
  p_body             text default null,
  p_reservation_id   uuid default null,
  p_price_per_person integer default null,
  p_order_id         uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_uid           uuid := auth.uid();
  v_verification  public.review_verification := 'none';
  v_reservation   uuid;
  v_order         uuid;
  v_done          timestamptz;
  v_id            uuid;
begin
  if v_uid is null then
    raise exception 'Zaloguj się, żeby dodać opinię.';
  end if;

  if coalesce(p_food, 0) not between 1 and 5
     or coalesce(p_service, 0) not between 1 and 5
     or coalesce(p_ambience, 0) not between 1 and 5 then
    raise exception 'Oceń kuchnię, obsługę i atmosferę w skali od 1 do 5.';
  end if;

  if p_price_per_person is not null and p_price_per_person not between 1 and 2000 then
    raise exception 'Cena na osobę musi mieścić się między 1 a 2000 zł.';
  end if;

  if p_reservation_id is not null and p_order_id is not null then
    raise exception 'Opinia dotyczy wizyty albo zamówienia, nie obu naraz.';
  end if;

  if p_reservation_id is not null then
    select r.ends_at into v_done
    from reservations r
    where r.id = p_reservation_id
      and r.restaurant_id = p_restaurant_id
      and private.guest_owns_reservation(v_uid, r.user_id, r.guest_phone)
      and r.status in ('confirmed', 'seated', 'completed')
      and r.ends_at < now();

    if not found then
      raise exception 'Opinię o wizycie możesz dodać dopiero po jej zakończeniu.';
    end if;

    if now() <= v_done + private.review_window() then
      v_verification := 'reservation';
      v_reservation := p_reservation_id;
    end if;
  end if;

  if p_order_id is not null then
    select coalesce(o.delivered_at, o.closed_at) into v_done
    from orders o
    where o.id = p_order_id
      and o.restaurant_id = p_restaurant_id
      and o.guest_id = v_uid
      and o.kind in ('delivery', 'pickup')
      and o.fulfillment = 'delivered';

    if not found or v_done is null then
      raise exception 'Opinię o zamówieniu możesz dodać, gdy je odbierzesz.';
    end if;

    if now() <= v_done + private.review_window() then
      v_verification := 'order';
      v_order := p_order_id;
    end if;
  end if;

  insert into reviews (
    restaurant_id, user_id, reservation_id, order_id, food, service, ambience, body,
    verification, price_per_person
  )
  values (
    p_restaurant_id, v_uid, v_reservation, v_order, p_food, p_service, p_ambience,
    nullif(btrim(p_body), ''), v_verification, p_price_per_person
  )
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'Masz już opinię o tej wizycie, o tym zamówieniu albo o tym lokalu.';
end;
$$;

-- Zamówienia, o których gość już napisał opinię.
create or replace function public.my_reviewed_orders()
returns setof uuid
language sql
stable
security definer
set search_path = 'public'
as $$
  select order_id from reviews
  where user_id = auth.uid() and order_id is not null
$$;

revoke execute on function private.review_window() from public, anon;
revoke execute on function private.guest_owns_reservation(uuid, uuid, text) from public, anon;
revoke execute on function public.guest_my_reservations() from public, anon;
revoke execute on function public.reservation_details(uuid) from public, anon;
revoke execute on function public.submit_review(uuid, integer, integer, integer, text, uuid, integer, uuid) from public, anon;
revoke execute on function public.my_reviewed_orders() from public, anon;
grant execute on function private.review_window() to authenticated;
grant execute on function private.guest_owns_reservation(uuid, uuid, text) to authenticated;
grant execute on function public.guest_my_reservations() to authenticated;
grant execute on function public.reservation_details(uuid) to authenticated;
grant execute on function public.submit_review(uuid, integer, integer, integer, text, uuid, integer, uuid) to authenticated;
grant execute on function public.my_reviewed_orders() to authenticated;
