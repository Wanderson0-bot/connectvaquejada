begin;

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
    return coalesce(v_device.operador_conta_id, v_device.concedido_por);
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

create or replace function public.pista_ops_boi_tv_atendimento_atualizar(
  p_atendimento_id uuid, p_estado text, p_observacao text default null
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth, pg_temp as $$
declare v_row public.pista_ops_boi_tv_atendimentos%rowtype; v_actor uuid; v_valid boolean;
begin
  select * into v_row from public.pista_ops_boi_tv_atendimentos where id=p_atendimento_id for update;
  if not found then raise exception using errcode='P0001',message='PISTA_TV_SERVICE_NOT_FOUND'; end if;
  select coalesce(d.operador_conta_id,d.concedido_por) into v_actor from public.pista_ops_devices d
    join public.eventos e on e.id=d.evento_id and e.status_operacional='em_andamento'
    join public.pista_ops_settings s on s.evento_id=d.evento_id and s.boi_tv
   where d.evento_id=v_row.evento_id and d.usuario_auth_id=auth.uid()
     and d.funcao='boi_tv' and d.estado='ativo'
     and exists(select 1 from public.pista_ops_members m where m.evento_id=d.evento_id
       and m.usuario_id=d.concedido_por and m.ativo and m.funcao='organizador');
  if v_actor is null then raise exception using errcode='42501',message='PISTA_TV_DEVICE_REQUIRED'; end if;
  v_valid := (v_row.estado_atendimento='nova' and p_estado='recebida')
    or (v_row.estado_atendimento='recebida' and p_estado='em_analise')
    or (v_row.estado_atendimento='em_analise' and p_estado='analise_concluida')
    or (v_row.estado_atendimento='analise_concluida' and p_estado='aguardando_decisao');
  if not coalesce(v_valid,false) then
    raise exception using errcode='P0001',message='PISTA_TV_SERVICE_TRANSITION_INVALID';
  end if;
  update public.pista_ops_boi_tv_atendimentos set
    estado_atendimento=p_estado,
    observacao_operacional=case when p_observacao is not null and p_estado in ('em_analise','analise_concluida')
      then left(btrim(p_observacao),2000) else observacao_operacional end,
    recebida_por=case when p_estado='recebida' then v_actor else recebida_por end,
    recebida_em=case when p_estado='recebida' then now() else recebida_em end,
    operador_id=case when p_estado in ('em_analise','analise_concluida','aguardando_decisao') then v_actor else operador_id end,
    analise_concluida_por=case when p_estado='analise_concluida' then v_actor else analise_concluida_por end,
    analise_concluida_em=case when p_estado='analise_concluida' then now() else analise_concluida_em end,
    atualizada_em=now()
  where id=p_atendimento_id;
  return p_atendimento_id;
end;
$$;

create function public.x1_registrar_boi_na_posicao(p_confronto_id uuid,p_resultado text,p_numero integer)
returns uuid language plpgsql security definer
set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_evento uuid; v_numero integer;
begin
  select evento_id into v_evento from public.x1_matches where id=p_confronto_id for update;
  if not found then raise exception 'X1_MATCH_NOT_FOUND'; end if;
  perform public.pista_ops_check_access(v_evento,array['organizador','locutor']);
  select count(*)+1 into v_numero from public.x1_bois where confronto_id=p_confronto_id;
  if p_numero is distinct from v_numero then
    raise exception 'X1_RESULT_CONFLICT' using errcode='P0001';
  end if;
  return public.x1_registrar_boi(p_confronto_id,p_resultado);
end;
$$;

revoke all on function public.x1_registrar_boi_na_posicao(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.x1_registrar_boi_na_posicao(uuid,text,integer) to authenticated;

create function public.pista_ops_historico_operacional(p_evento_id uuid,p_area text)
returns table(id uuid,senha integer,descricao text,ocorrido_em timestamptz)
language plpgsql stable security definer set search_path=pg_catalog,public,auth,pg_temp as $$
begin
  if p_area='escritorio' then
    perform public.pista_ops_check_access(p_evento_id,array['organizador','escritorio']);
    return query select d.id,d.numero_senha::integer,d.status_pagamento::text,d.created_at
      from public.duplas d where d.evento_id=p_evento_id order by d.created_at desc,d.id limit 50;
  elsif p_area='locutor' then
    perform public.pista_ops_check_access(p_evento_id,array['organizador','locutor']);
    return query select dados.id,dados.senha,dados.descricao,dados.ocorrido_em
      from (
        select r.id,d.numero_senha::integer as senha,
          'Corrida '||r.numero_corrida||' · '||
          case when r.estado='valeu_boi' then 'Valeu boi' else 'Zero' end||
          ' · '||replace(r.pontuacao::text,'.',',')||' pts' as descricao,
          r.atualizado_em as ocorrido_em
        from public.pista_ops_runs r join public.duplas d on d.id=r.dupla_id
        where r.evento_id=p_evento_id and r.estado in ('zero','valeu_boi')
        union all
        select c.id,d.numero_senha::integer,'Correção da corrida '||r.numero_corrida,c.ocorrido_em
        from public.pista_ops_result_corrections c join public.pista_ops_runs r on r.id=c.corrida_id
        join public.duplas d on d.id=r.dupla_id where r.evento_id=p_evento_id
      ) dados order by dados.ocorrido_em desc,dados.id limit 50;
  else
    raise exception 'PISTA_INVALID_HISTORY_AREA' using errcode='22023';
  end if;
end;
$$;

revoke all on function public.pista_ops_historico_operacional(uuid,text) from public,anon;
grant execute on function public.pista_ops_historico_operacional(uuid,text) to authenticated;

notify pgrst, 'reload schema';
commit;
