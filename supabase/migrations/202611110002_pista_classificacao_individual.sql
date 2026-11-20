begin;

create or replace function public.pista_ops_substituir_dupla(
  p_item_fila_id uuid,
  p_competidor_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  item public.pista_ops_queue_items%rowtype;
  target_round public.pista_ops_rounds%rowtype;
  actor_id uuid;
begin
  select q.* into item
    from public.pista_ops_queue_items q
   where q.id = p_item_fila_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'PISTA_QUEUE_ITEM_NOT_FOUND';
  end if;

  select r.* into target_round
    from public.pista_ops_rounds r
   where r.id = item.rodada_id;
  actor_id := public.pista_ops_check_access(target_round.evento_id, array['organizador']);
  perform public.pista_ops_lock_category(target_round.evento_id, target_round.categoria_id);

  if not coalesce((
    select s.permite_substituicao
      from public.pista_ops_settings s
     where s.evento_id = target_round.evento_id
  ), false) then
    raise exception using errcode = 'P0001', message = 'PISTA_SUBSTITUTION_DISABLED';
  end if;

  if not exists (
    select 1
      from public.competidores c
      join public.eventos e on e.id = target_round.evento_id
     where c.id = p_competidor_id
       and (
         (e.operacao_temporaria and c.evento_id = e.id)
         or (not e.operacao_temporaria and c.parque_id = e.parque_id)
       )
  ) then
    raise exception using errcode = '42501', message = 'PISTA_SUBSTITUTE_PARK_MISMATCH';
  end if;

  update public.pista_ops_queue_items
     set competidor_real_id = p_competidor_id
   where id = p_item_fila_id
     and estado in ('na_fila', 'chamada', 'retorno_pendente', 'aguardando_proximo');
  if not found then
    raise exception using errcode = 'P0001', message = 'PISTA_SUBSTITUTION_STATE_INVALID';
  end if;

  if item.corrida_id is not null then
    update public.pista_ops_runs
       set competidor_real_id = p_competidor_id, atualizado_em = now()
     where id = item.corrida_id
       and estado in ('pendente', 'retorno_pendente', 'em_curso');
  end if;
  return p_competidor_id;
end;
$$;

create or replace function public.pista_ops_competidores(p_evento_id uuid)
returns table(id uuid, nome text)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  event_row public.eventos%rowtype;
begin
  perform public.pista_ops_check_access(p_evento_id, array['organizador']);
  select e.* into event_row from public.eventos e where e.id = p_evento_id;
  if not found then
    raise exception using errcode = '42501', message = 'PISTA_EVENT_NOT_FOUND';
  end if;

  return query
  select c.id, c.nome
    from public.competidores c
   where (event_row.operacao_temporaria and c.evento_id = p_evento_id)
      or (not event_row.operacao_temporaria and c.parque_id = event_row.parque_id)
   order by c.nome, c.id;
end;
$$;

create or replace function public.pista_ops_classificacao(
  p_evento_id uuid,
  p_categoria_id uuid,
  p_rodizio_id uuid,
  p_escopo text
)
returns table(posicao bigint, competidor_id uuid, competidor_nome text, pontuacao numeric, corridas bigint)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
begin
  perform public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio', 'locutor']);

  if p_escopo is null or p_escopo not in ('parcial', 'geral')
    or not exists (
      select 1 from public.categorias c
       where c.id = p_categoria_id and c.evento_id = p_evento_id
    ) then
    raise exception using errcode = '22023', message = 'PISTA_CLASSIFICATION_SCOPE_INVALID';
  end if;

  if p_escopo = 'parcial' and not exists (
    select 1 from public.pista_ops_rounds r
     where r.id = p_rodizio_id
       and r.evento_id = p_evento_id
       and r.categoria_id = p_categoria_id
  ) then
    raise exception using errcode = '22023', message = 'PISTA_CLASSIFICATION_ROUND_INVALID';
  end if;

  return query
  with scores as (
    select coalesce(run.competidor_real_id, d.puxador_id) as competitor_id,
           sum(run.pontuacao)::numeric as total_score,
           count(*)::bigint as run_count
      from public.pista_ops_runs run
      join public.duplas d on d.id = run.dupla_id
     where run.evento_id = p_evento_id
       and run.categoria_id = p_categoria_id
       and run.estado in ('zero', 'valeu_boi')
       and (p_escopo = 'geral' or run.rodada_atual_id = p_rodizio_id)
       and d.status_pagamento is distinct from 'cancelado'
     group by coalesce(run.competidor_real_id, d.puxador_id)
  ), ranked as (
    select dense_rank() over (order by scores.total_score desc) as position,
           scores.competitor_id,
           c.nome,
           scores.total_score,
           scores.run_count
      from scores
      join public.competidores c on c.id = scores.competitor_id
  )
  select ranked.position, ranked.competitor_id, ranked.nome, ranked.total_score, ranked.run_count
    from ranked
   order by ranked.total_score desc, ranked.nome, ranked.competitor_id;
end;
$$;

revoke all on function public.pista_ops_competidores(uuid) from public, anon;
revoke all on function public.pista_ops_classificacao(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.pista_ops_competidores(uuid) to authenticated;
grant execute on function public.pista_ops_classificacao(uuid, uuid, uuid, text) to authenticated;

notify pgrst, 'reload schema';
commit;
