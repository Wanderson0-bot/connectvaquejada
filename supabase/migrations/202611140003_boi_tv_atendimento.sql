begin;

-- A pista currently stores one score per corrida. It has no reliable bull number.
-- Keep this nullable; older records remain unknown until a source supplies it.
alter table public.pista_ops_runs
  add column numero_boi smallint check (numero_boi is null or numero_boi > 0);

-- Capture the source on the official review rows, without changing their state
-- machine or decision semantics. Existing callers default to the office.
alter table public.pista_ops_boi_tv_reviews
  add column origem text not null default 'escritorio'
    check (origem in ('escritorio','locucao','apresentacao','x1'));
alter table public.x1_revisoes
  add column origem text not null default 'x1'
    check (origem in ('escritorio','locucao','apresentacao','x1'));

create table public.pista_ops_boi_tv_atendimentos (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.eventos(id) on delete restrict,
  categoria_id uuid not null references public.categorias(id) on delete restrict,
  revisao_pista_id uuid references public.pista_ops_boi_tv_reviews(id) on delete restrict,
  revisao_x1_id uuid references public.x1_revisoes(id) on delete restrict,
  origem text not null check (origem in ('escritorio','locucao','apresentacao','x1')),
  estado_atendimento text not null default 'nova' check (estado_atendimento in (
    'nova','recebida','em_analise','analise_concluida','aguardando_decisao','finalizada'
  )),
  dados_apresentacao jsonb not null default '{}'::jsonb,
  recebida_por uuid references public.perfis(id) on delete restrict,
  recebida_em timestamptz,
  operador_id uuid references public.perfis(id) on delete restrict,
  analise_concluida_por uuid references public.perfis(id) on delete restrict,
  analise_concluida_em timestamptz,
  observacao_operacional text check (observacao_operacional is null or length(observacao_operacional)<=2000),
  atualizada_em timestamptz not null default now(),
  criada_em timestamptz not null default now(),
  constraint pista_ops_boi_tv_atendimento_source_ck check (
    num_nonnulls(revisao_pista_id, revisao_x1_id) = 1
  ),
  constraint pista_ops_boi_tv_atendimento_received_ck check (
    (recebida_por is null and recebida_em is null)
    or (recebida_por is not null and recebida_em is not null)
  ),
  constraint pista_ops_boi_tv_atendimento_analysis_ck check (
    (analise_concluida_por is null and analise_concluida_em is null)
    or (analise_concluida_por is not null and analise_concluida_em is not null)
  )
);
create unique index pista_ops_boi_tv_atendimento_pista_uq
  on public.pista_ops_boi_tv_atendimentos(revisao_pista_id) where revisao_pista_id is not null;
create unique index pista_ops_boi_tv_atendimento_x1_uq
  on public.pista_ops_boi_tv_atendimentos(revisao_x1_id) where revisao_x1_id is not null;
create index pista_ops_boi_tv_atendimento_event_queue_idx
  on public.pista_ops_boi_tv_atendimentos(evento_id, criada_em desc);
create index pista_ops_boi_tv_atendimento_pending_idx
  on public.pista_ops_boi_tv_atendimentos(evento_id, estado_atendimento, criada_em)
  where estado_atendimento <> 'finalizada';

alter table public.pista_ops_boi_tv_atendimentos enable row level security;
revoke all on public.pista_ops_boi_tv_atendimentos from public, anon, authenticated;
grant select on public.pista_ops_boi_tv_atendimentos to authenticated;

create or replace function public.pista_ops_boi_tv_pode_ver_evento(p_evento_id uuid)
returns boolean language sql stable security definer
set search_path=pg_catalog,public,auth,pg_temp as $$
  select exists (
    select 1 from public.pista_ops_devices d
     join public.pista_ops_settings s on s.evento_id=d.evento_id and s.boi_tv
     join public.eventos e on e.id=d.evento_id and e.status_operacional='em_andamento'
     where d.evento_id=p_evento_id and d.usuario_auth_id=auth.uid()
       and d.funcao='boi_tv' and d.estado='ativo'
       and exists(select 1 from public.pista_ops_members m where m.evento_id=d.evento_id
         and m.usuario_id=d.concedido_por and m.funcao='organizador' and m.ativo)
  ) or exists (
    select 1 from public.pista_ops_members m
    join public.eventos e on e.id=m.evento_id
    join public.pista_ops_settings s on s.evento_id=e.id and s.boi_tv
    join public.perfis p on p.id=auth.uid() and p.parque_id=e.parque_id
     where m.evento_id=p_evento_id and m.usuario_id=auth.uid() and m.ativo
       and m.funcao in ('organizador','escritorio','locutor')
  );
