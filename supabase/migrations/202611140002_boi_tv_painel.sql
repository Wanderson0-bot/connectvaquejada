begin;

alter table public.pista_ops_settings
  add column boi_tv boolean not null default false;

create table public.pista_ops_boi_tv_reviews (
  id uuid primary key default gen_random_uuid(),
  corrida_id uuid not null references public.pista_ops_runs(id) on delete restrict,
  evento_id uuid not null references public.eventos(id) on delete restrict,
  categoria_id uuid not null references public.categorias(id) on delete restrict,
  tipo_solicitacao text not null check (tipo_solicitacao in ('a_favor','contra_terceiro')),
  reclamante_dupla_id uuid not null references public.duplas(id) on delete restrict,
  resultado_inicial text not null check (resultado_inicial in ('zero','valeu_boi')),
  pontuacao_inicial numeric(12,3),
  estado text not null default 'em_analise' check (estado in ('em_analise','decidido')),
  resultado_alternativa text check (resultado_alternativa in ('zero','valeu_boi')),
  pontuacao_alternativa numeric(12,3),
  solicitada_por uuid not null references public.perfis(id) on delete restrict,
  solicitada_em timestamptz not null default now(),
  julgada_por uuid references public.perfis(id) on delete restrict,
  julgada_em timestamptz,
  justificativa text,
  constraint pista_ops_tv_review_score_ck check (
    (resultado_inicial='zero' and pontuacao_inicial=0) or
    (resultado_inicial='valeu_boi' and pontuacao_inicial is not null and pontuacao_inicial>=0)
  ),
  constraint pista_ops_tv_alternative_score_ck check (
    (resultado_alternativa is null and pontuacao_alternativa is null) or
    (resultado_alternativa='zero' and pontuacao_alternativa=0) or
    (resultado_alternativa='valeu_boi' and pontuacao_alternativa is not null and pontuacao_alternativa>=0)
  ),
  constraint pista_ops_tv_decision_fields_ck check (
    (estado='em_analise' and resultado_alternativa is null and julgada_por is null and julgada_em is null and justificativa is null)
    or (estado='decidido' and resultado_alternativa is not null and julgada_por is not null and julgada_em is not null and length(btrim(justificativa))>=3)
  )
);
create unique index pista_ops_tv_one_pending_review_uq
  on public.pista_ops_boi_tv_reviews(corrida_id) where estado='em_analise';
create index pista_ops_tv_event_category_idx
  on public.pista_ops_boi_tv_reviews(evento_id,categoria_id,solicitada_em desc);
alter table public.pista_ops_boi_tv_reviews enable row level security;

create or replace function public.pista_ops_boi_tv_configurar(p_evento_id uuid,p_habilitado boolean)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_actor uuid;
begin
 v_actor:=public.pista_ops_check_access(p_evento_id,array['organizador']);
 if p_habilitado is null then raise exception using errcode='22023',message='PISTA_TV_VALUE_REQUIRED'; end if;
 insert into public.pista_ops_settings(evento_id,permite_substituicao,boi_tv,atualizado_por)
 values(p_evento_id,false,p_habilitado,v_actor)
 on conflict(evento_id) do update set boi_tv=excluded.boi_tv,atualizado_em=now(),atualizado_por=excluded.atualizado_por;
 return p_habilitado;
end $$;

create or replace function public.pista_ops_boi_tv_habilitado(p_evento_id uuid)
returns boolean language plpgsql stable security definer set search_path=pg_catalog,public,auth,pg_temp as $$
begin
 perform public.pista_ops_check_access(p_evento_id,array['organizador','escritorio','locutor']);
 return coalesce((select s.boi_tv from public.pista_ops_settings s where s.evento_id=p_evento_id),false);
end $$;

