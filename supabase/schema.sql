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

-- ── quién es "recepción" ───────────────────────────────────────────
-- Ojo: el rol "authenticated" NO basta. Si en el proyecto está activado
-- el registro público, cualquiera puede crearse una cuenta y quedaría
-- como "authenticated". Por eso el permiso se ata a correos concretos
-- de esta tabla. Cambia el correo por el de verdad antes de ejecutar.
create table if not exists public.admins (
  email text primary key,
  note  text not null default ''
);

insert into public.admins (email, note) values
  ('recepcion@hostalamerica.es', 'cuenta única de recepción')
on conflict (email) do nothing;

-- Comprueba el correo del token contra la lista. SECURITY DEFINER para
-- poder leer public.admins aunque el que llama no tenga permiso.
create or replace function public.is_staff()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.admins a
    where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

alter table public.admins enable row level security;

drop policy if exists "la recepcion ve la lista" on public.admins;
create policy "la recepcion ve la lista" on public.admins
  for select to authenticated using (public.is_staff());

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

-- Recepción: solo las cuentas de public.admins, no todo "authenticated".
drop policy if exists "recepcion administra reservas" on public.reservations;
create policy "recepcion administra reservas" on public.reservations
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists "recepcion administra habitaciones" on public.rooms;
create policy "recepcion administra habitaciones" on public.rooms
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists "recepcion administra bloqueos" on public.blocked_dates;
create policy "recepcion administra bloqueos" on public.blocked_dates
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists "recepcion administra ajustes" on public.settings;
create policy "recepcion administra ajustes" on public.settings
  for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- ════════════════════════════════════════════════════════════════════
--  PRECIO CALCULADO EN EL SERVIDOR
--  La web solo envía fechas y datos del huésped. noches y total los pone
--  Postgres a partir de la tarifa del cuarto, así no se pueden falsificar.
-- ════════════════════════════════════════════════════════════════════
create or replace function public.tarifar_reserva()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  tarifa numeric(10,2);
begin
  new.nights := greatest(1, new.check_out - new.check_in);
  select price into tarifa from public.rooms where id = new.room_id;
  new.total := case when tarifa is null then null else tarifa * new.nights end;
  return new;
end $$;

drop trigger if exists reservations_precio on public.reservations;
create trigger reservations_precio
  before insert or update of check_in, check_out, room_id on public.reservations
  for each row execute function public.tarifar_reserva();

do $$ begin
  alter table public.reservations
    add constraint noches_coherentes check (nights = check_out - check_in);
exception when duplicate_object then null; end $$;

-- ════════════════════════════════════════════════════════════════════
--  ÚLTIMO PASO — crear el usuario de recepción
--  Authentication → Users → Add user → Create new user.
--  Usa EXACTAMENTE el correo que pusiste en public.admins (arriba),
--  contraseña larga, y deja "Auto Confirm User" activado.
--
--  IMPORTANTE: en Authentication → Providers → Email, desactiva
--  "Allow new users to sign up". Si no, cualquiera puede registrarse.
-- ════════════════════════════════════════════════════════════════════
