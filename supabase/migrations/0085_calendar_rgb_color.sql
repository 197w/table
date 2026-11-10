-- 0085: Własny kolor RGB wydarzenia w Kalendarzu (10.11.2026, prośba użytkownika).
-- Obok gotowych nazw (green, blue, violet, amber, rose, teal, gray) kolor może być „#RRGGBB” (wielkie litery
-- zapisuje panel i Table for employees).

alter table public.calendar_events drop constraint if exists calendar_events_color_check;
alter table public.calendar_events add constraint calendar_events_color_check
  check (color in ('green', 'blue', 'violet', 'amber', 'rose', 'teal', 'gray') or color ~ '^#[0-9A-F]{6}$');
