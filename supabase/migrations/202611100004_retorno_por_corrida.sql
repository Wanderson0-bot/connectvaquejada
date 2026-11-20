-- Retornos permanecem no rodízio da corrida original. Se a primeira corrida
-- voltar, a segunda só será planejada no próximo rodízio.
begin;

create or replace function public.pista_ops_liberar_retorno(p_item_fila_id uuid)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  item public.pista_ops_queue_items%rowtype;
  target_round public.pista_ops_rounds%rowtype;
  actor_id uuid;
begin
  select q.* into item from public.pista_ops_queue_items q where q.id=p_item_fila_id;
  if not found then raise exception using errcode='P0001',message='PISTA_QUEUE_ITEM_NOT_FOUND'; end if;
  select * into target_round from public.pista_ops_rounds where id=item.rodada_id;
  actor_id:=public.pista_ops_check_access(target_round.evento_id,array['organizador','locutor']);
  perform public.pista_ops_lock_category(target_round.evento_id,target_round.categoria_id);
  select q.* into item from public.pista_ops_queue_items q where q.id=p_item_fila_id for update;
  if item.estado<>'retorno_pendente' then raise exception using errcode='P0001',message='PISTA_RETURN_NOT_PENDING'; end if;
  if target_round.estado<>'ativo' then
    return jsonb_build_object('status','aguardando_proximo_rodizio','item_id',item.id);
  end if;
  -- Retorno não consome boi: posições já usadas podem ser reutilizadas.
  if not exists(select 1 from public.pista_ops_positions p where p.rodada_id=target_round.id and p.estado in ('livre','consumida')) then
    return jsonb_build_object('status','aguardando_proximo_rodizio','item_id',item.id);
  end if;
  update public.pista_ops_queue_items set estado='na_fila',eh_retorno=true where id=item.id;
  update public.pista_ops_runs set estado='pendente',atualizado_em=now() where id=item.corrida_id and estado='retorno_pendente';
  return jsonb_build_object('status','liberado','item_id',item.id);
end;
$$;

create or replace function public.pista_ops_chamar_proxima(p_rodizio_id uuid,p_request_id uuid)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog,public,auth,pg_temp
as $$
declare
  target public.pista_ops_rounds%rowtype;
  actor_id uuid;
  item public.pista_ops_queue_items%rowtype;
  position_number integer;
  result_payload jsonb;
  request_row_id uuid;
