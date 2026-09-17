-- Table · migracja 0011
-- Imię i nazwisko dla restauracji, cena na osobę w opiniach i automatyczny poziom cen,
-- opinie zostają po usunięciu konta, kod SMS przy zmianie numeru telefonu.

-- ---------------------------------------------------------------
-- Dwie nazwy gościa
-- ---------------------------------------------------------------

alter table public.profiles
  add column full_name text check (char_length(full_name) <= 120);

comment on column public.profiles.first_name is
  'Imię widoczne publicznie przy opiniach.';
comment on column public.profiles.full_name is
  'Imię i nazwisko widoczne tylko dla restauracji, w której gość ma rezerwację. Nigdy przy opiniach.';

-- ---------------------------------------------------------------
-- Opinie zostają po usunięciu konta, jako anonimowe
-- ---------------------------------------------------------------

alter table public.reviews
  drop constraint reviews_user_id_fkey,
  add constraint reviews_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete set null;

create or replace function public.restaurant_reviews(
  p_restaurant_id  uuid,
  p_limit          integer default 20,
  p_offset         integer default 0
)
returns table (
  id            uuid,
  food          smallint,
  service       smallint,
  ambience      smallint,
  body          text,
  verification  public.review_verification,
  author        text,
  is_mine       boolean,
  created_at    timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    rv.id, rv.food, rv.service, rv.ambience, rv.body, rv.verification,
    coalesce(
      nullif(btrim(p.first_name), ''),
      rv.seed_author,
      case when rv.user_id is null then 'Były gość' else 'Gość' end
    ),
    coalesce(rv.user_id = auth.uid(), false),
    rv.created_at
  from reviews rv
  left join profiles p on p.id = rv.user_id
  where rv.restaurant_id = p_restaurant_id
  order by (rv.verification <> 'none') desc, rv.created_at desc
  limit least(greatest(p_limit, 1), 50)
  offset greatest(p_offset, 0)
$$;

-- ---------------------------------------------------------------
-- Cena na osobę i poziom cen liczony z mediany
-- Liczą się tylko zweryfikowane opinie. Bez danych zostaje poziom wpisany ręcznie.
-- ---------------------------------------------------------------

alter table public.reviews
  add column price_per_person smallint check (price_per_person between 1 and 2000);

comment on column public.reviews.price_per_person is
  'Średnia kwota na osobę w złotych, podana przez gościa.';

create or replace function private.price_level_for(p_median numeric)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_median <= 30 then 1
    when p_median <= 50 then 2
    when p_median <= 80 then 3
    else 4
  end::smallint
$$;

create or replace function private.recalculate_price_level(p_restaurant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_median  numeric;
  v_level   smallint;
begin
  select percentile_cont(0.5) within group (order by rv.price_per_person)
  into v_median
  from public.reviews rv
  where rv.restaurant_id = p_restaurant_id
    and rv.verification <> 'none'
    and rv.price_per_person is not null;

  if v_median is null then
    return;
  end if;

  v_level := private.price_level_for(v_median);
  update public.restaurants
  set price_level = v_level
  where id = p_restaurant_id and price_level <> v_level;
end;
$$;

create or replace function private.reviews_price_level_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform private.recalculate_price_level(old.restaurant_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform private.recalculate_price_level(new.restaurant_id);
  end if;
  return null;
end;
$$;

create trigger reviews_price_level
  after insert or delete or update of price_per_person, verification, restaurant_id
  on public.reviews
  for each row execute function private.reviews_price_level_trigger();

revoke execute on function private.price_level_for(numeric) from public, anon, authenticated;
revoke execute on function private.recalculate_price_level(uuid) from public, anon, authenticated;
revoke execute on function private.reviews_price_level_trigger() from public, anon, authenticated;

drop function if exists public.submit_review(uuid, integer, integer, integer, text, uuid);

create or replace function public.submit_review(
  p_restaurant_id     uuid,
  p_food              integer,
  p_service           integer,
  p_ambience          integer,
  p_body              text default null,
  p_reservation_id    uuid default null,
  p_price_per_person  integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid           uuid := auth.uid();
  v_verification  public.review_verification := 'none';
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

  if p_reservation_id is not null then
    perform 1
    from reservations r
    where r.id = p_reservation_id
      and r.user_id = v_uid
      and r.restaurant_id = p_restaurant_id
      and r.status in ('confirmed', 'seated', 'completed')
      and r.ends_at < now();

    if not found then
      raise exception 'Opinię o wizycie możesz dodać dopiero po jej zakończeniu.';
    end if;

    v_verification := 'reservation';
  end if;

  insert into reviews (
    restaurant_id, user_id, reservation_id, food, service, ambience, body,
    verification, price_per_person
  )
  values (
    p_restaurant_id, v_uid, p_reservation_id, p_food, p_service, p_ambience,
    nullif(btrim(p_body), ''), v_verification, p_price_per_person
  )
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'Masz już opinię o tej wizycie albo o tym lokalu.';
end;
$$;

revoke execute on function public.submit_review(uuid, integer, integer, integer, text, uuid, integer) from public, anon;
grant execute on function public.submit_review(uuid, integer, integer, integer, text, uuid, integer) to authenticated;

-- ---------------------------------------------------------------
-- Testowy hook SMS: kod zmiany numeru trafia na nowy numer
-- ---------------------------------------------------------------

create or replace function public.dev_send_sms_hook(event jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
begin
  insert into private.dev_sms_outbox (phone, otp)
  values (
    coalesce(
      nullif(event -> 'user' ->> 'new_phone', ''),
      nullif(event -> 'user' ->> 'phone_change', ''),
      event -> 'user' ->> 'phone'
    ),
    event -> 'sms' ->> 'otp'
  );
  return '{}'::jsonb;
end;
$$;