-- Older installations may never have had the one-argument overload.
drop function if exists public.pista_ops_boi_tv_solicitar(uuid);
create or replace function public.pista_ops_boi_tv_solicitar(p_corrida_id uuid,p_tipo text,p_reclamante_dupla_id uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_run public.pista_ops_runs%rowtype; v_actor uuid; v_review uuid;
begin
 select * into v_run from public.pista_ops_runs where id=p_corrida_id;
 if not found then raise exception using errcode='P0001',message='PISTA_RUN_NOT_FOUND'; end if;
 v_actor:=public.pista_ops_check_access(v_run.evento_id,array['organizador','escritorio']);
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

create or replace function public.pista_ops_boi_tv_decidir(
 p_revisao_id uuid,p_resultado text,p_pontuacao numeric,p_justificativa text
) returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_review public.pista_ops_boi_tv_reviews%rowtype; v_run public.pista_ops_runs%rowtype; v_actor uuid;
begin
 select * into v_review from public.pista_ops_boi_tv_reviews where id=p_revisao_id;
 if not found then raise exception using errcode='P0001',message='PISTA_TV_REVIEW_NOT_FOUND'; end if;
 v_actor:=public.pista_ops_check_access(v_review.evento_id,array['organizador']);
 perform public.pista_ops_lock_category(v_review.evento_id,v_review.categoria_id);
 select * into v_review from public.pista_ops_boi_tv_reviews where id=p_revisao_id for update;
 if v_review.estado<>'em_analise' then raise exception using errcode='P0001',message='PISTA_TV_REVIEW_CLOSED'; end if;
 if p_resultado not in ('zero','valeu_boi') or
    (p_resultado='zero' and p_pontuacao is distinct from 0::numeric) or
    (p_resultado='valeu_boi' and (p_pontuacao is null or p_pontuacao<0 or p_pontuacao>40)) or
    length(btrim(coalesce(p_justificativa,'')))<3 then
  raise exception using errcode='22023',message='PISTA_TV_DECISION_INVALID';
 end if;
 select * into v_run from public.pista_ops_runs where id=v_review.corrida_id for update;
 if v_run.estado not in ('zero','valeu_boi') then raise exception using errcode='P0001',message='PISTA_TV_RUN_CHANGED'; end if;
 if v_run.estado<>p_resultado or v_run.pontuacao is distinct from p_pontuacao then
  insert into public.pista_ops_result_corrections(corrida_id,resultado_anterior,pontuacao_anterior,resultado_novo,pontuacao_nova,autor_id,justificativa)
  values(v_run.id,v_run.estado,v_run.pontuacao,p_resultado,p_pontuacao,v_actor,'Boi de TV: '||btrim(p_justificativa));
  update public.pista_ops_runs set estado=p_resultado,pontuacao=p_pontuacao,atualizado_em=now() where id=v_run.id;
 end if;
 update public.pista_ops_boi_tv_reviews set estado='decidido',resultado_alternativa=p_resultado,
  pontuacao_alternativa=p_pontuacao,julgada_por=v_actor,julgada_em=now(),justificativa=btrim(p_justificativa)
 where id=p_revisao_id;
 return v_review.corrida_id;
end $$;

create or replace function public.pista_ops_boi_tv_estado(p_evento_id uuid,p_categoria_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_state jsonb;
begin
 perform public.pista_ops_check_access(p_evento_id,array['organizador','escritorio','locutor']);
 if not exists(select 1 from public.categorias c where c.id=p_categoria_id and c.evento_id=p_evento_id) then
  raise exception using errcode='P0001',message='PISTA_CATEGORY_NOT_FOUND'; end if;
 select jsonb_build_object(
  'habilitado',coalesce((select s.boi_tv from public.pista_ops_settings s where s.evento_id=p_evento_id),false),
  'revisoes',coalesce((select jsonb_agg(jsonb_build_object(
    'id',r.id,'corrida_id',r.corrida_id,'estado',r.estado,'resultado_inicial',r.resultado_inicial,'pontuacao_inicial',r.pontuacao_inicial,
    'resultado_alternativa',r.resultado_alternativa,'pontuacao_alternativa',r.pontuacao_alternativa,
    'senha',d.numero_senha,'numero_corrida',run.numero_corrida,'vaqueiro',c.nome,
    'tipo_solicitacao',r.tipo_solicitacao,'reclamante_dupla_id',r.reclamante_dupla_id,'reclamante_senha',rd.numero_senha,'reclamante',rc.nome,
    'solicitada_em',r.solicitada_em,'julgada_em',r.julgada_em,'justificativa',r.justificativa
  ) order by (r.estado='em_analise') desc,r.solicitada_em desc)
    from public.pista_ops_boi_tv_reviews r join public.pista_ops_runs run on run.id=r.corrida_id
    join public.duplas d on d.id=run.dupla_id left join public.competidores c on c.id=coalesce(run.competidor_real_id,d.puxador_id)
    join public.duplas rd on rd.id=r.reclamante_dupla_id left join public.competidores rc on rc.id=rd.puxador_id
    where r.evento_id=p_evento_id and r.categoria_id=p_categoria_id),'[]'::jsonb)
 ) into v_state;
 return v_state;
end $$;

alter table public.x1_revisoes
  add column tipo_solicitacao text not null default 'a_favor' check(tipo_solicitacao in ('a_favor','contra_terceiro')),
  add column reclamante_dupla_id uuid references public.duplas(id) on delete restrict;

create or replace function public.x1_estado(p_evento_id uuid,p_categoria_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_actor uuid; v_result jsonb;
begin
 v_actor:=public.pista_ops_check_access(p_evento_id,array['organizador','escritorio','locutor']);
 select jsonb_build_object(
   'bracket',(select to_jsonb(b) from public.x1_brackets b where b.evento_id=p_evento_id and b.categoria_id=p_categoria_id),
   'inscricoes',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'senha',d.numero_senha,'nome',c.nome,'equipe',d.nome_equipe) order by d.numero_senha)
    from public.duplas d join public.competidores c on c.id=d.puxador_id where d.evento_id=p_evento_id and d.categoria_id=p_categoria_id and d.status_pagamento in ('pago','isento')),'[]'::jsonb),
   'confrontos',coalesce((select jsonb_agg(jsonb_build_object(
    'id',m.id,'fase',m.fase,'posicao',m.posicao,'estado',m.estado,'lado_a',m.lado_a,'lado_b',m.lado_b,'vencedor',m.vencedor_id,
    'nome_a',ca.nome,'nome_b',cb.nome,
    'bois',coalesce((select jsonb_agg(jsonb_build_object('id',boi.id,'numero',boi.numero,'lado',boi.lado,'dupla_id',boi.dupla_id,
      'resultado',coalesce(r.resultado_final,boi.resultado),'revisao',r.estado,'revisao_id',r.id,'prazo',r.prazo,
      'tipo_solicitacao',r.tipo_solicitacao,'reclamante_dupla_id',r.reclamante_dupla_id,'reclamante',rc.nome)
      order by boi.numero) from public.x1_bois boi left join public.x1_revisoes r on r.boi_id=boi.id
      left join public.duplas rd on rd.id=r.reclamante_dupla_id left join public.competidores rc on rc.id=rd.puxador_id
      where boi.confronto_id=m.id),'[]'::jsonb)) order by m.fase,m.posicao)
    from public.x1_matches m left join public.duplas da on da.id=m.lado_a left join public.competidores ca on ca.id=da.puxador_id
     left join public.duplas db on db.id=m.lado_b left join public.competidores cb on cb.id=db.puxador_id
    where m.evento_id=p_evento_id and m.categoria_id=p_categoria_id),'[]'::jsonb)
 ) into v_result;
 return v_result;