begin
  if p_request_id is null then raise exception using errcode='22023',message='PISTA_REQUEST_ID_REQUIRED'; end if;
  select * into target from public.pista_ops_rounds where id=p_rodizio_id;
  if not found then raise exception using errcode='P0001',message='PISTA_ROUND_NOT_FOUND'; end if;
  actor_id:=public.pista_ops_check_access(target.evento_id,array['organizador','escritorio','locutor']);
  perform public.pista_ops_lock_category(target.evento_id,target.categoria_id);
  select * into target from public.pista_ops_rounds where id=p_rodizio_id for update;
  select r.id,r.resultado into request_row_id,result_payload from public.pista_ops_call_requests r
    where r.rodada_id=target.id and r.request_id=p_request_id for update;
  if found then
    if result_payload is null then raise exception using errcode='P0001',message='PISTA_REQUEST_IN_PROGRESS'; end if;
    return result_payload;
  end if;
  insert into public.pista_ops_call_requests(rodada_id,request_id) values(target.id,p_request_id) returning id into request_row_id;
  if target.estado<>'ativo' then raise exception using errcode='P0001',message='PISTA_ROUND_NOT_ACTIVE'; end if;

  update public.pista_ops_queue_items q set estado='encaminhada' from public.duplas d
   where q.dupla_id=d.id and q.rodada_id=target.id and q.estado='na_fila' and d.status_pagamento='cancelado';
  select * into item from public.pista_ops_queue_items q where q.rodada_id=target.id and q.estado='na_fila'
    and exists(select 1 from public.duplas d where d.id=q.dupla_id and d.status_pagamento is distinct from 'cancelado')
    order by q.ordem_fila for update skip locked limit 1;
  if not found then
    if exists(select 1 from public.pista_ops_runs r join public.duplas d on d.id=r.dupla_id
      where r.evento_id=target.evento_id and r.categoria_id=target.categoria_id and r.estado in ('pendente','retorno_pendente')
        and not (r.numero_corrida=2 and exists(
          select 1 from public.pista_ops_runs first_run where first_run.dupla_id=r.dupla_id
            and first_run.numero_corrida=1 and first_run.retornos_realizados>0 and first_run.estado='valeu_boi'))
        and d.status_pagamento is distinct from 'cancelado')
      or exists(select 1 from public.pista_ops_queue_items q where q.rodada_id=target.id and q.estado in ('retorno_pendente','aguardando_proximo')) then
      update public.pista_ops_rounds set estado='aguardando_proximo_rodizio' where id=target.id;
      result_payload:=jsonb_build_object('status','aguardando_proximo_rodizio');
      update public.pista_ops_call_requests set resultado=result_payload where id=request_row_id;
      return result_payload;
    end if;
    update public.pista_ops_rounds set estado='finalizado' where id=target.id;
    result_payload:=jsonb_build_object('status','fila_concluida');
    update public.pista_ops_call_requests set resultado=result_payload where id=request_row_id;
    return result_payload;
  end if;

  select p.numero_posicao into position_number from public.pista_ops_positions p
   where p.rodada_id=target.id and (p.estado='livre' or (item.eh_retorno and p.estado='consumida'))
   order by case p.estado when 'livre' then 0 else 1 end,p.numero_posicao for update skip locked limit 1;
  if position_number is null then
    update public.pista_ops_queue_items set estado='aguardando_proximo' where rodada_id=target.id and estado='na_fila';
    update public.pista_ops_rounds set estado='aguardando_proximo_rodizio' where id=target.id;
    result_payload:=jsonb_build_object('status','aguardando_proximo_rodizio');
    update public.pista_ops_call_requests set resultado=result_payload where id=request_row_id;
    return result_payload;
  end if;
  update public.pista_ops_queue_items set estado='chamada' where id=item.id;
  update public.pista_ops_positions set estado='ocupada',item_fila_id=item.id
    where rodada_id=target.id and numero_posicao=position_number and estado in ('livre','consumida');
  if not found then raise exception using errcode='P0001',message='PISTA_POSITION_RACE'; end if;
  if item.tipo='regular' then
    update public.pista_ops_runs set estado='em_curso',atualizado_em=now() where id=item.corrida_id and estado in ('pendente','retorno_pendente');
    if not found then raise exception using errcode='P0001',message='PISTA_RUN_NOT_CALLABLE'; end if;
  end if;
  result_payload:=jsonb_build_object('status','chamada','item_id',item.id,'posicao',position_number,'tipo',item.tipo,'eh_retorno',item.eh_retorno);
  update public.pista_ops_call_requests set resultado=result_payload where id=request_row_id;
  return result_payload;
end;
$$;

create or replace function public.pista_ops_registrar_resultado(p_item_fila_id uuid,p_resultado text,p_pontuacao numeric)
returns uuid
language plpgsql security definer
set search_path = pg_catalog,public,auth,pg_temp
as $$
declare
  item public.pista_ops_queue_items%rowtype;
  target_round public.pista_ops_rounds%rowtype;
  actor_id uuid;
