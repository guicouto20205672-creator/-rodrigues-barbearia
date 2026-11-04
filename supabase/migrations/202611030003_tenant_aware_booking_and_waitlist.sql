-- Tenant-aware booking and intelligent waitlist.
-- Existing public RPC signatures are preserved for the current customer UI.
-- Business identity is derived from the selected active barber/service pair.

create or replace function public.get_available_slots(p_barber_id uuid,p_service_id uuid,p_date date)
returns table(slot_start timestamptz,slot_end timestamptz)
language plpgsql security definer set search_path=''
as $$
declare cfg public.business_settings%rowtype; svc public.services%rowtype;
  v_business_id uuid; day_key text; day_cfg jsonb; opening timestamp; closing timestamp;
  break_a timestamptz; break_b timestamptz; candidate timestamptz; finish_at timestamptz;
begin
  if auth.uid() is null then raise exception 'Entre na sua conta para consultar horários.'; end if;
  select b.business_id into v_business_id from public.barbers b where b.id=p_barber_id and b.active=true;
  if v_business_id is null then raise exception 'Profissional indisponível.'; end if;
  select * into svc from public.services where id=p_service_id and business_id=v_business_id and active=true;
  if not found then raise exception 'Serviço indisponível para esta barbearia.'; end if;
  select * into cfg from public.business_settings where business_id=v_business_id limit 1;
  if not found then raise exception 'O funcionamento desta barbearia ainda não foi configurado.'; end if;
  if p_date < (now() at time zone cfg.timezone)::date or p_date > (now() at time zone cfg.timezone)::date+cfg.max_booking_days then return; end if;
  day_key:=case extract(isodow from p_date)::integer when 1 then 'monday' when 2 then 'tuesday' when 3 then 'wednesday' when 4 then 'thursday' when 5 then 'friday' when 6 then 'saturday' else 'sunday' end;
  day_cfg:=cfg.opening_hours->day_key;
  if coalesce((day_cfg->>'enabled')::boolean,false)=false then return; end if;
  opening:=p_date+(day_cfg->>'open')::time; closing:=p_date+(day_cfg->>'close')::time;
  candidate:=opening at time zone cfg.timezone; finish_at:=closing at time zone cfg.timezone;
  break_a:=case when coalesce(day_cfg->>'break_start','')='' then null else (p_date+(day_cfg->>'break_start')::time) at time zone cfg.timezone end;
  break_b:=case when coalesce(day_cfg->>'break_end','')='' then null else (p_date+(day_cfg->>'break_end')::time) at time zone cfg.timezone end;
  while candidate+make_interval(mins=>svc.duration_minutes)<=finish_at loop
    if candidate>=now()+make_interval(hours=>cfg.min_booking_notice_hours)
      and not (break_a is not null and break_b is not null and tstzrange(candidate,candidate+make_interval(mins=>svc.duration_minutes),'[)') && tstzrange(break_a,break_b,'[)'))
      and not exists(select 1 from public.appointments a where a.business_id=v_business_id and a.barber_id=p_barber_id and a.status='booked' and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(candidate,candidate+make_interval(mins=>svc.duration_minutes),'[)'))
    then slot_start:=candidate; slot_end:=candidate+make_interval(mins=>svc.duration_minutes); return next; end if;
    candidate:=candidate+make_interval(mins=>cfg.slot_interval_minutes);
  end loop;
end; $$;

