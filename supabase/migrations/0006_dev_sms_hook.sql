-- Table · migracja 0006 · TYLKO DO TESTÓW
-- Zamiast wysyłać SMS, Supabase zapisuje kod w tabeli private.dev_sms_outbox.
-- Kod podejrzysz w panelu: Table Editor, schemat "private".
-- Przed wydaniem aplikacji wyłącz ten hook i podłącz prawdziwą bramkę SMS.

create schema if not exists private;

create table private.dev_sms_outbox (
  id          bigint generated always as identity primary key,
  phone       text not null,
  otp         text not null,
  created_at  timestamptz not null default now()
);

create or replace function public.dev_send_sms_hook(event jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
begin
  insert into private.dev_sms_outbox (phone, otp)
  values (event -> 'user' ->> 'phone', event -> 'sms' ->> 'otp');
  return '{}'::jsonb;
end;
$$;

grant usage on schema private to supabase_auth_admin;
grant insert on private.dev_sms_outbox to supabase_auth_admin;
grant execute on function public.dev_send_sms_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.dev_send_sms_hook(jsonb) from authenticated, anon, public;
