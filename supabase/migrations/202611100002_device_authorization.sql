-- Autorização temporária de navegadores para uma única tela de operação.
begin;

create table public.pista_ops_device_codes (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.eventos(id) on delete cascade,
  funcao text not null check (funcao in ('escritorio','locutor')),
  codigo text not null unique,
  criado_por uuid not null references public.perfis(id) on delete restrict,
  substitui_dispositivo_id uuid,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null,
  usado_em timestamptz
);

create table public.pista_ops_devices (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.eventos(id) on delete cascade,
  usuario_auth_id uuid not null references auth.users(id) on delete cascade,
  identificador_navegador uuid not null,
  funcao text not null check (funcao in ('escritorio','locutor')),
  concedido_por uuid not null references public.perfis(id) on delete restrict,
  estado text not null default 'ativo' check (estado in ('ativo','bloqueado','revogado')),
  nome text not null default 'Dispositivo autorizado',
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  revogado_em timestamptz,
  revogado_por uuid references public.perfis(id) on delete restrict
);
create index pista_ops_devices_event_idx on public.pista_ops_devices(evento_id, criado_em desc);
create unique index pista_ops_devices_one_active_session_uq on public.pista_ops_devices(usuario_auth_id) where estado='ativo';
alter table public.pista_ops_device_codes enable row level security;
alter table public.pista_ops_devices enable row level security;
revoke all on public.pista_ops_device_codes, public.pista_ops_devices from public, anon, authenticated;

create or replace function public.pista_ops_device_code_create(p_evento_id uuid,p_funcao text,p_substitui_id uuid default null)
returns table(codigo text, expira_em timestamptz)
language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_code text;
begin
  if v_actor is null or not exists(select 1 from public.pista_ops_members m where m.evento_id=p_evento_id and m.usuario_id=v_actor and m.ativo and m.funcao='organizador') then
    raise exception 'DEVICE_ADMIN_REQUIRED' using errcode='42501';
  end if;
  if p_funcao not in ('escritorio','locutor') then raise exception 'DEVICE_ROLE_INVALID' using errcode='22023'; end if;
  if p_substitui_id is not null and not exists(select 1 from public.pista_ops_devices d where d.id=p_substitui_id and d.evento_id=p_evento_id and d.estado in ('ativo','bloqueado')) then raise exception 'DEVICE_REPLACE_TARGET_INVALID' using errcode='22023'; end if;
  v_code:=substr(upper(replace(gen_random_uuid()::text,'-','')),1,12);
  insert into public.pista_ops_device_codes(evento_id,funcao,codigo,criado_por,substitui_dispositivo_id,expira_em)
  values(p_evento_id,p_funcao,v_code,v_actor,p_substitui_id,now()+interval '10 minutes');
  return query select v_code,now()+interval '10 minutes';
end $$;

create or replace function public.pista_ops_device_activate(p_codigo text,p_identificador uuid,p_nome text default 'Dispositivo autorizado')
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_auth uuid:=auth.uid(); v_code public.pista_ops_device_codes%rowtype; v_device uuid;
begin
  if v_auth is null then raise exception 'DEVICE_AUTH_REQUIRED' using errcode='42501'; end if;
  if coalesce((auth.jwt()->>'is_anonymous')::boolean,false) is not true then raise exception 'DEVICE_ANONYMOUS_AUTH_REQUIRED' using errcode='42501'; end if;
  if p_identificador is null or length(btrim(coalesce(p_nome,'')))=0 or length(btrim(p_nome))>80 then raise exception 'DEVICE_FIELDS_INVALID' using errcode='22023'; end if;
  select * into v_code from public.pista_ops_device_codes c where c.codigo=upper(btrim(p_codigo)) and c.usado_em is null and c.expira_em>now() for update;
  if not found then raise exception 'DEVICE_CODE_INVALID' using errcode='42501'; end if;
  update public.pista_ops_devices set estado='revogado',revogado_em=now(),atualizado_em=now()
   where (usuario_auth_id=v_auth or identificador_navegador=p_identificador) and estado='ativo';
  update public.pista_ops_devices set estado='revogado',revogado_em=now(),revogado_por=v_code.criado_por,atualizado_em=now()
   where id=v_code.substitui_dispositivo_id and estado in ('ativo','bloqueado');
  insert into public.pista_ops_devices(evento_id,usuario_auth_id,identificador_navegador,funcao,concedido_por,nome)
  values(v_code.evento_id,v_auth,p_identificador,v_code.funcao,v_code.criado_por,btrim(p_nome)) returning id into v_device;
  update public.pista_ops_device_codes set usado_em=now() where id=v_code.id;
  return jsonb_build_object('id',v_device,'evento_id',v_code.evento_id,'funcao',v_code.funcao);
end $$;

