begin;

-- Add BOI TV to the existing authorized-device workflow. Regular office and
-- announcer devices retain the temporary-operation restriction.
alter table public.pista_ops_device_codes drop constraint if exists pista_ops_device_codes_funcao_check;
alter table public.pista_ops_device_codes add constraint pista_ops_device_codes_funcao_check
  check (funcao in ('escritorio','locutor','boi_tv'));
alter table public.pista_ops_devices drop constraint if exists pista_ops_devices_funcao_check;
alter table public.pista_ops_devices add constraint pista_ops_devices_funcao_check
  check (funcao in ('escritorio','locutor','boi_tv'));

create or replace function public.pista_ops_device_admin_events()
returns table(id uuid,nome text,data date)
language sql stable security definer set search_path=pg_catalog,public,auth as $$
  select e.id,e.nome,e.data from public.eventos e
  where e.status_operacional='em_andamento'
    and (e.operacao_temporaria or exists(select 1 from public.pista_ops_settings s where s.evento_id=e.id and s.boi_tv))
    and exists(select 1 from public.pista_ops_members m where m.evento_id=e.id and m.usuario_id=auth.uid() and m.ativo and m.funcao='organizador')
  order by e.data desc,e.nome;
$$;

create or replace function public.pista_ops_device_code_create(p_evento_id uuid,p_funcao text,p_substitui_id uuid default null)
returns table(codigo text,expira_em timestamptz)
language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_code text; v_allowed boolean;
begin
  if p_funcao not in ('escritorio','locutor','boi_tv') then raise exception 'DEVICE_ROLE_INVALID' using errcode='22023'; end if;
  select exists(select 1 from public.eventos e join public.pista_ops_members m on m.evento_id=e.id
    where e.id=p_evento_id and e.status_operacional='em_andamento'
      and m.usuario_id=v_actor and m.ativo and m.funcao='organizador'
      and ((p_funcao='boi_tv' and exists(select 1 from public.pista_ops_settings s where s.evento_id=e.id and s.boi_tv))
        or (p_funcao<>'boi_tv' and e.operacao_temporaria))) into v_allowed;
  if v_actor is null or not v_allowed then raise exception 'DEVICE_ADMIN_REQUIRED' using errcode='42501'; end if;
  if p_substitui_id is not null and not exists(select 1 from public.pista_ops_devices d where d.id=p_substitui_id and d.evento_id=p_evento_id and d.funcao=p_funcao and d.estado in ('ativo','bloqueado')) then
    raise exception 'DEVICE_REPLACE_TARGET_INVALID' using errcode='22023';
  end if;
  v_code:=substr(upper(replace(gen_random_uuid()::text,'-','')),1,12);
  insert into public.pista_ops_device_codes(evento_id,funcao,codigo,criado_por,substitui_dispositivo_id,expira_em)
  values(p_evento_id,p_funcao,v_code,v_actor,p_substitui_id,now()+interval '10 minutes');
  return query select v_code,now()+interval '10 minutes';
end $$;

create or replace function public.pista_ops_device_activate(p_codigo text,p_identificador uuid,p_nome text default 'Dispositivo autorizado')
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_auth uuid:=auth.uid(); v_code public.pista_ops_device_codes%rowtype; v_device uuid;
begin
  if v_auth is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) is not true then raise exception 'DEVICE_AUTH_REQUIRED' using errcode='42501'; end if;
  select c.* into v_code from public.pista_ops_device_codes c join public.eventos e on e.id=c.evento_id
    where c.codigo=upper(btrim(p_codigo)) and c.usado_em is null and c.expira_em>now() and e.status_operacional='em_andamento'
      and ((c.funcao='boi_tv' and exists(select 1 from public.pista_ops_settings s where s.evento_id=e.id and s.boi_tv))
        or (c.funcao<>'boi_tv' and e.operacao_temporaria))
    for update of c;
  if not found then raise exception 'DEVICE_CODE_INVALID' using errcode='42501'; end if;
  if p_identificador is null or length(btrim(coalesce(p_nome,'')))=0 or length(btrim(p_nome))>80 then raise exception 'DEVICE_FIELDS_INVALID' using errcode='22023'; end if;
  update public.pista_ops_devices set estado='revogado',revogado_em=now(),atualizado_em=now()
    where (usuario_auth_id=v_auth or identificador_navegador=p_identificador or id=v_code.substitui_dispositivo_id) and estado in ('ativo','bloqueado');
  insert into public.pista_ops_devices(evento_id,usuario_auth_id,identificador_navegador,funcao,concedido_por,nome)
    values(v_code.evento_id,v_auth,p_identificador,v_code.funcao,v_code.criado_por,btrim(p_nome)) returning id into v_device;
  update public.pista_ops_device_codes set usado_em=now() where id=v_code.id;
  return jsonb_build_object('id',v_device,'evento_id',v_code.evento_id,'funcao',v_code.funcao);
end $$;

create or replace function public.pista_ops_device_manage(p_id uuid,p_action text,p_nome text default null)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_event uuid; v_status text; v_temporary boolean; v_role text; v_boi_enabled boolean;
begin
  select d.evento_id,e.status_operacional,e.operacao_temporaria,d.funcao,exists(
    select 1 from public.pista_ops_settings s where s.evento_id=d.evento_id and s.boi_tv
  ) into v_event,v_status,v_temporary,v_role,v_boi_enabled
    from public.pista_ops_devices d join public.eventos e on e.id=d.evento_id where d.id=p_id;
  if v_event is null or v_status<>'em_andamento'
    or not ((v_temporary and v_role<>'boi_tv') or (v_role='boi_tv' and v_boi_enabled))
    or not exists(select 1 from public.pista_ops_members m where m.evento_id=v_event and m.usuario_id=v_actor and m.ativo and m.funcao='organizador') then
    raise exception 'DEVICE_ADMIN_REQUIRED' using errcode='42501';
  end if;
  if p_action not in ('bloquear','revogar','reativar','nome') then raise exception 'DEVICE_ACTION_INVALID' using errcode='22023'; end if;
  update public.pista_ops_devices set
    estado=case p_action when 'bloquear' then 'bloqueado' when 'revogar' then 'revogado' when 'reativar' then 'ativo' else estado end,
    nome=case when p_action='nome' and length(btrim(coalesce(p_nome,''))) between 1 and 80 then btrim(p_nome) else nome end,
    revogado_em=case when p_action in ('revogar','bloquear') then now() when p_action='reativar' then null else revogado_em end,
    revogado_por=case when p_action in ('revogar','bloquear') then v_actor when p_action='reativar' then null else revogado_por end,
    atualizado_em=now() where id=p_id and (p_action<>'nome' or length(btrim(coalesce(p_nome,''))) between 1 and 80);
  return found;
end $$;

notify pgrst, 'reload schema';
commit;
