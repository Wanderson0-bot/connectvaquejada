begin;

-- Keep the existing request RPCs as the source of truth. These wrappers add
-- request provenance in transaction-local context for the capture triggers.
create or replace function public.pista_ops_boi_tv_solicitar_com_origem(
  p_corrida_id uuid, p_tipo text, p_reclamante_dupla_id uuid, p_origem text
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_id uuid;
begin
  if p_origem not in ('escritorio','locucao','apresentacao') then
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
  if p_origem not in ('escritorio','locucao','apresentacao','x1') then
    raise exception using errcode='22023',message='X1_REVIEW_ORIGIN_INVALID';
  end if;
  perform set_config('app.boi_tv_origin',p_origem,true);
  v_id := public.x1_solicitar_revisao(p_boi_id,p_tipo,p_reclamante_dupla_id);
  update public.x1_revisoes set origem=p_origem where id=v_id;
  return v_id;
end;
$$;

create or replace function public.pista_ops_boi_tv_atendimento_capture_pista()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, auth, pg_temp as $$
declare v_origin text;
begin
  v_origin := coalesce(nullif(current_setting('app.boi_tv_origin',true),''),new.origem);
  insert into public.pista_ops_boi_tv_atendimentos
    (evento_id,categoria_id,revisao_pista_id,origem,dados_apresentacao)
  values
    (new.evento_id,new.categoria_id,new.id,v_origin,
     public.pista_ops_boi_tv_atendimento_snapshot_pista(new.id)
       || jsonb_build_object('origem',v_origin))
  on conflict (revisao_pista_id) where revisao_pista_id is not null do nothing;
  return new;
end;
$$;

create or replace function public.pista_ops_boi_tv_atendimento_capture_x1()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, auth, pg_temp as $$
declare v_event uuid; v_category uuid; v_snapshot jsonb; v_origin text;
begin
  select m.evento_id,m.categoria_id into v_event,v_category
    from public.x1_bois b join public.x1_matches m on m.id=b.confronto_id
   where b.id=new.boi_id;
  v_origin := coalesce(nullif(current_setting('app.boi_tv_origin',true),''),new.origem);
  v_snapshot := public.pista_ops_boi_tv_atendimento_snapshot_x1(new.id)
    || jsonb_build_object('origem',v_origin);
  insert into public.pista_ops_boi_tv_atendimentos
    (evento_id,categoria_id,revisao_x1_id,origem,dados_apresentacao)
  values (v_event,v_category,new.id,v_origin,v_snapshot)
  on conflict (revisao_x1_id) where revisao_x1_id is not null do nothing;
  return new;
end;
$$;

-- A pending X1 review no longer prevents the next bull from being recorded.
-- Results continue to be scored from the official initial value until a judge
-- resolves each review; the decision RPC then recomputes this exact match.
create or replace function public.x1_registrar_boi(p_confronto_id uuid,p_resultado text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare
 v_m public.x1_matches%rowtype; v_b uuid; v_actor uuid; v_n integer; v_lado smallint;
 v_dupla uuid; v_a integer; v_c integer; v_limite integer; v_winner uuid; v_next uuid;
 v_next_side text; v_pending boolean;
begin
 select * into v_m from public.x1_matches where id=p_confronto_id for update;
 if not found then raise exception 'X1_MATCH_NOT_FOUND'; end if;
 v_actor:=public.pista_ops_check_access(v_m.evento_id,array['organizador','locutor']);
 if p_resultado not in ('valeu','zero') or v_m.estado not in ('em_andamento','morte_subita','revisao') then raise exception 'X1_RESULT_INVALID'; end if;
 select count(*)+1 into v_n from public.x1_bois where confronto_id=v_m.id;
 v_lado:=case when v_n%2=1 then 1 else 2 end;
 v_dupla:=case when v_lado=1 then v_m.lado_a else v_m.lado_b end;
 insert into public.x1_bois(confronto_id,numero,lado,dupla_id,resultado,registrado_por)
 values(v_m.id,v_n,v_lado,v_dupla,p_resultado,v_actor) returning id into v_b;
 select exists(select 1 from public.x1_revisoes r join public.x1_bois b on b.id=r.boi_id
   where b.confronto_id=v_m.id and r.estado='aberta') into v_pending;
 if v_pending then
   update public.x1_matches set estado='revisao',vencedor_id=null where id=v_m.id;
   return v_b;
 end if;
 select count(*) filter(where coalesce(r.resultado_final,b.resultado)='valeu' and b.dupla_id=v_m.lado_a),
        count(*) filter(where coalesce(r.resultado_final,b.resultado)='valeu' and b.dupla_id=v_m.lado_b)
   into v_a,v_c from public.x1_bois b left join public.x1_revisoes r on r.boi_id=b.id where b.confronto_id=v_m.id;
 select melhor_de into v_limite from public.x1_brackets where id=v_m.chave_id;
 if v_n=v_limite*2 then
   if v_a>v_c then v_winner:=v_m.lado_a;
   elsif v_c>v_a then v_winner:=v_m.lado_b;
   else update public.x1_matches set estado='morte_subita' where id=v_m.id; end if;
 elsif v_n>v_limite*2 and v_n%2=0 and v_a<>v_c then
   v_winner:=case when v_a>v_c then v_m.lado_a else v_m.lado_b end;
 end if;
 if v_winner is not null then
   update public.x1_matches set estado='finalizada',vencedor_id=v_winner where id=v_m.id;
   select id into v_next from public.x1_matches where chave_id=v_m.chave_id and fase=v_m.fase+1 and posicao=(v_m.posicao+1)/2;
   if v_next is null then update public.x1_brackets set estado='finalizada' where id=v_m.chave_id;
   else
     v_next_side:=case when v_m.posicao%2=1 then 'lado_a' else 'lado_b' end;
     if v_next_side='lado_a' then update public.x1_matches set lado_a=v_winner where id=v_next;
     else update public.x1_matches set lado_b=v_winner where id=v_next; end if;
     update public.x1_matches set estado='em_andamento' where id=v_next and lado_a is not null and lado_b is not null;
   end if;
 end if;
 return v_b;
end $$;

-- Mark the service workflow complete only after the official decision closes.
create or replace function public.pista_ops_boi_tv_atendimento_finish_pista()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,auth,pg_temp as $$
begin
  if old.estado is distinct from new.estado and new.estado='decidido' then
    update public.pista_ops_boi_tv_atendimentos set estado_atendimento='finalizada',atualizada_em=now()
     where revisao_pista_id=new.id and estado_atendimento<>'finalizada';
  end if;
  return new;
end;
$$;
create trigger pista_ops_boi_tv_atendimento_finish_pista_trg
  after update of estado on public.pista_ops_boi_tv_reviews
  for each row execute function public.pista_ops_boi_tv_atendimento_finish_pista();

create or replace function public.pista_ops_boi_tv_atendimento_finish_x1()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,auth,pg_temp as $$
begin
  if old.estado is distinct from new.estado and new.estado in ('confirmada','alterada') then
    update public.pista_ops_boi_tv_atendimentos set estado_atendimento='finalizada',atualizada_em=now()
     where revisao_x1_id=new.id and estado_atendimento<>'finalizada';
  end if;
  return new;
end;
$$;
create trigger pista_ops_boi_tv_atendimento_finish_x1_trg
  after update of estado on public.x1_revisoes
  for each row execute function public.pista_ops_boi_tv_atendimento_finish_x1();

-- The locution position is the operational source for the bull number in the
-- pista flow. Persist it at first result entry; keep it null if no called item
-- has a position, and never infer it during later corrections.
create or replace function public.pista_ops_boi_tv_capture_bull_number()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,auth,pg_temp as $$
begin
  if old.estado='em_curso' and new.estado in ('zero','valeu_boi') and new.numero_boi is null then
    select p.numero_posicao into new.numero_boi
      from public.pista_ops_queue_items q
      join public.pista_ops_positions p on p.item_fila_id=q.id
     where q.corrida_id=new.id and q.estado='chamada'
     order by q.criado_em desc limit 1;
  end if;
  return new;
end;
$$;
create trigger pista_ops_boi_tv_capture_bull_number_trg
  before update of estado on public.pista_ops_runs
  for each row execute function public.pista_ops_boi_tv_capture_bull_number();

revoke all on function public.pista_ops_boi_tv_solicitar_com_origem(uuid,text,uuid,text),
  public.x1_solicitar_revisao_com_origem(uuid,text,uuid,text),
  public.pista_ops_boi_tv_atendimento_finish_pista(),
  public.pista_ops_boi_tv_atendimento_finish_x1(),
  public.pista_ops_boi_tv_capture_bull_number() from public,anon,authenticated;
grant execute on function public.pista_ops_boi_tv_solicitar_com_origem(uuid,text,uuid,text),
  public.x1_solicitar_revisao_com_origem(uuid,text,uuid,text) to authenticated;

notify pgrst, 'reload schema';
commit;