create or replace function public.pista_ops_device_context(p_evento_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,public,auth as $$
  select jsonb_build_object('id',d.id,'evento_id',d.evento_id,'funcao',d.funcao,'nome',d.nome)
  from public.pista_ops_devices d where d.usuario_auth_id=auth.uid() and d.evento_id=p_evento_id and d.estado='ativo'
    and exists(select 1 from public.eventos e where e.id=d.evento_id and e.status_operacional='em_andamento');
$$;

create or replace function public.pista_ops_device_my_context()
returns jsonb language sql stable security definer set search_path=pg_catalog,public,auth as $$
  select jsonb_build_object('id',d.id,'evento_id',d.evento_id,'funcao',d.funcao,'nome',d.nome,'evento_nome',e.nome)
  from public.pista_ops_devices d join public.eventos e on e.id=d.evento_id
  where d.usuario_auth_id=auth.uid() and d.estado='ativo' and e.status_operacional='em_andamento';
$$;

create or replace function public.pista_ops_devices_list(p_evento_id uuid)
returns table(id uuid,nome text,funcao text,estado text,criado_em timestamptz,identificador_navegador uuid)
language plpgsql stable security definer set search_path=pg_catalog,public,auth,pg_temp as $$
begin
  if not exists(select 1 from public.pista_ops_members m where m.evento_id=p_evento_id and m.usuario_id=auth.uid() and m.ativo and m.funcao='organizador') then
    raise exception 'DEVICE_ADMIN_REQUIRED' using errcode='42501';
  end if;
  return query select d.id,d.nome,d.funcao,d.estado,d.criado_em,d.identificador_navegador from public.pista_ops_devices d where d.evento_id=p_evento_id order by d.criado_em desc;
end $$;

create or replace function public.pista_ops_device_admin_events()
returns table(id uuid,nome text,data date)
language sql stable security definer set search_path=pg_catalog,public,auth as $$
  select e.id,e.nome,e.data from public.eventos e
  where public.usuario_tem_parque(e.parque_id)
    and exists(select 1 from public.pista_ops_members m where m.evento_id=e.id and m.usuario_id=auth.uid() and m.ativo and m.funcao='organizador')
  order by e.data desc,e.nome;
$$;

create or replace function public.pista_ops_device_manage(p_id uuid,p_action text,p_nome text default null)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_event uuid;
begin
  select d.evento_id into v_event from public.pista_ops_devices d where d.id=p_id;
  if v_event is null or not exists(select 1 from public.pista_ops_members m where m.evento_id=v_event and m.usuario_id=v_actor and m.ativo and m.funcao='organizador') then
    raise exception 'DEVICE_ADMIN_REQUIRED' using errcode='42501';
  end if;
  if p_action not in ('bloquear','revogar','reativar','nome') then raise exception 'DEVICE_ACTION_INVALID' using errcode='22023'; end if;
  update public.pista_ops_devices set estado=case p_action when 'bloquear' then 'bloqueado' when 'revogar' then 'revogado' when 'reativar' then 'ativo' else estado end,
    nome=case when p_action='nome' and length(btrim(coalesce(p_nome,''))) between 1 and 80 then btrim(p_nome) else nome end,
    revogado_em=case when p_action in ('revogar','bloquear') then now() when p_action='reativar' then null else revogado_em end,
    revogado_por=case when p_action in ('revogar','bloquear') then v_actor when p_action='reativar' then null else revogado_por end,
    atualizado_em=now() where id=p_id and (p_action<>'nome' or length(btrim(coalesce(p_nome,''))) between 1 and 80);
  return found;
end $$;

create or replace function public.pista_ops_check_access(p_evento_id uuid,p_funcoes text[])
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_device public.pista_ops_devices%rowtype; v_profile_park uuid; v_event_park uuid; v_status text;
begin
  if v_actor is null then raise exception 'PISTA_AUTH_REQUIRED' using errcode='42501'; end if;
  select * into v_device from public.pista_ops_devices d where d.usuario_auth_id=v_actor and d.estado='ativo' and d.evento_id=p_evento_id;
  if found then
    select e.parque_id,e.status_operacional into v_event_park,v_status from public.eventos e where e.id=p_evento_id;
    if v_status<>'em_andamento' then raise exception 'EVENT_OPERATION_BLOCKED' using errcode='42501'; end if;
    if not (v_device.funcao=any(p_funcoes)) then raise exception 'DEVICE_SCREEN_FORBIDDEN' using errcode='42501'; end if;
    if not exists(select 1 from public.pista_ops_members m where m.evento_id=p_evento_id and m.usuario_id=v_device.concedido_por and m.ativo and m.funcao='organizador') then
      raise exception 'DEVICE_GRANT_REVOKED' using errcode='42501';
    end if;
    return v_device.concedido_por;
  end if;
  select parque_id into v_profile_park from public.perfis where id=v_actor;
  if v_profile_park is null then raise exception 'PISTA_PROFILE_REQUIRED' using errcode='42501'; end if;
  select e.parque_id,e.status_operacional into v_event_park,v_status from public.eventos e where e.id=p_evento_id;
  if v_event_park is distinct from v_profile_park then raise exception 'PISTA_EVENT_PARK_MISMATCH' using errcode='42501'; end if;
  if v_status<>'em_andamento' then raise exception 'EVENT_OPERATION_BLOCKED' using errcode='42501'; end if;
  if not exists(select 1 from public.pista_ops_members m where m.evento_id=p_evento_id and m.usuario_id=v_actor and m.ativo and m.funcao=any(p_funcoes)) then raise exception 'PISTA_EVENT_ROLE_REQUIRED' using errcode='42501'; end if;
  return v_actor;
end $$;

create policy eventos_device_select on public.eventos for select to authenticated
using (public.pista_ops_device_context(eventos.id) is not null);

grant execute on function public.pista_ops_device_code_create(uuid,text,uuid) to authenticated;
grant execute on function public.pista_ops_device_activate(text,uuid,text) to authenticated;
grant execute on function public.pista_ops_device_context(uuid),public.pista_ops_device_my_context(),public.pista_ops_devices_list(uuid),public.pista_ops_device_admin_events() to authenticated;
grant execute on function public.pista_ops_device_manage(uuid,text,text) to authenticated;
grant execute on function public.pista_ops_check_access(uuid,text[]) to authenticated;
revoke all on function public.pista_ops_device_code_create(uuid,text,uuid),public.pista_ops_device_activate(text,uuid,text),public.pista_ops_device_context(uuid),public.pista_ops_device_my_context(),public.pista_ops_devices_list(uuid),public.pista_ops_device_admin_events(),public.pista_ops_device_manage(uuid,text,text),public.pista_ops_check_access(uuid,text[]) from public,anon;
commit;
