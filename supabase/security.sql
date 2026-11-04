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

drop policy if exists "clients create own client profile" on public.profiles;
create policy "clients create own client profile" on public.profiles
for insert to authenticated with check ((select auth.uid()) = id and role = 'client');

drop policy if exists "clients update own contact details" on public.profiles;
create policy "clients update own contact details" on public.profiles
for update to authenticated using ((select auth.uid()) = id)
with check ((select auth.uid()) = id and role = 'client');

drop policy if exists "clients read own appointments" on public.appointments;
create policy "clients read own appointments" on public.appointments
for select to authenticated using ((select auth.uid()) = client_id);

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