create or replace function public.create_booking(p_barber_id uuid,p_service_id uuid,p_starts_at timestamptz)
returns uuid language plpgsql security definer set search_path=''
as $$
declare new_id uuid; v_business_id uuid; v_tz text;
begin
  if auth.uid() is null then raise exception 'Entre na sua conta para agendar.'; end if;
  select business_id into v_business_id from public.barbers where id=p_barber_id and active=true;
  if v_business_id is null then raise exception 'Profissional indisponível.'; end if;
  if not exists(select 1 from public.services where id=p_service_id and business_id=v_business_id and active=true) then raise exception 'Serviço não pertence a esta barbearia ou está indisponível.'; end if;
  select timezone into v_tz from public.business_settings where business_id=v_business_id;
  if v_tz is null then raise exception 'A barbearia ainda não configurou seus horários.'; end if;
  if not exists(select 1 from public.get_available_slots(p_barber_id,p_service_id,(p_starts_at at time zone v_tz)::date) s where s.slot_start=p_starts_at) then raise exception 'Esse horário não está mais disponível. Atualize os horários e escolha outro.'; end if;
  insert into public.business_memberships(business_id,user_id,role) values(v_business_id,auth.uid(),'client') on conflict(business_id,user_id) do nothing;
  insert into public.appointments(business_id,client_id,barber_id,service_id,starts_at,ends_at,status)
  select v_business_id,auth.uid(),p_barber_id,p_service_id,p_starts_at,p_starts_at+make_interval(mins=>s.duration_minutes),'booked'
  from public.services s where s.id=p_service_id and s.business_id=v_business_id and s.active=true returning id into new_id;
  if new_id is null then raise exception 'Não foi possível confirmar o agendamento.'; end if;
  return new_id;
exception when exclusion_violation then raise exception 'Alguém acabou de reservar esse horário. Escolha outro.';
end; $$;

create or replace function private.dispatch_waitlist_slot(p_business_id uuid,p_service_id uuid,p_barber_id uuid,p_start timestamptz,p_end timestamptz)
returns void language plpgsql security definer set search_path=''
as $$
declare v_entry public.waitlist_entries%rowtype;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_business_id::text||':'||p_barber_id::text||':'||p_start::text||':'||p_service_id::text));
  if exists(select 1 from public.waitlist_offers o where o.business_id=p_business_id and o.appointment_slot_start=p_start and o.appointment_slot_end=p_end and o.appointment_barber_id=p_barber_id and o.status='pending' and o.expires_at>now()) then return; end if;
  select w.* into v_entry from public.waitlist_entries w where w.business_id=p_business_id and w.service_id=p_service_id and (w.barber_id is null or w.barber_id=p_barber_id) and w.status='waiting' order by w.created_at,w.id for update skip locked limit 1;
  if not found then return; end if;
  insert into public.waitlist_offers(business_id,waitlist_entry_id,appointment_slot_start,appointment_slot_end,appointment_barber_id,offered_at,expires_at,status)
  values(p_business_id,v_entry.id,p_start,p_end,p_barber_id,now(),now()+interval '5 minutes','pending');
  update public.waitlist_entries set status='offered' where id=v_entry.id;
end; $$;

create or replace function private.on_appointment_cancelled_dispatch()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if old.status='booked' and new.status='cancelled' then perform private.dispatch_waitlist_slot(old.business_id,old.service_id,old.barber_id,old.starts_at,old.ends_at); end if;
  return new;
end; $$;

create or replace function private.expire_waitlist_offers()
returns void language plpgsql security definer set search_path=''
as $$
declare v record;
begin
  for v in select o.id,o.business_id,o.waitlist_entry_id,o.appointment_slot_start,o.appointment_slot_end,o.appointment_barber_id,w.service_id
    from public.waitlist_offers o join public.waitlist_entries w on w.id=o.waitlist_entry_id
    where o.status='pending' and o.expires_at<=now() for update of o skip locked
  loop
    update public.waitlist_offers set status='expired',responded_at=now() where id=v.id;
    update public.waitlist_entries set status='expired' where id=v.waitlist_entry_id;
    perform private.dispatch_waitlist_slot(v.business_id,v.service_id,v.appointment_barber_id,v.appointment_slot_start,v.appointment_slot_end);
  end loop;
end; $$;

