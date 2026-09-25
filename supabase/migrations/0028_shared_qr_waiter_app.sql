-- Table · migracja 0028
-- 1. Kod QR z panelu jest wspólny: każdy pracownik, który go zeskanuje, zaczyna swoją zmianę.
--    Odblokowanie panelu na swoje konto to osobny krok w aplikacji („Otwórz panel na komputerze”).
-- 2. Aplikacja Table for workers: kelner nabija zamówienia na telefonie. Konto telefonu pracownika dostaje
--    rolę obsługi w lokalu (restaurant_staff), a uprawnienia bierze ze stanowiska.

-- ---------------------------------------------------------------
-- Rola obsługi dla kont pracowników z aplikacji
-- ---------------------------------------------------------------

-- Konto przypisane do aktywnego pracownika ma rolę obsługi. Po wyłączeniu, usunięciu pracownika
-- albo zmianie konta rola znika (kierownik i właściciel zostają, bo mają inną rolę).
create or replace function private.sync_member_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_drop  boolean := false;
begin
  -- Przy usunięciu NEW nie istnieje, więc warunki sprawdzamy osobno dla każdej operacji.
  if tg_op = 'DELETE' then
    v_drop := old.user_id is not null;
  elsif tg_op = 'UPDATE' then
    v_drop := old.user_id is not null and (new.user_id is distinct from old.user_id or not new.active);
  end if;

  if v_drop then
    delete from public.restaurant_staff s
    where s.restaurant_id = old.restaurant_id
      and s.user_id = old.user_id
      and s.role = 'staff'
      and not exists (
        select 1 from public.staff_members m
        where m.restaurant_id = old.restaurant_id and m.user_id = old.user_id and m.active and m.id <> old.id
      );
  end if;

  if tg_op <> 'DELETE' then
    if new.user_id is not null and new.active then
      insert into public.restaurant_staff (restaurant_id, user_id, role)
      values (new.restaurant_id, new.user_id, 'staff')
      on conflict do nothing;
    end if;
    return new;
  end if;
  return old;
end;
$$;

create trigger staff_members_account
after insert or update of user_id, active or delete on public.staff_members
for each row execute function private.sync_member_account();

insert into public.restaurant_staff (restaurant_id, user_id, role)
select restaurant_id, user_id, 'staff' from public.staff_members
where user_id is not null and active
on conflict do nothing;

-- ---------------------------------------------------------------
-- Wspólny kod QR
-- ---------------------------------------------------------------

-- Skan kodu z panelu: zaczyna zmianę pracownika (jeśli jeszcze nie trwa). Kod działa dla wielu osób,
-- dopóki nie wygaśnie. Panelu nie odblokowuje: do tego służy staff_open_panel.
create or replace function public.staff_scan(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row      panel_login_tokens%rowtype;
  v_member   staff_members%rowtype;
  v_started  timestamptz;
  v_new      boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Zaloguj się numerem telefonu.';
  end if;

  select * into v_row from panel_login_tokens
  where token = regexp_replace(coalesce(p_token, ''), '^table-praca:', '');
  if not found then
    raise exception 'To nie jest kod z panelu Table. Zeskanuj kod z ekranu „Zaloguj się do pracy”.';
  end if;
  if v_row.expires_at < now() then
    raise exception 'Kod już wygasł. Zeskanuj nowy kod z panelu.';
  end if;

  select * into v_member from private.my_members() m where m.restaurant_id = v_row.restaurant_id limit 1;
  if not found then
    raise exception 'Twojego numeru nie ma na liście pracowników tego lokalu. Poproś kierownika o dodanie.';
  end if;

  -- Konto aplikacji zostaje przypisane do pracownika (trigger daje mu rolę obsługi w lokalu).
  if v_member.user_id is distinct from auth.uid() then
    update staff_members set user_id = auth.uid() where id = v_member.id;
  end if;

  select started_at into v_started from staff_shifts where member_id = v_member.id and ended_at is null;
  if v_started is null then
    insert into staff_shifts (restaurant_id, member_id, source)
    values (v_member.restaurant_id, v_member.id, 'scan')
    returning started_at into v_started;
    v_new := true;
  end if;

  return jsonb_build_object(
    'restaurant', (select name from restaurants where id = v_member.restaurant_id),
    'member', v_member.name,
    'member_id', v_member.id,
    'token', v_row.token,
    'shift_started_at', v_started,
    'started_now', v_new
  );
end;
$$;

-- Otwiera panel na komputerze, z którego pracownik zeskanował kod, na jego uprawnienia.
-- Działa tylko w trakcie zmiany i tylko raz dla danego kodu (panel od razu pokazuje nowy).
create or replace function public.staff_open_panel(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row     panel_login_tokens%rowtype;
  v_member  staff_members%rowtype;
begin
  select * into v_row from panel_login_tokens
  where token = regexp_replace(coalesce(p_token, ''), '^table-praca:', '')
  for update;
  if not found then
    raise exception 'Nie znaleziono kodu. Zeskanuj kod z panelu jeszcze raz.';
  end if;
  if v_row.expires_at < now() then
    raise exception 'Kod już wygasł. Zeskanuj nowy kod z panelu.';
  end if;
  if v_row.claimed_member_id is not null then
    raise exception 'Ktoś właśnie otworzył panel tym kodem. Zeskanuj nowy kod.';
  end if;

  select * into v_member from private.my_members() m where m.restaurant_id = v_row.restaurant_id limit 1;
  if not found then
    raise exception 'Twojego numeru nie ma na liście pracowników tego lokalu.';
  end if;
  perform private.check_member(v_row.restaurant_id, v_member.id);

  update panel_login_tokens set claimed_member_id = v_member.id, claimed_at = now() where token = v_row.token;
end;
$$;

-- Lokale, w których pracuję, z uprawnieniami stanowiska (np. „orders” odblokowuje zamówienia w aplikacji).
drop function public.staff_my_jobs();
create or replace function public.staff_my_jobs()
returns table (member_id uuid, restaurant_id uuid, restaurant_name text, member_name text,
               position_name text, permissions text[], shift_id uuid, shift_started_at timestamptz,
               week_seconds bigint)
language sql
stable
security definer
set search_path = public
as $$
  select m.id, r.id, r.name, m.name, p.name, coalesce(p.permissions, '{}'), s.id, s.started_at,
         (select coalesce(sum(extract(epoch from coalesce(x.ended_at, now()) - x.started_at)), 0)::bigint
          from staff_shifts x
          where x.member_id = m.id and x.started_at >= date_trunc('week', now()))
  from private.my_members() m
  join restaurants r on r.id = m.restaurant_id
  left join staff_positions p on p.id = m.position_id
  left join staff_shifts s on s.member_id = m.id and s.ended_at is null
  order by r.name
$$;

revoke execute on function public.staff_open_panel(text) from public, anon;
revoke execute on function public.staff_my_jobs() from public, anon;
grant execute on function public.staff_open_panel(text) to authenticated;
grant execute on function public.staff_my_jobs() to authenticated;
