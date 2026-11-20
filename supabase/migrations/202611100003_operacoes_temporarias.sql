-- Operações rápidas reutilizam o escopo event_id existente sem exigir parque/local.
begin;

alter table public.eventos add column if not exists operacao_temporaria boolean not null default false;
alter table public.eventos alter column parque_id drop not null;
alter table public.competidores alter column parque_id drop not null;
alter table public.competidores add column if not exists evento_id uuid references public.eventos(id) on delete cascade;
create index if not exists competidores_evento_idx on public.competidores(evento_id) where evento_id is not null;

create or replace function public.painel_iniciar_operacao(p_nome text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_nome text:=btrim(coalesce(p_nome,''));
begin
  if v_actor is null or not exists(select 1 from public.perfis p where p.id=v_actor) then raise exception 'OPERATION_ADMIN_PROFILE_REQUIRED' using errcode='42501'; end if;
  if length(v_nome)=0 or length(v_nome)>120 then raise exception 'OPERATION_NAME_INVALID' using errcode='22023'; end if;
  insert into public.eventos(parque_id,nome,data,status,status_operacional,operacao_temporaria)
  values(null,v_nome,current_date,'rascunho','em_andamento',true) returning id into v_id;
  insert into public.pista_ops_members(evento_id,usuario_id,funcao,ativo,criado_por)
  values(v_id,v_actor,'organizador',true,v_actor);
  insert into public.categorias(evento_id,nome,ordem,valor_inscricao,ativa)
  values(v_id,'Geral',1,0,true);
  return v_id;
end $$;

create or replace function public.painel_listar_operacoes()
returns table(id uuid,nome text,data date,status_operacional text,quantidade_inscricoes bigint,quantidade_dispositivos bigint)
language sql stable security definer set search_path=pg_catalog,public,auth as $$
  select e.id,e.nome,e.data,e.status_operacional,
    (select count(*) from public.duplas d where d.evento_id=e.id and d.status_pagamento<>'cancelado')::bigint,
    (select count(*) from public.pista_ops_devices x where x.evento_id=e.id and x.estado='ativo')::bigint
  from public.eventos e join public.pista_ops_members m on m.evento_id=e.id and m.usuario_id=auth.uid() and m.ativo and m.funcao='organizador'
  where e.operacao_temporaria and e.status_operacional='em_andamento' order by e.data desc,e.nome;
$$;

create or replace function public.painel_encerrar_operacao(p_operacao_id uuid)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_ended boolean:=false;
begin
  if not exists(select 1 from public.eventos e join public.pista_ops_members m on m.evento_id=e.id
    where e.id=p_operacao_id and e.operacao_temporaria and m.usuario_id=v_actor and m.ativo and m.funcao='organizador') then
    raise exception 'OPERATION_ADMIN_REQUIRED' using errcode='42501';
  end if;
  update public.eventos set status_operacional='concluido' where id=p_operacao_id and status_operacional='em_andamento';
  v_ended:=found;
  update public.pista_ops_device_codes set usado_em=coalesce(usado_em,now()) where evento_id=p_operacao_id;
  update public.pista_ops_devices set estado='revogado',revogado_em=now(),revogado_por=v_actor,atualizado_em=now()
    where evento_id=p_operacao_id and estado in ('ativo','bloqueado');
  return v_ended;
end $$;

create or replace function public.pista_ops_check_access(p_evento_id uuid,p_funcoes text[])
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare
  v_actor uuid:=auth.uid(); v_device public.pista_ops_devices%rowtype; v_profile_park uuid;
  v_event_park uuid; v_status text; v_temporary boolean;
begin
  if v_actor is null then raise exception 'PISTA_AUTH_REQUIRED' using errcode='42501'; end if;
  select e.parque_id,e.status_operacional,e.operacao_temporaria into v_event_park,v_status,v_temporary from public.eventos e where e.id=p_evento_id;
  if v_status is null then raise exception 'PISTA_EVENT_NOT_FOUND' using errcode='42501'; end if;
  if v_status<>'em_andamento' then raise exception 'EVENT_OPERATION_BLOCKED' using errcode='42501'; end if;
  select * into v_device from public.pista_ops_devices d where d.usuario_auth_id=v_actor and d.estado='ativo' and d.evento_id=p_evento_id;
  if found then
    if not (v_device.funcao=any(p_funcoes)) then raise exception 'DEVICE_SCREEN_FORBIDDEN' using errcode='42501'; end if;
    if not exists(select 1 from public.pista_ops_members m where m.evento_id=p_evento_id and m.usuario_id=v_device.concedido_por and m.ativo and m.funcao='organizador') then raise exception 'DEVICE_GRANT_REVOKED' using errcode='42501'; end if;
    return v_device.concedido_por;
  end if;
  if v_temporary then
    if not exists(select 1 from public.perfis p where p.id=v_actor)
      or not exists(select 1 from public.pista_ops_members m where m.evento_id=p_evento_id and m.usuario_id=v_actor and m.ativo and m.funcao=any(p_funcoes)) then
      raise exception 'PISTA_EVENT_ROLE_REQUIRED' using errcode='42501';
    end if;
    return v_actor;
  end if;
  select parque_id into v_profile_park from public.perfis where id=v_actor;
  if v_profile_park is null or v_event_park is distinct from v_profile_park then raise exception 'PISTA_EVENT_PARK_MISMATCH' using errcode='42501'; end if;
  if not exists(select 1 from public.pista_ops_members m where m.evento_id=p_evento_id and m.usuario_id=v_actor and m.ativo and m.funcao=any(p_funcoes)) then raise exception 'PISTA_EVENT_ROLE_REQUIRED' using errcode='42501'; end if;
  return v_actor;
end $$;

create or replace function public.pista_tem_funcao(p_evento_id uuid,p_funcoes text[])
returns boolean language sql stable security definer set search_path=pg_catalog,public,auth as $$
  select exists(select 1 from public.pista_ops_devices d join public.eventos e on e.id=d.evento_id
    where d.usuario_auth_id=auth.uid() and d.evento_id=p_evento_id and d.estado='ativo' and d.funcao=any(p_funcoes) and e.status_operacional='em_andamento')
  or exists(select 1 from public.pista_ops_members m join public.eventos e on e.id=m.evento_id
    where m.usuario_id=auth.uid() and m.evento_id=p_evento_id and m.ativo and m.funcao=any(p_funcoes) and e.status_operacional='em_andamento'
      and (e.operacao_temporaria or public.usuario_tem_parque(e.parque_id)));
$$;

create or replace function public.pista_ops_can_view_event(p_evento_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public,auth as $$
  select exists(select 1 from public.eventos e where e.id=p_evento_id and e.operacao_temporaria and (
    exists(select 1 from public.pista_ops_members m where m.evento_id=e.id and m.usuario_id=auth.uid() and m.ativo)
    or exists(select 1 from public.pista_ops_devices d where d.evento_id=e.id and d.usuario_auth_id=auth.uid() and d.estado='ativo')
  ));
$$;

create or replace function public.pista_ops_active_round_summary(p_evento_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_result jsonb;
begin
  perform public.pista_ops_check_access(p_evento_id,array['organizador','escritorio','locutor']);
  select jsonb_build_object('id',r.id,'numero',r.numero,'categoria_nome',c.nome,'fila_total',count(q.id),
      'fila_pendente',count(q.id) filter(where q.estado in ('na_fila','retorno_pendente','aguardando_proximo')))
    into v_result from public.pista_ops_rounds r join public.categorias c on c.id=r.categoria_id
    left join public.pista_ops_queue_items q on q.rodada_id=r.id
    where r.evento_id=p_evento_id and r.estado in ('ativo','aguardando_proximo_rodizio')
    group by r.id,c.nome limit 1;
  return v_result;
end $$;

create policy eventos_temporarios_member_select on public.eventos for select to authenticated
using (operacao_temporaria and public.pista_ops_can_view_event(id));
create policy categorias_temporarias_member_select on public.categorias for select to authenticated
using (exists(select 1 from public.eventos e where e.id=categorias.evento_id and e.operacao_temporaria)
  and public.pista_tem_funcao(evento_id,array['organizador','escritorio']));
create policy duplas_temporarias_member_select on public.duplas for select to authenticated
using (exists(select 1 from public.eventos e where e.id=duplas.evento_id and e.operacao_temporaria)
  and public.pista_tem_funcao(evento_id,array['organizador','escritorio']));
create policy competidores_temporarios_member_select on public.competidores for select to authenticated
using (evento_id is not null and public.pista_tem_funcao(evento_id,array['organizador','escritorio']));

create or replace function public.painel_atualizar_pagamento(p_evento_id uuid,p_inscricao_id uuid,p_status text,p_motivo text)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_event public.eventos%rowtype;
begin
  select * into v_event from public.eventos where id=p_evento_id;
  if not found or (v_event.operacao_temporaria and v_event.status_operacional<>'em_andamento')
    or (not v_event.operacao_temporaria and v_event.status_operacional in ('pausado','concluido','cancelado')) then
    raise exception 'EVENT_OPERATION_BLOCKED' using errcode='42501';
  end if;
  if v_event.operacao_temporaria then perform public.pista_ops_check_access(p_evento_id,array['organizador','escritorio']);
  elsif not public.usuario_tem_parque(v_event.parque_id) then raise exception 'EVENT_ACCESS_REQUIRED' using errcode='42501'; end if;
  if p_status is null or p_status not in ('pendente','pago','isento') or (p_status='isento' and length(btrim(coalesce(p_motivo,'')))=0) then raise exception 'PAYMENT_FIELDS_INVALID' using errcode='22023'; end if;
  update public.duplas set status_pagamento=p_status,motivo_isencao=case when p_status='isento' then btrim(p_motivo) else null end
   where id=p_inscricao_id and evento_id=p_evento_id and status_pagamento<>'cancelado';
  return found;
end $$;

create or replace function public.painel_editar_inscricao(p_evento_id uuid,p_inscricao_id uuid,p_categoria_id uuid,p_competidor_id uuid,p_numero_senha integer)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_event public.eventos%rowtype;
begin
  select * into v_event from public.eventos where id=p_evento_id;
  if not found or (v_event.operacao_temporaria and v_event.status_operacional<>'em_andamento')
    or (not v_event.operacao_temporaria and v_event.status_operacional in ('pausado','concluido','cancelado')) then
    raise exception 'EVENT_OPERATION_BLOCKED' using errcode='42501';
  end if;
  if v_event.operacao_temporaria then perform public.pista_ops_check_access(p_evento_id,array['organizador','escritorio']);
  elsif not public.usuario_tem_parque(v_event.parque_id) then raise exception 'EVENT_ACCESS_REQUIRED' using errcode='42501'; end if;
  if p_numero_senha is null or p_numero_senha<1 or not exists(select 1 from public.categorias where id=p_categoria_id and evento_id=p_evento_id)
    or not exists(select 1 from public.competidores c where c.id=p_competidor_id and ((v_event.operacao_temporaria and c.evento_id=p_evento_id) or (not v_event.operacao_temporaria and c.parque_id=v_event.parque_id))) then
    raise exception 'INSCRICAO_EDIT_INVALID' using errcode='22023';
  end if;
  update public.duplas set categoria_id=p_categoria_id,puxador_id=p_competidor_id,numero_senha=p_numero_senha
   where id=p_inscricao_id and evento_id=p_evento_id and status_pagamento<>'cancelado';
  return found;
end $$;

create or replace function public.pista_ops_device_admin_events()
returns table(id uuid,nome text,data date)
language sql stable security definer set search_path=pg_catalog,public,auth as $$
  select e.id,e.nome,e.data from public.eventos e
  where e.operacao_temporaria and e.status_operacional='em_andamento'
    and exists(select 1 from public.pista_ops_members m where m.evento_id=e.id and m.usuario_id=auth.uid() and m.ativo and m.funcao='organizador')
  order by e.data desc,e.nome;
$$;

create or replace function public.pista_ops_device_code_create(p_evento_id uuid,p_funcao text,p_substitui_id uuid default null)
returns table(codigo text,expira_em timestamptz)
language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_code text;
begin
  if v_actor is null or not exists(select 1 from public.eventos e join public.pista_ops_members m on m.evento_id=e.id
    where e.id=p_evento_id and e.operacao_temporaria and e.status_operacional='em_andamento' and m.usuario_id=v_actor and m.ativo and m.funcao='organizador') then
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
  if v_auth is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) is not true then raise exception 'DEVICE_AUTH_REQUIRED' using errcode='42501'; end if;
  select c.* into v_code from public.pista_ops_device_codes c join public.eventos e on e.id=c.evento_id
    where c.codigo=upper(btrim(p_codigo)) and c.usado_em is null and c.expira_em>now() and e.operacao_temporaria and e.status_operacional='em_andamento' for update of c;
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
declare v_actor uuid:=auth.uid(); v_event uuid; v_status text; v_temporary boolean;
begin
  select d.evento_id,e.status_operacional,e.operacao_temporaria into v_event,v_status,v_temporary
    from public.pista_ops_devices d join public.eventos e on e.id=d.evento_id where d.id=p_id;
  if v_event is null or not v_temporary or v_status<>'em_andamento'
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

create or replace function public.inscrever_competidor_evento(
  p_evento_id uuid,p_categoria_id uuid,p_nome text,p_numero_senha integer,p_nome_cavalo text,p_nome_equipe text,
  p_status_pagamento text,p_motivo_isencao text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_event public.eventos%rowtype; v_actor uuid; v_comp uuid; v_entry uuid;
begin
  if p_evento_id is null or p_categoria_id is null or length(btrim(coalesce(p_nome,''))) not between 1 and 120 or p_numero_senha is null or p_numero_senha<1
    or length(btrim(coalesce(p_nome_cavalo,'')))>120 or length(btrim(coalesce(p_nome_equipe,'')))>120
    or p_status_pagamento is null or p_status_pagamento not in ('pendente','pago','isento') or (p_status_pagamento='isento' and length(btrim(coalesce(p_motivo_isencao,''))) not between 1 and 500) then
    raise exception 'INSCRICAO_INVALID_FIELDS' using errcode='22023';
  end if;
  select * into v_event from public.eventos where id=p_evento_id;
  if not found or (v_event.operacao_temporaria and v_event.status_operacional<>'em_andamento')
    or (not v_event.operacao_temporaria and v_event.status_operacional in ('pausado','concluido','cancelado')) then
    raise exception 'EVENT_OPERATION_BLOCKED' using errcode='42501';
  end if;
  if v_event.operacao_temporaria then
    v_actor:=public.pista_ops_check_access(p_evento_id,array['organizador','escritorio']);
    if not exists(select 1 from public.categorias c where c.id=p_categoria_id and c.evento_id=p_evento_id and c.ativa) then raise exception 'INSCRICAO_CATEGORY_INVALID' using errcode='22023'; end if;
    insert into public.competidores(parque_id,evento_id,nome) values(null,p_evento_id,btrim(p_nome)) returning id into v_comp;
  else
    v_actor:=auth.uid();
    if v_event.parque_id is null or not public.usuario_tem_parque(v_event.parque_id) then raise exception 'INSCRICAO_EVENT_ACCESS_DENIED' using errcode='42501'; end if;
    if not exists(select 1 from public.categorias c where c.id=p_categoria_id and c.evento_id=p_evento_id and c.ativa) then raise exception 'INSCRICAO_CATEGORY_INVALID' using errcode='22023'; end if;
    insert into public.competidores(parque_id,nome) values(v_event.parque_id,btrim(p_nome)) returning id into v_comp;
  end if;
  insert into public.duplas(evento_id,categoria_id,puxador_id,numero_senha,nome_cavalo,nome_equipe,status_pagamento,motivo_isencao)
  values(p_evento_id,p_categoria_id,v_comp,p_numero_senha,nullif(btrim(coalesce(p_nome_cavalo,'')),''),nullif(btrim(coalesce(p_nome_equipe,'')),''),p_status_pagamento,
    case when p_status_pagamento='isento' then btrim(p_motivo_isencao) else null end) returning id into v_entry;
  return v_entry;
end $$;

grant execute on function public.painel_iniciar_operacao(text),public.painel_listar_operacoes(),public.painel_encerrar_operacao(uuid),public.pista_ops_can_view_event(uuid) to authenticated;
grant execute on function public.pista_ops_active_round_summary(uuid),public.painel_atualizar_pagamento(uuid,uuid,text,text),public.painel_editar_inscricao(uuid,uuid,uuid,uuid,integer) to authenticated;
grant execute on function public.pista_ops_check_access(uuid,text[]),public.pista_tem_funcao(uuid,text[]),public.pista_ops_device_code_create(uuid,text,uuid),public.pista_ops_device_activate(text,uuid,text),public.pista_ops_device_manage(uuid,text,text),public.inscrever_competidor_evento(uuid,uuid,text,integer,text,text,text,text) to authenticated;
revoke all on function public.painel_iniciar_operacao(text),public.painel_listar_operacoes(),public.painel_encerrar_operacao(uuid),public.pista_ops_can_view_event(uuid) from public,anon;
revoke all on function public.pista_ops_active_round_summary(uuid),public.painel_atualizar_pagamento(uuid,uuid,text,text),public.painel_editar_inscricao(uuid,uuid,uuid,uuid,integer) from public,anon;
revoke all on function public.pista_ops_check_access(uuid,text[]),public.pista_tem_funcao(uuid,text[]),public.pista_ops_device_code_create(uuid,text,uuid),public.pista_ops_device_activate(text,uuid,text),public.pista_ops_device_manage(uuid,text,text),public.inscrever_competidor_evento(uuid,uuid,text,integer,text,text,text,text) from public,anon;

notify pgrst,'reload schema';
commit;
