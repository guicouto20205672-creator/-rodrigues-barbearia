-- Rodrigues Barbearia SaaS foundation
-- Preserves existing records and assigns them to the founding tenant.
-- This is phase 1 only: do not onboard additional businesses until tenant-aware
-- policies, RPCs, and frontend tenant selection are deployed.

create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  status text not null default 'active' check (status in ('active','trial','suspended','cancelled')),
  plan_code text not null default 'starter',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_memberships (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','barber','client')),
  created_at timestamptz not null default now(),
  unique (business_id, user_id)
);

alter table public.businesses enable row level security;
alter table public.business_memberships enable row level security;
revoke all on public.businesses, public.business_memberships from anon, authenticated;
grant select on public.businesses, public.business_memberships to authenticated;

drop policy if exists "members read their businesses" on public.businesses;
create policy "members read their businesses" on public.businesses
for select to authenticated
using (exists (select 1 from public.business_memberships m
  where m.business_id=businesses.id and m.user_id=(select auth.uid())));

drop policy if exists "users read own memberships" on public.business_memberships;
create policy "users read own memberships" on public.business_memberships
for select to authenticated using (user_id=(select auth.uid()));

alter table public.profiles add column if not exists onboarding_completed boolean not null default false;
alter table public.services add column if not exists business_id uuid references public.businesses(id);
alter table public.barbers add column if not exists business_id uuid references public.businesses(id);
alter table public.appointments add column if not exists business_id uuid references public.businesses(id);
alter table public.waitlist_entries add column if not exists business_id uuid references public.businesses(id);
alter table public.waitlist_offers add column if not exists business_id uuid references public.businesses(id);
alter table public.business_settings add column if not exists business_id uuid references public.businesses(id);

do $$
declare v_business_id uuid; v_owner_id uuid;
begin
  select id into v_owner_id from auth.users
  where lower(email)=lower('guilhermeoliveiraa9090@gmail.com') limit 1;
  if v_owner_id is null then raise exception 'Conta proprietária não encontrada; migração cancelada.'; end if;
  insert into public.businesses(name,slug,status,plan_code)
  values ('Rodrigues Barbearia','rodrigues-barbearia','active','founder')
  on conflict (slug) do update set name=excluded.name
  returning id into v_business_id;
  insert into public.business_memberships(business_id,user_id,role)
  values (v_business_id,v_owner_id,'owner')
  on conflict (business_id,user_id) do update set role='owner';
  update public.services set business_id=v_business_id where business_id is null;
  update public.barbers set business_id=v_business_id where business_id is null;
  update public.appointments set business_id=v_business_id where business_id is null;
  update public.waitlist_entries set business_id=v_business_id where business_id is null;
  update public.waitlist_offers set business_id=v_business_id where business_id is null;
  update public.business_settings set business_id=v_business_id where business_id is null;
  update public.profiles set onboarding_completed=true where id=v_owner_id;
end $$;

alter table public.services alter column business_id set not null;
alter table public.barbers alter column business_id set not null;
alter table public.appointments alter column business_id set not null;
alter table public.waitlist_entries alter column business_id set not null;
alter table public.waitlist_offers alter column business_id set not null;
alter table public.business_settings alter column business_id set not null;

create index if not exists services_business_active_idx on public.services(business_id,active);
create index if not exists barbers_business_active_idx on public.barbers(business_id,active);
create index if not exists appointments_business_start_idx on public.appointments(business_id,starts_at);
create index if not exists waitlist_business_fifo_idx on public.waitlist_entries(business_id,created_at,id) where status='waiting';
create index if not exists memberships_user_idx on public.business_memberships(user_id,business_id);