end $$;

drop function public.x1_solicitar_revisao(uuid);
create or replace function public.x1_solicitar_revisao(p_boi_id uuid,p_tipo text,p_reclamante_dupla_id uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_event uuid; v_actor uuid; v_id uuid; v_b public.x1_bois%rowtype; v_m public.x1_matches%rowtype; v_next uuid;
begin
 select b.* into v_b from public.x1_bois b where b.id=p_boi_id;
 if not found then raise exception 'X1_RUN_NOT_FOUND'; end if;
 select evento_id into v_event from public.x1_matches where id=v_b.confronto_id;
 v_actor:=public.pista_ops_check_access(v_event,array['organizador','escritorio','locutor']);
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

revoke all on function public.pista_ops_boi_tv_configurar(uuid,boolean),public.pista_ops_boi_tv_habilitado(uuid),public.pista_ops_boi_tv_solicitar(uuid,text,uuid),public.pista_ops_boi_tv_decidir(uuid,text,numeric,text),public.pista_ops_boi_tv_estado(uuid,uuid),public.x1_solicitar_revisao(uuid, text, uuid) from public,anon;
grant execute on function public.pista_ops_boi_tv_configurar(uuid,boolean),public.pista_ops_boi_tv_habilitado(uuid),public.pista_ops_boi_tv_solicitar(uuid,text,uuid),public.pista_ops_boi_tv_decidir(uuid,text,numeric,text),public.pista_ops_boi_tv_estado(uuid,uuid),public.x1_solicitar_revisao(uuid, text, uuid) to authenticated;
notify pgrst,'reload schema';
commit;