$$;

create policy pista_ops_boi_tv_atendimento_event_access
  on public.pista_ops_boi_tv_atendimentos for select to authenticated
  using (public.pista_ops_boi_tv_pode_ver_evento(evento_id));

create or replace function public.pista_ops_boi_tv_atendimento_snapshot_pista(p_review_id uuid)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public, auth, pg_temp as $$
  select jsonb_build_object(
    'tipo_fonte','pista', 'revisao_id', r.id, 'corrida_id', run.id,
    'evento_id', e.id, 'evento', e.nome, 'categoria_id', cat.id, 'categoria', cat.nome,
    'competidor', comp.nome, 'senha', d.numero_senha,
    'equipe', d.nome_equipe, 'cavalo', d.nome_cavalo,
    'numero_boi', run.numero_boi, 'numero_corrida', run.numero_corrida,
    'rodizio', rodada.numero, 'tipo_solicitacao', r.tipo_solicitacao,
    'resultado_original', r.resultado_inicial, 'pontuacao_original', r.pontuacao_inicial,
    'solicitante_id', r.solicitada_por, 'solicitado_em', r.solicitada_em,
    'origem', r.origem
  )
  from public.pista_ops_boi_tv_reviews r
  join public.pista_ops_runs run on run.id = r.corrida_id
  join public.eventos e on e.id = r.evento_id
  join public.categorias cat on cat.id = r.categoria_id
  join public.duplas d on d.id = run.dupla_id
  left join public.competidores comp on comp.id = coalesce(run.competidor_real_id, d.puxador_id)
  left join public.pista_ops_rounds rodada on rodada.id = run.rodada_atual_id
  where r.id = p_review_id;
$$;

create or replace function public.pista_ops_boi_tv_atendimento_capture_pista()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, auth, pg_temp as $$
begin
  insert into public.pista_ops_boi_tv_atendimentos
    (evento_id,categoria_id,revisao_pista_id,origem,dados_apresentacao)
  values
    (new.evento_id,new.categoria_id,new.id,new.origem,
     public.pista_ops_boi_tv_atendimento_snapshot_pista(new.id))
  on conflict (revisao_pista_id) where revisao_pista_id is not null do nothing;
  return new;
end;
$$;
create trigger pista_ops_boi_tv_atendimento_capture_pista_trg
  after insert on public.pista_ops_boi_tv_reviews
  for each row execute function public.pista_ops_boi_tv_atendimento_capture_pista();

create or replace function public.pista_ops_boi_tv_atendimento_snapshot_x1(p_review_id uuid)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public, auth, pg_temp as $$
  select jsonb_build_object(
    'tipo_fonte','x1', 'revisao_id', r.id, 'boi_id', b.id,
    'evento_id', m.evento_id, 'evento', e.nome, 'categoria_id', m.categoria_id, 'categoria', cat.nome,
    'competidor', comp.nome, 'senha', d.numero_senha, 'equipe', d.nome_equipe,
    'cavalo', d.nome_cavalo, 'numero_boi', b.numero, 'numero_corrida', null,
    'rodizio', null, 'tipo_solicitacao', r.tipo_solicitacao,
    'resultado_original', b.resultado, 'pontuacao_original', null,
    'solicitante_id', r.solicitante, 'solicitado_em', r.criado_em,
    'origem', r.origem
  )
  from public.x1_revisoes r
  join public.x1_bois b on b.id = r.boi_id
  join public.x1_matches m on m.id = b.confronto_id
  join public.eventos e on e.id = m.evento_id
  join public.categorias cat on cat.id = m.categoria_id
  join public.duplas d on d.id = b.dupla_id
  left join public.competidores comp on comp.id = d.puxador_id
  where r.id = p_review_id;
$$;

create or replace function public.pista_ops_boi_tv_atendimento_capture_x1()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, auth, pg_temp as $$
declare v_event uuid; v_category uuid; v_snapshot jsonb;
begin
  select m.evento_id,m.categoria_id into v_event,v_category
    from public.x1_bois b join public.x1_matches m on m.id=b.confronto_id
   where b.id=new.boi_id;
  v_snapshot := public.pista_ops_boi_tv_atendimento_snapshot_x1(new.id);
  insert into public.pista_ops_boi_tv_atendimentos
    (evento_id,categoria_id,revisao_x1_id,origem,dados_apresentacao)
  values (v_event,v_category,new.id,new.origem,v_snapshot)
  on conflict (revisao_x1_id) where revisao_x1_id is not null do nothing;
  return new;