create or replace function public.respond_waitlist_offer(p_offer_id uuid,p_decision text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_offer public.waitlist_offers%rowtype; v_entry public.waitlist_entries%rowtype;
begin
  if auth.uid() is null then raise exception 'Faça login para responder à oferta.'; end if;
  if p_decision not in ('accepted','declined') then raise exception 'Resposta inválida.'; end if;
  select o.* into v_offer from public.waitlist_offers o join public.waitlist_entries w on w.id=o.waitlist_entry_id where o.id=p_offer_id and w.client_id=auth.uid() and w.business_id=o.business_id for update of o;
  if not found then raise exception 'Oferta não encontrada.'; end if;
  if v_offer.status<>'pending' then raise exception 'Esta oferta não está mais disponível.'; end if;
  select * into v_entry from public.waitlist_entries where id=v_offer.waitlist_entry_id for update;
  if v_offer.expires_at<=now() then
    update public.waitlist_offers set status='expired',responded_at=now() where id=p_offer_id;
    update public.waitlist_entries set status='expired' where id=v_entry.id;
    perform private.dispatch_waitlist_slot(v_entry.business_id,v_entry.service_id,v_offer.appointment_barber_id,v_offer.appointment_slot_start,v_offer.appointment_slot_end);
    return jsonb_build_object('ok',false,'message','O prazo de 5 minutos terminou.');
  end if;
  if p_decision='declined' then
    update public.waitlist_offers set status='declined',responded_at=now() where id=p_offer_id;
    update public.waitlist_entries set status='declined' where id=v_entry.id;
    perform private.dispatch_waitlist_slot(v_entry.business_id,v_entry.service_id,v_offer.appointment_barber_id,v_offer.appointment_slot_start,v_offer.appointment_slot_end);
    return jsonb_build_object('ok',true,'message','Oferta recusada. A próxima pessoa será chamada.');
  end if;
  insert into public.business_memberships(business_id,user_id,role) values(v_entry.business_id,v_entry.client_id,'client') on conflict(business_id,user_id) do nothing;
  begin
    insert into public.appointments(business_id,client_id,barber_id,service_id,starts_at,ends_at,status)
    values(v_entry.business_id,v_entry.client_id,v_offer.appointment_barber_id,v_entry.service_id,v_offer.appointment_slot_start,v_offer.appointment_slot_end,'booked');
  exception when exclusion_violation or unique_violation then
    update public.waitlist_offers set status='superseded',responded_at=now() where id=p_offer_id;
    update public.waitlist_entries set status='declined' where id=v_entry.id;
    return jsonb_build_object('ok',false,'message','Esse horário acabou de ser ocupado.');
  end;
  update public.waitlist_offers set status='accepted',responded_at=now() where id=p_offer_id;
  update public.waitlist_entries set status='accepted' where id=v_entry.id;
  return jsonb_build_object('ok',true,'message','Horário reservado com sucesso!');
end; $$;

create or replace function public.join_waitlist(p_service_id uuid,p_barber_id uuid default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_business_id uuid; v_id uuid;
begin
  if auth.uid() is null then raise exception 'Entre na sua conta para entrar na fila.'; end if;
  select business_id into v_business_id from public.services where id=p_service_id and active=true;
  if v_business_id is null then raise exception 'Serviço indisponível.'; end if;
  if p_barber_id is not null and not exists(select 1 from public.barbers where id=p_barber_id and business_id=v_business_id and active=true) then raise exception 'Profissional não pertence a esta barbearia.'; end if;
  insert into public.business_memberships(business_id,user_id,role) values(v_business_id,auth.uid(),'client') on conflict(business_id,user_id) do nothing;
  insert into public.waitlist_entries(business_id,client_id,service_id,barber_id,status) values(v_business_id,auth.uid(),p_service_id,p_barber_id,'waiting') returning id into v_id;
  return v_id;
end; $$;

revoke all on function public.get_available_slots(uuid,uuid,date) from public,anon;
revoke all on function public.create_booking(uuid,uuid,timestamptz) from public,anon;
revoke all on function public.respond_waitlist_offer(uuid,text) from public,anon;
revoke all on function public.join_waitlist(uuid,uuid) from public,anon;
grant execute on function public.get_available_slots(uuid,uuid,date) to authenticated;
grant execute on function public.create_booking(uuid,uuid,timestamptz) to authenticated;
grant execute on function public.respond_waitlist_offer(uuid,text) to authenticated;
grant execute on function public.join_waitlist(uuid,uuid) to authenticated;
revoke all on function private.dispatch_waitlist_slot(uuid,uuid,uuid,timestamptz,timestamptz) from public,anon,authenticated;
