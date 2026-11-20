begin;

create or replace function public.pista_ops_boi_tv_solicitar(p_corrida_id uuid,p_tipo text,p_reclamante_dupla_id uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_run public.pista_ops_runs%rowtype; v_actor uuid; v_review uuid;
begin
 select * into v_run from public.pista_ops_runs where id=p_corrida_id;
 if not found then raise exception using errcode='P0001',message='PISTA_RUN_NOT_FOUND'; end if;
 v_actor:=public.pista_ops_check_access(v_run.evento_id,array['locutor']);
 perform public.pista_ops_lock_category(v_run.evento_id,v_run.categoria_id);
 select * into v_run from public.pista_ops_runs where id=p_corrida_id for update;
 if not coalesce((select s.boi_tv from public.pista_ops_settings s where s.evento_id=v_run.evento_id),false) then
  raise exception using errcode='P0001',message='PISTA_TV_DISABLED';
 end if;
 if p_tipo is null or p_tipo not in ('a_favor','contra_terceiro') then raise exception using errcode='22023',message='PISTA_TV_REQUEST_TYPE_INVALID'; end if;
 if v_run.estado not in ('zero','valeu_boi') then raise exception using errcode='P0001',message='PISTA_TV_RUN_NOT_FINAL'; end if;
 if not exists(select 1 from public.duplas d where d.id=p_reclamante_dupla_id and d.evento_id=v_run.evento_id and d.categoria_id=v_run.categoria_id and d.status_pagamento is distinct from 'cancelado') then
  raise exception using errcode='P0001',message='PISTA_TV_CLAIMANT_INVALID'; end if;
 if p_reclamante_dupla_id is null or
    (p_tipo='a_favor' and (v_run.estado<>'zero' or p_reclamante_dupla_id<>v_run.dupla_id)) or
    (p_tipo='contra_terceiro' and (v_run.estado<>'valeu_boi' or p_reclamante_dupla_id=v_run.dupla_id)) then
  raise exception using errcode='P0001',message='PISTA_TV_REQUEST_DOES_NOT_MATCH_RESULT'; end if;
 if exists(select 1 from public.pista_ops_boi_tv_reviews r where r.corrida_id=v_run.id and r.estado='em_analise') then
  raise exception using errcode='P0001',message='PISTA_TV_REVIEW_PENDING'; end if;
 insert into public.pista_ops_boi_tv_reviews(corrida_id,evento_id,categoria_id,tipo_solicitacao,reclamante_dupla_id,resultado_inicial,pontuacao_inicial,solicitada_por)
 values(v_run.id,v_run.evento_id,v_run.categoria_id,p_tipo,p_reclamante_dupla_id,v_run.estado,v_run.pontuacao,v_actor) returning id into v_review;
 return v_review;
end $$;

create or replace function public.x1_solicitar_revisao(p_boi_id uuid,p_tipo text,p_reclamante_dupla_id uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_event uuid; v_actor uuid; v_id uuid; v_b public.x1_bois%rowtype; v_m public.x1_matches%rowtype; v_next uuid;
begin
 select b.* into v_b from public.x1_bois b where b.id=p_boi_id;
 if not found then raise exception 'X1_RUN_NOT_FOUND'; end if;
 select evento_id into v_event from public.x1_matches where id=v_b.confronto_id;
 v_actor:=public.pista_ops_check_access(v_event,array['locutor']);
 if not coalesce((select s.boi_tv from public.pista_ops_settings s where s.evento_id=v_event),false) then raise exception 'PISTA_TV_DISABLED'; end if;
 if p_tipo is null or p_tipo not in ('a_favor','contra_terceiro') then raise exception 'X1_REVIEW_TYPE_INVALID'; end if;
 if p_reclamante_dupla_id is null or
    (p_tipo='a_favor' and (v_b.resultado<>'zero' or p_reclamante_dupla_id<>v_b.dupla_id)) or
    (p_tipo='contra_terceiro' and (v_b.resultado<>'valeu' or p_reclamante_dupla_id is null or p_reclamante_dupla_id=v_b.dupla_id)) then
  raise exception 'X1_REVIEW_TYPE_RESULT_MISMATCH'; end if;
 if p_reclamante_dupla_id is null or p_reclamante_dupla_id not in (
   select lado_a from public.x1_matches where id=v_b.confronto_id
   union select lado_b from public.x1_matches where id=v_b.confronto_id
  ) then raise exception 'X1_REVIEW_CLAIMANT_INVALID'; end if;
 if v_b.registrado_em<now()-interval '5 minutes' then raise exception 'X1_REVIEW_EXPIRED'; end if;
 select * into v_m from public.x1_matches where id=v_b.confronto_id;
 if v_m.vencedor_id is not null then
  select id into v_next from public.x1_matches where chave_id=v_m.chave_id and fase=v_m.fase+1 and posicao=(v_m.posicao+1)/2;
  if v_next is not null and exists(select 1 from public.x1_bois where confronto_id=v_next) then raise exception 'X1_REVIEW_TOO_LATE'; end if;
 end if;
 insert into public.x1_revisoes(boi_id,solicitante,tipo_solicitacao,reclamante_dupla_id)
 values(p_boi_id,v_actor,p_tipo,p_reclamante_dupla_id) returning id into v_id;
 update public.x1_matches set estado='revisao' where id=v_b.confronto_id;
 return v_id;
end $$;

create or replace function public.pista_ops_boi_tv_solicitar_com_origem(
  p_corrida_id uuid, p_tipo text, p_reclamante_dupla_id uuid, p_origem text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_id uuid;
begin
  if p_origem is distinct from 'locucao' then
    raise exception using errcode='22023',message='PISTA_TV_ORIGIN_INVALID';
  end if;
  perform set_config('app.boi_tv_origin',p_origem,true);
  v_id := public.pista_ops_boi_tv_solicitar(p_corrida_id,p_tipo,p_reclamante_dupla_id);
  update public.pista_ops_boi_tv_reviews set origem=p_origem where id=v_id;
  return v_id;
end;
$$;

create or replace function public.x1_solicitar_revisao_com_origem(
  p_boi_id uuid, p_tipo text, p_reclamante_dupla_id uuid, p_origem text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_id uuid;
begin
  if p_origem is distinct from 'x1' then
    raise exception using errcode='22023',message='X1_REVIEW_ORIGIN_INVALID';
  end if;
  perform set_config('app.boi_tv_origin',p_origem,true);
  v_id := public.x1_solicitar_revisao(p_boi_id,p_tipo,p_reclamante_dupla_id);
  update public.x1_revisoes set origem=p_origem where id=v_id;
  return v_id;
end;
$$;

revoke execute on function public.pista_ops_boi_tv_solicitar(uuid,text,uuid),
  public.x1_solicitar_revisao(uuid,text,uuid) from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;
