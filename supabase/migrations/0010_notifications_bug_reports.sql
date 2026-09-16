-- Rarytka · migracja 0010
-- Ustawienia powiadomień push i zgłoszenia błędów z aplikacji.
-- Wszystkie powiadomienia idą przez push. SMS służy wyłącznie do kodów logowania.

create table public.notification_preferences (
  user_id               uuid primary key references auth.users (id) on delete cascade,
  reservation_reminders boolean not null default true,
  reservation_updates   boolean not null default true,
  review_requests       boolean not null default true,
  news                  boolean not null default false,
  updated_at            timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

create policy "Gość czyta swoje ustawienia powiadomień"
  on public.notification_preferences for select to authenticated
  using (user_id = (select auth.uid()));

create policy "Gość tworzy swoje ustawienia powiadomień"
  on public.notification_preferences for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "Gość zmienia swoje ustawienia powiadomień"
  on public.notification_preferences for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create table public.bug_reports (
  id           bigint generated always as identity primary key,
  user_id      uuid references auth.users (id) on delete set null default auth.uid(),
  message      text not null check (char_length(btrim(message)) between 10 and 2000),
  app_version  text check (char_length(app_version) <= 40),
  platform     text check (char_length(platform) <= 40),
  created_at   timestamptz not null default now()
);

create index bug_reports_created_idx on public.bug_reports (created_at desc);
create index bug_reports_user_idx on public.bug_reports (user_id);

alter table public.bug_reports enable row level security;

-- Zgłaszać może każdy, także bez konta. Nikt z aplikacji nie czyta zgłoszeń.
create policy "Każdy może zgłosić błąd"
  on public.bug_reports for insert to anon, authenticated
  with check (user_id is null or user_id = (select auth.uid()));