end;
$$;
create trigger pista_ops_boi_tv_atendimento_capture_x1_trg
  after insert on public.x1_revisoes
  for each row execute function public.pista_ops_boi_tv_atendimento_capture_x1();

create or replace function public.pista_ops_boi_tv_atendimento_estado(p_evento_id uuid)
returns setof public.pista_ops_boi_tv_atendimentos language plpgsql stable security definer
set search_path = pg_catalog, public, auth, pg_temp as $$
begin
  if not public.pista_ops_boi_tv_pode_ver_evento(p_evento_id) then
    raise exception using errcode='42501',message='PISTA_TV_EVENT_ACCESS_REQUIRED';
  end if;
  return query select a.* from public.pista_ops_boi_tv_atendimentos a
   where a.evento_id=p_evento_id order by a.criada_em desc;
end;
$$;

create or replace function public.pista_ops_boi_tv_atendimento_atualizar(
  p_atendimento_id uuid, p_estado text
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth, pg_temp as $$
declare v_row public.pista_ops_boi_tv_atendimentos%rowtype; v_actor uuid;
begin
  select * into v_row from public.pista_ops_boi_tv_atendimentos where id=p_atendimento_id for update;
  if not found then raise exception using errcode='P0001',message='PISTA_TV_SERVICE_NOT_FOUND'; end if;
  if not exists (
    select 1 from public.pista_ops_devices d
     join public.pista_ops_settings s on s.evento_id=d.evento_id and s.boi_tv
     join public.eventos e on e.id=d.evento_id and e.status_operacional='em_andamento'
     where d.evento_id=v_row.evento_id and d.usuario_auth_id=auth.uid()
       and d.funcao='boi_tv' and d.estado='ativo'
       and exists(select 1 from public.pista_ops_members m where m.evento_id=d.evento_id
         and m.usuario_id=d.concedido_por and m.funcao='organizador' and m.ativo)
  ) then raise exception using errcode='42501',message='PISTA_TV_OPERATOR_REQUIRED'; end if;
  select d.concedido_por into v_actor from public.pista_ops_devices d
   where d.evento_id=v_row.evento_id and d.usuario_auth_id=auth.uid() and d.funcao='boi_tv' and d.estado='ativo';
  if p_estado not in ('recebida','em_analise','analise_concluida','aguardando_decisao') then
    raise exception using errcode='22023',message='PISTA_TV_SERVICE_STATE_INVALID';
  end if;
  if v_row.estado_atendimento='finalizada' then
    raise exception using errcode='P0001',message='PISTA_TV_SERVICE_CLOSED';
  end if;
  update public.pista_ops_boi_tv_atendimentos set
    estado_atendimento=p_estado,
    recebida_por=case when p_estado='recebida' then coalesce(recebida_por,v_actor) else recebida_por end,
    recebida_em=case when p_estado='recebida' then coalesce(recebida_em,now()) else recebida_em end,
    operador_id=case when p_estado in ('em_analise','analise_concluida','aguardando_decisao') then v_actor else operador_id end,
    analise_concluida_por=case when p_estado='analise_concluida' then v_actor else analise_concluida_por end,
    analise_concluida_em=case when p_estado='analise_concluida' then now() else analise_concluida_em end,
    atualizada_em=now()
  where id=p_atendimento_id;
  return p_atendimento_id;
end;
$$;

revoke all on function public.pista_ops_boi_tv_atendimento_snapshot_pista(uuid),
  public.pista_ops_boi_tv_atendimento_capture_pista(),
  public.pista_ops_boi_tv_atendimento_snapshot_x1(uuid),
  public.pista_ops_boi_tv_atendimento_capture_x1() from public,anon,authenticated;
revoke all on function public.pista_ops_boi_tv_pode_ver_evento(uuid) from public,anon;
grant execute on function public.pista_ops_boi_tv_pode_ver_evento(uuid) to authenticated;
revoke all on function public.pista_ops_boi_tv_atendimento_estado(uuid),
  public.pista_ops_boi_tv_atendimento_atualizar(uuid,text) from public,anon;
grant execute on function public.pista_ops_boi_tv_atendimento_estado(uuid),
  public.pista_ops_boi_tv_atendimento_atualizar(uuid,text) to authenticated;

notify pgrst, 'reload schema';
commit;
