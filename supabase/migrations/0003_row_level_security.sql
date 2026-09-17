-- Table · migracja 0003
-- Uprawnienia. Domyślnie wszystko jest zablokowane.
-- Zapis rezerwacji, opinii i zdarzeń odbywa się wyłącznie przez funkcje z migracji 0004.

alter table public.profiles           enable row level security;
alter table public.restaurants        enable row level security;
alter table public.opening_hours      enable row level security;
alter table public.menu_sections      enable row level security;
alter table public.menu_items         enable row level security;
alter table public.dining_tables      enable row level security;
alter table public.reservations       enable row level security;
alter table public.reservation_diets  enable row level security;
alter table public.table_holds        enable row level security;
alter table public.reviews            enable row level security;
alter table public.restaurant_events  enable row level security;

-- Publiczne dane lokali: każdy może czytać, nikt z aplikacji nie może zmieniać.
create policy "Lokale widoczne dla wszystkich"
  on public.restaurants for select to anon, authenticated using (true);

create policy "Godziny widoczne dla wszystkich"
  on public.opening_hours for select to anon, authenticated using (true);

create policy "Sekcje menu widoczne dla wszystkich"
  on public.menu_sections for select to anon, authenticated using (true);

create policy "Pozycje menu widoczne dla wszystkich"
  on public.menu_items for select to anon, authenticated using (true);

-- Profil: tylko właściciel.
create policy "Gość czyta swój profil"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));

create policy "Gość zmienia swój profil"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Rezerwacje: gość widzi tylko swoje, zmiany tylko przez funkcje.
create policy "Gość czyta swoje rezerwacje"
  on public.reservations for select to authenticated
  using (user_id = (select auth.uid()));

create policy "Gość czyta swoje informacje o diecie"
  on public.reservation_diets for select to authenticated
  using (
    exists (
      select 1 from public.reservations r
      where r.id = reservation_id and r.user_id = (select auth.uid())
    )
  );

-- Stoliki, blokady stolików, opinie i zdarzenia nie mają zasad,
-- więc aplikacja nie ma do nich bezpośredniego dostępu.
-- Opinie są czytane przez funkcję restaurant_reviews, która ukrywa identyfikatory autorów.
