-- Tenant-scoped RLS policies for the SaaS foundation.
-- Membership is the source of tenant authorization; profile.role alone is not trusted.

create or replace function private.is_business_member(p_business_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists (
    select 1 from public.business_memberships m
    join public.businesses b on b.id=m.business_id
    where m.business_id=p_business_id and m.user_id=(select auth.uid())
      and b.status in ('active','trial')
  );
$$;

create or replace function private.is_business_admin(p_business_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists (
    select 1 from public.business_memberships m
    join public.businesses b on b.id=m.business_id
    where m.business_id=p_business_id and m.user_id=(select auth.uid())
      and m.role in ('owner','admin') and b.status in ('active','trial')
  );
$$;

revoke all on function private.is_business_member(uuid) from public, anon;
revoke all on function private.is_business_admin(uuid) from public, anon;
grant execute on function private.is_business_member(uuid) to authenticated;
grant execute on function private.is_business_admin(uuid) to authenticated;

drop policy if exists "admins read all appointments" on public.appointments;
drop policy if exists "admins update appointments" on public.appointments;
drop policy if exists "admins manage services" on public.services;
drop policy if exists "admins manage barbers" on public.barbers;
drop policy if exists "admins read client profiles" on public.profiles;
drop policy if exists "admins create business settings" on public.business_settings;
drop policy if exists "admins update business settings" on public.business_settings;
drop policy if exists "business settings are publicly readable" on public.business_settings;

create policy "tenant admins manage services" on public.services for all to authenticated
using (private.is_business_admin(business_id))
with check (private.is_business_admin(business_id));
create policy "tenant admins manage barbers" on public.barbers for all to authenticated
using (private.is_business_admin(business_id))
with check (private.is_business_admin(business_id));

create policy "tenant clients and admins read appointments" on public.appointments
for select to authenticated
using (client_id=(select auth.uid()) or private.is_business_admin(business_id));
create policy "tenant clients create appointments" on public.appointments
for insert to authenticated
with check (client_id=(select auth.uid()) and status='booked' and private.is_business_member(business_id));
create policy "tenant admins update appointments" on public.appointments
for update to authenticated
using (private.is_business_admin(business_id))
with check (private.is_business_admin(business_id));

drop policy if exists "clients join waitlist" on public.waitlist_entries;
drop policy if exists "clients read own waitlist entries" on public.waitlist_entries;
create policy "tenant clients read own waitlist entries" on public.waitlist_entries
for select to authenticated using (client_id=(select auth.uid()));
create policy "tenant clients join waitlist" on public.waitlist_entries
for insert to authenticated
with check (client_id=(select auth.uid()) and status='waiting' and private.is_business_member(business_id));

drop policy if exists "Clients read own waitlist offers" on public.waitlist_offers;
create policy "tenant clients read own waitlist offers" on public.waitlist_offers
for select to authenticated using (
  exists (select 1 from public.waitlist_entries w
    where w.id=waitlist_offers.waitlist_entry_id
      and w.client_id=(select auth.uid()) and w.business_id=waitlist_offers.business_id)
);

create policy "tenant members read settings" on public.business_settings
for select to authenticated using (private.is_business_member(business_id));
create policy "tenant admins insert settings" on public.business_settings
for insert to authenticated with check (private.is_business_admin(business_id));
create policy "tenant admins update settings" on public.business_settings
for update to authenticated using (private.is_business_admin(business_id))
with check (private.is_business_admin(business_id));

create policy "tenant admins read member profiles" on public.profiles
for select to authenticated using (
  exists (select 1 from public.business_memberships m
    where m.user_id=profiles.id and private.is_business_admin(m.business_id))
);