begin
  select q.* into item from public.pista_ops_queue_items q where q.id=p_item_fila_id;
  if not found then raise exception using errcode='P0001',message='PISTA_QUEUE_ITEM_NOT_FOUND'; end if;
  select * into target_round from public.pista_ops_rounds where id=item.rodada_id;
  actor_id:=public.pista_ops_check_access(target_round.evento_id,array['organizador','locutor']);
  perform public.pista_ops_lock_category(target_round.evento_id,target_round.categoria_id);
  select q.* into item from public.pista_ops_queue_items q where q.id=p_item_fila_id for update;
  if item.estado<>'chamada' or item.tipo<>'regular' then raise exception using errcode='P0001',message='PISTA_RESULT_NOT_CALLABLE'; end if;
  if p_resultado not in ('zero','valeu_boi') then raise exception using errcode='22023',message='PISTA_INVALID_RESULT'; end if;
  if p_resultado='valeu_boi' and (p_pontuacao is null or p_pontuacao<0) then raise exception using errcode='22023',message='PISTA_SCORE_REQUIRED'; end if;
  if p_resultado='zero' and p_pontuacao is distinct from 0::numeric then raise exception using errcode='22023',message='PISTA_ZERO_SCORE_MUST_BE_ZERO'; end if;
  update public.pista_ops_runs set estado=p_resultado,pontuacao=p_pontuacao,
    retornos_realizados=retornos_realizados+case when item.eh_retorno then 1 else 0 end,atualizado_em=now()
    where id=item.corrida_id and estado='em_curso';
  if not found then raise exception using errcode='P0001',message='PISTA_RUN_NOT_RUNNING'; end if;
  -- A tentativa de retorno não usa a posição como um boi adicional.
  update public.pista_ops_positions set estado=case when item.eh_retorno then 'livre' else 'consumida' end,item_fila_id=null
    where rodada_id=item.rodada_id and item_fila_id=item.id and estado='ocupada';
  if not found then raise exception using errcode='P0001',message='PISTA_POSITION_RACE'; end if;
  update public.pista_ops_queue_items set estado='concluida' where id=item.id;
  return item.corrida_id;
end;
$$;

create or replace function public.pista_ops_atualizar_direito_segunda_corrida()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare second_run public.pista_ops_runs%rowtype; active_round_id uuid;
begin
  if new.numero_corrida<>1 or new.estado not in ('zero','valeu_boi') or new.estado=old.estado then return new; end if;
  select * into second_run from public.pista_ops_runs r where r.dupla_id=new.dupla_id and r.numero_corrida=2 for update;
  if not found then return new; end if;
  if new.estado='zero' then
    if old.estado='valeu_boi' and second_run.estado in ('em_curso','zero','valeu_boi') then
      raise exception using errcode='P0001',message='PISTA_SECOND_RUN_ALREADY_USED';
    end if;
    if second_run.estado in ('pendente','retorno_pendente') then
      update public.pista_ops_runs set estado='sem_direito',pontuacao=null,atualizado_em=now() where id=second_run.id;
      update public.pista_ops_queue_items set estado='encaminhada'
       where corrida_id=second_run.id and estado in ('na_fila','retorno_pendente','aguardando_proximo');
    end if;
    return new;
  end if;
  if second_run.estado='sem_direito' then
    update public.pista_ops_runs set estado='pendente',pontuacao=null,atualizado_em=now() where id=second_run.id;
  end if;
  -- Uma primeira corrida que voltou termina no rodízio atual, mas a segunda
  -- corrida só pode entrar na fila quando um novo rodízio for iniciado.
  if new.retornos_realizados>0 then return new; end if;
  select r.id into active_round_id from public.pista_ops_rounds r
   where r.evento_id=new.evento_id and r.categoria_id=new.categoria_id and r.estado='ativo'
   order by r.numero desc limit 1;
  if active_round_id is not null and second_run.estado in ('pendente','sem_direito') then
    update public.pista_ops_runs set rodada_atual_id=active_round_id,atualizado_em=now() where id=second_run.id;
    update public.pista_ops_queue_items set estado='na_fila'
      where rodada_id=active_round_id and corrida_id=second_run.id and estado='encaminhada';
    if not found then
      insert into public.pista_ops_queue_items(rodada_id,dupla_id,corrida_id,tipo,estado,eh_retorno,competidor_real_id)
       values(active_round_id,second_run.dupla_id,second_run.id,'regular','na_fila',false,second_run.competidor_real_id)
       on conflict(rodada_id,corrida_id) where tipo='regular' do nothing;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.pista_ops_liberar_retorno(uuid) from public,anon;
revoke all on function public.pista_ops_chamar_proxima(uuid,uuid) from public,anon;
revoke all on function public.pista_ops_registrar_resultado(uuid,text,numeric) from public,anon;
revoke all on function public.pista_ops_atualizar_direito_segunda_corrida() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
