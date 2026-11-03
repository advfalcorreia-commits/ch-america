-- ════════════════════════════════════════════════════════════════════
--  HOSTAL CH AMÉRICA — base de datos del motor de reservas
--  Supabase · Postgres
--
--  CÓMO USARLO
--   1. Entra en supabase.com y crea un proyecto (plan gratuito).
--   2. Menú lateral → SQL Editor → New query.
--   3. Pega TODO este fichero y pulsa Run.
--   4. Project Settings → API: copia "Project URL" y la clave
--      "anon public" en sb-config.js.
--
--  Se puede volver a ejecutar sin miedo: no borra reservas existentes.
-- ════════════════════════════════════════════════════════════════════

-- ── habitaciones ───────────────────────────────────────────────────
create table if not exists public.rooms (
  id      text primary key,
  name    text not null,
  tag     text not null default '',
  m2      integer not null default 14,
  price   numeric(10,2) not null default 0,
  active  boolean not null default true,
  sort    integer not null default 0
);

insert into public.rooms (id, name, tag, m2, price, active, sort) values
  ('r1','Doble Patio',    'Patio interior',    14, 45, true, 1),
  ('r2','Doble Patio II', 'Patio interior',    13, 39, true, 2),
  ('r3','Doble Patio III','Patio interior',    13, 39, true, 3),
  ('r4','Doble Patio IV', 'Patio interior',    14, 45, true, 4),
  ('r5','Doble Superior', 'La más amplia',     20, 59, true, 5),
  ('r6','Doble Calle',    'Calle tranquila',   14, 49, true, 6)
on conflict (id) do nothing;

-- ── fechas cerradas a mano (mantenimiento, uso propio…) ────────────
create table if not exists public.blocked_dates (
  id         bigserial primary key,
  room_id    text not null references public.rooms(id) on delete cascade,
  day        date not null,
  reason     text not null default '',
  created_at timestamptz not null default now(),
  unique (room_id, day)
);

-- ── solicitudes de reserva ─────────────────────────────────────────
do $$ begin
  create type public.res_status as enum ('pending','confirmed','cancelled','done');
exception when duplicate_object then null; end $$;

create table if not exists public.reservations (
  id         bigserial primary key,
  ref        text not null unique,
  room_id    text references public.rooms(id) on delete set null,
  check_in   date not null,
  check_out  date not null,
  nights     integer not null,
  guests     integer not null default 2,
  name       text not null,
  email      text not null,
  phone      text not null,
  country    text not null default '',
  eta        text not null default '',
  notes      text not null default '',
  total      numeric(10,2),
  status     public.res_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fechas_coherentes check (check_out > check_in and nights > 0)
);

create index if not exists reservations_dates  on public.reservations (check_in, check_out);
create index if not exists reservations_status on public.reservations (status);

-- ── ajustes del hostal (una sola fila) ─────────────────────────────
create table if not exists public.settings (
  id             integer primary key default 1 check (id = 1),
  whatsapp       text not null default '34600000000',
  whatsapp_label text not null default '+34 600 000 000',
  check_in       text not null default '14:00',
  check_out      text not null default '12:00',
  max_nights     integer not null default 30
);

insert into public.settings (id) values (1) on conflict (id) do nothing;

-- ── updated_at automático ──────────────────────────────────────────
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists reservations_touch on public.reservations;
create trigger reservations_touch
  before update on public.reservations
  for each row execute function public.touch_updated_at();

-- ════════════════════════════════════════════════════════════════════
--  SEGURIDAD — sin esto la clave pública dejaría la base abierta
-- ════════════════════════════════════════════════════════════════════
alter table public.rooms         enable row level security;
alter table public.blocked_dates enable row level security;
alter table public.reservations  enable row level security;
alter table public.settings      enable row level security;

-- Lectura pública: el sitio necesita precios, fechas cerradas y ajustes.
drop policy if exists "lectura publica rooms" on public.rooms;
create policy "lectura publica rooms" on public.rooms
  for select to anon, authenticated using (true);

drop policy if exists "lectura publica bloqueos" on public.blocked_dates;
create policy "lectura publica bloqueos" on public.blocked_dates
  for select to anon, authenticated using (true);

drop policy if exists "lectura publica ajustes" on public.settings;
create policy "lectura publica ajustes" on public.settings
  for select to anon, authenticated using (true);

-- El sitio público SOLO puede crear solicitudes, y solo en estado "pending".
-- No puede leer las reservas de otros huéspedes (protección de datos).
drop policy if exists "alta publica de solicitudes" on public.reservations;
create policy "alta publica de solicitudes" on public.reservations
  for insert to anon, authenticated
  with check (status = 'pending');

-- Recepción (sesión iniciada con correo y contraseña) manda sobre todo.
drop policy if exists "recepcion administra reservas" on public.reservations;
create policy "recepcion administra reservas" on public.reservations
  for all to authenticated using (true) with check (true);

drop policy if exists "recepcion administra habitaciones" on public.rooms;
create policy "recepcion administra habitaciones" on public.rooms
  for all to authenticated using (true) with check (true);

drop policy if exists "recepcion administra bloqueos" on public.blocked_dates;
create policy "recepcion administra bloqueos" on public.blocked_dates
  for all to authenticated using (true) with check (true);

drop policy if exists "recepcion administra ajustes" on public.settings;
create policy "recepcion administra ajustes" on public.settings
  for all to authenticated using (true) with check (true);

-- ════════════════════════════════════════════════════════════════════
--  ÚLTIMO PASO — crear el usuario de recepción
--  Authentication → Users → Add user → Create new user.
--  Pon el correo del hostal y una contraseña larga, y deja
--  "Auto Confirm User" activado. Ese es el acceso a /adm.html.
--  No hace falta crear más usuarios: la recepción usa uno solo.
-- ════════════════════════════════════════════════════════════════════
