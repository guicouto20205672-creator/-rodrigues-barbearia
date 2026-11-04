-- Security baseline for Rodrigues Barbearia
-- Apply after supabase/schema.sql in the Supabase SQL editor.

alter table public.profiles enable row level security;
alter table public.services enable row level security;
alter table public.barbers enable row level security;
alter table public.appointments enable row level security;
alter table public.waitlist_entries enable row level security;
alter table public.waitlist_offers enable row level security;

-- Remove broad default privileges if they were granted in the project.
revoke all on public.profiles, public.services, public.barbers,
  public.appointments, public.waitlist_entries, public.waitlist_offers from anon, authenticated;

grant select on public.services, public.barbers to anon, authenticated;
grant select, insert on public.profiles to authenticated;
grant update (full_name, phone) on public.profiles to authenticated;
grant select, insert on public.appointments to authenticated;
grant update (status) on public.appointments to authenticated;
grant select, insert on public.waitlist_entries to authenticated;
-- Waitlist offers are server-managed; do not grant direct access to clients.

drop policy if exists "active services are readable" on public.services;
create policy "active services are readable" on public.services
for select to anon, authenticated using (active = true);

drop policy if exists "active barbers are readable" on public.barbers;
create policy "active barbers are readable" on public.barbers
for select to anon, authenticated using (active = true);

drop policy if exists "clients read own profile" on public.profiles;
create policy "clients read own profile" on public.profiles
for select to authenticated using ((select auth.uid()) = id);
create policy "admins read client profiles" on public.profiles
for select to authenticated using ((select private.is_admin()));

drop policy if exists "clients create own client profile" on public.profiles;
create policy "clients create own client profile" on public.profiles
for insert to authenticated with check ((select auth.uid()) = id and role = 'client');

drop policy if exists "clients update own contact details" on public.profiles;
drop policy if exists "users update own contact details" on public.profiles;
create policy "users update own contact details" on public.profiles
for update to authenticated using ((select auth.uid()) = id)
with check ((select auth.uid()) = id and role in ('client','admin'));

drop policy if exists "clients read own appointments" on public.appointments;
create policy "clients read own appointments" on public.appointments
for select to authenticated using ((select auth.uid()) = client_id);
create policy "admins read all appointments" on public.appointments
for select to authenticated using ((select private.is_admin()));
create policy "admins update appointments" on public.appointments
for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

drop policy if exists "clients create own appointments" on public.appointments;
create policy "clients create own appointments" on public.appointments
for insert to authenticated with check ((select auth.uid()) = client_id and status = 'booked');

drop policy if exists "clients cancel own appointments" on public.appointments;
create policy "clients cancel own appointments" on public.appointments
for update to authenticated using ((select auth.uid()) = client_id and status = 'booked')
with check ((select auth.uid()) = client_id and status = 'cancelled');

drop policy if exists "clients read own waitlist entries" on public.waitlist_entries;
create policy "clients read own waitlist entries" on public.waitlist_entries
for select to authenticated using ((select auth.uid()) = client_id);

drop policy if exists "clients join waitlist" on public.waitlist_entries;
create policy "clients join waitlist" on public.waitlist_entries
for insert to authenticated with check (
  (select auth.uid()) = client_id and status = 'waiting'
);

-- No client-facing policies for waitlist_offers: all offer dispatch/response
-- must go through trusted server-side code after authenticating the user.

-- Configurações administrativas e catálogo editável pelo proprietário.
alter table public.business_settings enable row level security;
revoke all on public.business_settings from anon, authenticated;
grant select on public.business_settings to anon, authenticated;
grant insert, update on public.business_settings to authenticated;

create or replace function private.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='admin'); $$;
revoke all on function private.is_admin() from public, anon;
grant execute on function private.is_admin() to authenticated;

drop policy if exists "business settings are publicly readable" on public.business_settings;
create policy "business settings are publicly readable" on public.business_settings for select to anon, authenticated using (true);
drop policy if exists "admins create business settings" on public.business_settings;
create policy "admins create business settings" on public.business_settings for insert to authenticated with check ((select private.is_admin()));
drop policy if exists "admins update business settings" on public.business_settings;
create policy "admins update business settings" on public.business_settings for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

grant insert, update, delete on public.services, public.barbers to authenticated;
drop policy if exists "admins manage services" on public.services;
create policy "admins manage services" on public.services for all to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));
drop policy if exists "admins manage barbers" on public.barbers;
create policy "admins manage barbers" on public.barbers for all to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

-- Booking RPCs: authenticated clients only. Both functions validate auth.uid().
-- The exclusion constraint on appointments remains the final concurrency guard.
