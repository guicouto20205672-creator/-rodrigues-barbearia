-- Give each tenant its own settings row and provide a validated waitlist join RPC.
alter table public.business_settings drop constraint if exists business_settings_pkey;
alter table public.business_settings add constraint business_settings_pkey primary key (business_id);
alter table public.business_settings alter column id set default true;

create or replace function public.join_waitlist(p_service_id uuid,p_barber_id uuid default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_business_id uuid; v_id uuid;
begin
  if auth.uid() is null then raise exception 'Entre na sua conta para entrar na fila.'; end if;
  select business_id into v_business_id from public.services where id=p_service_id and active=true;
  if v_business_id is null then raise exception 'Serviço indisponível.'; end if;
  if p_barber_id is not null and not exists(select 1 from public.barbers where id=p_barber_id and business_id=v_business_id and active=true) then raise exception 'Profissional não pertence a esta barbearia.'; end if;
  insert into public.business_memberships(business_id,user_id,role)
  values(v_business_id,auth.uid(),'client') on conflict(business_id,user_id) do nothing;
  insert into public.waitlist_entries(business_id,client_id,service_id,barber_id,status)
  values(v_business_id,auth.uid(),p_service_id,p_barber_id,'waiting') returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.join_waitlist(uuid,uuid) from public,anon;
grant execute on function public.join_waitlist(uuid,uuid) to authenticated;

drop policy if exists "active businesses are publicly listed" on public.businesses;
create policy "active businesses are publicly listed" on public.businesses
for select to anon,authenticated using(status in ('active','trial'));
grant select on public.businesses to anon,authenticated;
