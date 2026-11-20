-- Poprawka do 0092: klucz główny (event_id, section_id) z dwoma kluczami obcymi PostgREST traktuje jak tabelę łączącą
-- (relacja wiele-do-wielu między `menu_sections` a `calendar_events`), obok istniejącego `menu_sections.event_id`.
-- Zapytanie o `menu_sections` z osadzonym `calendar_events` bez wskazanego klucza (tak pyta panel w Menu) dostawało
-- wtedy błąd PGRST201 „więcej niż jedna relacja”. Tabela ma teraz własny klucz `id`, a para (event_id, section_id)
-- to zwykłe ograniczenie unikalności, więc nie jest już tabelą łączącą.

alter table public.event_section_discounts drop constraint event_section_discounts_pkey;
alter table public.event_section_discounts add column id uuid not null default gen_random_uuid();
alter table public.event_section_discounts add primary key (id);
alter table public.event_section_discounts add constraint event_section_discounts_event_section_key unique (event_id, section_id);

notify pgrst, 'reload schema';
