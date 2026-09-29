-- Table · migracja 0034
-- Okres grafiku lokalu: pracownicy zgłaszają godziny na tydzień, 2 tygodnie albo miesiąc.
-- Ustawia go kierownik w „Dane lokalu”, aplikacja Table for employees pokazuje grafik w tym okresie.

alter table public.restaurants
  add column schedule_period text not null default 'week' check (schedule_period in ('week', 'two_weeks', 'month'));

drop function public.staff_my_jobs();
create or replace function public.staff_my_jobs()
returns table (member_id uuid, restaurant_id uuid, restaurant_name text, member_name text,
               position_name text, permissions text[], shift_id uuid, shift_started_at timestamptz,
               week_seconds bigint, schedule_period text)
language sql
stable
security definer
set search_path = public
as $$
  select m.id, r.id, r.name, m.name, p.name, coalesce(private.position_permissions(m.position_id), '{}'),
         s.id, s.started_at,
         (select coalesce(sum(extract(epoch from coalesce(x.ended_at, now()) - x.started_at)), 0)::bigint
          from staff_shifts x
          where x.member_id = m.id and x.started_at >= date_trunc('week', now())),
         r.schedule_period
  from private.my_members() m
  join restaurants r on r.id = m.restaurant_id
  left join staff_positions p on p.id = m.position_id
  left join staff_shifts s on s.member_id = m.id and s.ended_at is null
  order by r.name
$$;

revoke execute on function public.staff_my_jobs() from public, anon;
grant execute on function public.staff_my_jobs() to authenticated;
