-- Zwolnienie pracownika (31.10.2026, prośba użytkownika: zaznaczanie pracowników w panelu i „Zwolnij”, „Nieaktywny”).
-- Zwolniony nie loguje się (jak nieaktywny, private.member_by_code sprawdza active), kończy trwającą zmianę i znika
-- z przyszłego grafiku. Przepracowane zmiany, stawka i historia zostają (usunięcie pracownika kasuje jego zmiany).

alter table public.staff_members add column if not exists dismissed_at timestamptz;

comment on column public.staff_members.dismissed_at is 'Kiedy pracownik został zwolniony (null: nie jest zwolniony).';

-- Stan kilku pracowników naraz: 'active' (aktywny, także ponowne zatrudnienie), 'inactive' (nieaktywny),
-- 'dismissed' (zwolniony). Wymaga uprawnienia „Pracownicy” w lokalu każdego z nich. Zwraca liczbę zmienionych.
create or replace function public.panel_set_staff_status(p_member_ids uuid[], p_status text)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_restaurant uuid;
  v_count integer;
begin
  if p_status is null or p_status not in ('active', 'inactive', 'dismissed') then
    raise exception 'Nieznany stan pracownika: %', p_status;
  end if;

  for v_restaurant in
    select distinct m.restaurant_id from public.staff_members m where m.id = any(p_member_ids)
  loop
    perform private.require_permission(v_restaurant, 'staff');
  end loop;

  update public.staff_members m
     set active = (p_status = 'active'),
         dismissed_at = case when p_status = 'dismissed' then coalesce(m.dismissed_at, now()) end
   where m.id = any(p_member_ids);
  get diagnostics v_count = row_count;

  if p_status = 'dismissed' then
    update public.staff_shifts s
       set ended_at = greatest(now(), s.started_at + interval '1 second')
     where s.member_id = any(p_member_ids)
       and s.ended_at is null;
    delete from public.staff_schedule s
     where s.member_id = any(p_member_ids)
       and s.day > current_date;
  end if;

  return v_count;
end;
$$;

revoke all on function public.panel_set_staff_status(uuid[], text) from public, anon;
grant execute on function public.panel_set_staff_status(uuid[], text) to authenticated;
