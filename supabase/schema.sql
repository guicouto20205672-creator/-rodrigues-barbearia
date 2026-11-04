create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null,
 phone text,
 role text not null default 'client' check (role in ('client','barber','admin')),
 created_at timestamptz not null default now()
);
create table if not exists public.services (
 id uuid primary key default gen_random_uuid(), name text not null, description text,
 duration_minutes integer not null check(duration_minutes>0), price_cents integer not null check(price_cents>=0),
 active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.barbers (
 id uuid primary key default gen_random_uuid(), profile_id uuid references public.profiles(id) on delete set null,
 display_name text not null, active boolean not null default true
);
create table if not exists public.appointments (
 id uuid primary key default gen_random_uuid(), client_id uuid not null references public.profiles(id),
 barber_id uuid not null references public.barbers(id), service_id uuid not null references public.services(id),
 starts_at timestamptz not null, ends_at timestamptz not null,
 status text not null default 'booked' check(status in ('booked','cancelled','completed','no_show')),
 created_at timestamptz not null default now(), check(ends_at>starts_at)
);
alter table public.appointments drop constraint if exists appointments_no_overlap;
alter table public.appointments add constraint appointments_no_overlap exclude using gist
 (barber_id with =, tstzrange(starts_at,ends_at,'[)') with &&) where(status='booked');
create table if not exists public.waitlist_entries (
 id uuid primary key default gen_random_uuid(), client_id uuid not null references public.profiles(id),
 service_id uuid not null references public.services(id), barber_id uuid references public.barbers(id),
 created_at timestamptz not null default now(),
 status text not null default 'waiting' check(status in ('waiting','offered','accepted','declined','expired','removed'))
);
create table if not exists public.waitlist_offers (
 id uuid primary key default gen_random_uuid(), waitlist_entry_id uuid not null references public.waitlist_entries(id),
 appointment_slot_start timestamptz not null, appointment_slot_end timestamptz not null,
 offered_at timestamptz not null default now(), expires_at timestamptz not null default(now()+interval '5 minutes'),
 status text not null default 'pending' check(status in ('pending','accepted','declined','expired','superseded')),
 responded_at timestamptz, created_at timestamptz not null default now(),
 check(appointment_slot_end>appointment_slot_start)
);
create index if not exists waitlist_fifo_idx on public.waitlist_entries(created_at,id) where status='waiting';
create index if not exists appointments_barber_start_idx on public.appointments(barber_id,starts_at);

-- IMPORTANTE: antes de produção, habilite RLS e aplique políticas restritivas por papel.
-- A oferta FIFO, o prazo de 5 minutos e a aceitação atômica devem ser implementados em função server-side.
-- Nunca exponha a chave service_role no navegador. WhatsApp requer provedor/API oficial configurado.
-- Configurações editáveis pelo proprietário. A agenda usa America/Sao_Paulo por padrão.
create table if not exists public.business_settings (
 id boolean primary key default true check (id = true),
 timezone text not null default 'America/Sao_Paulo',
 opening_hours jsonb not null default '{
  "monday":{"enabled":false,"open":"08:00","close":"18:00","break_start":"","break_end":""},
  "tuesday":{"enabled":false,"open":"08:00","close":"18:00","break_start":"","break_end":""},
  "wednesday":{"enabled":false,"open":"08:00","close":"18:00","break_start":"","break_end":""},
  "thursday":{"enabled":false,"open":"08:00","close":"18:00","break_start":"","break_end":""},
  "friday":{"enabled":false,"open":"08:00","close":"18:00","break_start":"","break_end":""},
  "saturday":{"enabled":false,"open":"08:00","close":"18:00","break_start":"","break_end":""},
  "sunday":{"enabled":false,"open":"08:00","close":"12:00","break_start":"","break_end":""}
 }'::jsonb,
 slot_interval_minutes integer not null default 15 check (slot_interval_minutes between 5 and 120),
 min_booking_notice_hours integer not null default 1 check (min_booking_notice_hours between 0 and 720),
 max_booking_days integer not null default 30 check (max_booking_days between 1 and 365),
 updated_at timestamptz not null default now()
);
