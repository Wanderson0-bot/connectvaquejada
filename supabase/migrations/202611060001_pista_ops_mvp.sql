begin;

do $$
declare
  required_column record;
  actual_type text;
begin
  if to_regclass('public.perfis') is null
    or to_regclass('public.eventos') is null
    or to_regclass('public.categorias') is null
    or to_regclass('public.duplas') is null
    or to_regclass('public.competidores') is null then
    raise exception 'Pista ops preflight: required local tables are missing';
  end if;

  for required_column in
    select * from (values
      ('perfis', 'id', 'uuid'),
      ('perfis', 'parque_id', 'uuid'),
      ('eventos', 'id', 'uuid'),
      ('eventos', 'parque_id', 'uuid'),
      ('categorias', 'id', 'uuid'),
      ('categorias', 'evento_id', 'uuid'),
      ('duplas', 'id', 'uuid'),
      ('duplas', 'evento_id', 'uuid'),
      ('duplas', 'categoria_id', 'uuid'),
      ('duplas', 'numero_senha', 'integer'),
      ('duplas', 'status_pagamento', 'status'),
      ('duplas', 'created_at', 'timestamp with time zone'),
      ('competidores', 'id', 'uuid'),
      ('competidores', 'parque_id', 'uuid')
    ) as required(table_name, column_name, expected_type)
  loop
    select case
      when c.data_type = 'USER-DEFINED' then c.udt_name
      else c.data_type
    end into actual_type
      from information_schema.columns c
     where c.table_schema = 'public'
       and c.table_name = required_column.table_name
       and c.column_name = required_column.column_name;

    if actual_type is null then
      raise exception 'Pista ops preflight: public.%.% is missing',
        required_column.table_name, required_column.column_name;
    end if;

    if required_column.expected_type = 'status' then
      null;
    elsif required_column.expected_type = 'integer'
      and actual_type not in ('smallint', 'integer', 'bigint') then
      raise exception 'Pista ops preflight: public.%.% must be an integer, found %',
        required_column.table_name, required_column.column_name, actual_type;
    elsif required_column.expected_type = 'text'
      and actual_type not in ('text', 'character varying', 'character') then
      raise exception 'Pista ops preflight: public.%.% must be textual, found %',
        required_column.table_name, required_column.column_name, actual_type;
    elsif required_column.expected_type = 'timestamp with time zone'
      and actual_type not in ('timestamp with time zone', 'timestamp without time zone') then
      raise exception 'Pista ops preflight: public.%.% must be a timestamp, found %',
        required_column.table_name, required_column.column_name, actual_type;
    elsif required_column.expected_type not in ('text', 'timestamp with time zone')
      and actual_type <> required_column.expected_type then
      raise exception 'Pista ops preflight: public.%.% expected %, found %',
        required_column.table_name, required_column.column_name,
        required_column.expected_type, actual_type;
    end if;
  end loop;

  if to_regprocedure('auth.uid()') is null then
    raise exception 'Pista ops preflight: auth.uid() is required';
  end if;
end;
$$;

create table public.pista_ops_members (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.eventos(id) on delete restrict,
  usuario_id uuid not null references public.perfis(id) on delete restrict,
  funcao text not null check (funcao in ('organizador', 'escritorio', 'locutor')),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  criado_por uuid not null references public.perfis(id) on delete restrict,
  revogado_em timestamptz,
  revogado_por uuid references public.perfis(id) on delete restrict,
  constraint pista_ops_member_revocation_ck check (
    (ativo and revogado_em is null and revogado_por is null)
    or (not ativo and revogado_em is not null and revogado_por is not null)
  )
);
create unique index pista_ops_members_active_uq
  on public.pista_ops_members(evento_id, usuario_id, funcao) where ativo;
create index pista_ops_members_user_event_idx
  on public.pista_ops_members(usuario_id, evento_id) where ativo;

create table public.pista_ops_first_organizer_audit (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null unique references public.eventos(id) on delete restrict,
  usuario_id uuid not null references public.perfis(id) on delete restrict,
  executado_por text not null,
  executado_em timestamptz not null default now()
);

create table public.pista_ops_settings (
  evento_id uuid primary key references public.eventos(id) on delete restrict,
  permite_substituicao boolean not null default false,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid not null references public.perfis(id) on delete restrict
);

create table public.pista_ops_rounds (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.eventos(id) on delete restrict,
  categoria_id uuid not null references public.categorias(id) on delete restrict,
  numero integer not null check (numero > 0),
  quantidade_bois integer not null check (quantidade_bois > 0),
  estado text not null default 'planejado'
    check (estado in ('planejado', 'ativo', 'finalizado', 'aguardando_proximo_rodizio')),
  criado_em timestamptz not null default now(),
  criado_por uuid not null references public.perfis(id) on delete restrict,
  iniciado_em timestamptz,
  iniciado_por uuid references public.perfis(id) on delete restrict,
  constraint pista_ops_round_number_uq unique(evento_id, categoria_id, numero)
);
create unique index pista_ops_one_active_round_uq
  on public.pista_ops_rounds(evento_id, categoria_id) where estado = 'ativo';
create index pista_ops_round_scope_idx
  on public.pista_ops_rounds(evento_id, categoria_id, numero desc);

create table public.pista_ops_runs (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.eventos(id) on delete restrict,
  categoria_id uuid not null references public.categorias(id) on delete restrict,
  dupla_id uuid not null references public.duplas(id) on delete restrict,
  numero_corrida smallint not null check (numero_corrida in (1, 2)),
  rodada_atual_id uuid references public.pista_ops_rounds(id) on delete restrict,
  estado text not null default 'pendente'
    check (estado in ('pendente', 'retorno_pendente', 'em_curso', 'zero', 'valeu_boi')),
  pontuacao numeric(12, 3),
  retornos_realizados integer not null default 0 check (retornos_realizados >= 0),
  competidor_real_id uuid references public.competidores(id) on delete restrict,
  atualizado_em timestamptz not null default now(),
  constraint pista_ops_run_dupla_number_uq unique(dupla_id, numero_corrida),
  constraint pista_ops_run_score_ck check (
    (estado = 'valeu_boi' and pontuacao is not null and pontuacao >= 0)
    or (estado = 'zero' and pontuacao = 0)
    or (estado not in ('valeu_boi', 'zero') and pontuacao is null)
  )
);
create index pista_ops_runs_scope_state_idx
  on public.pista_ops_runs(evento_id, categoria_id, estado, dupla_id);
create index pista_ops_runs_round_idx on public.pista_ops_runs(rodada_atual_id);

create table public.pista_ops_queue_items (
  id uuid primary key default gen_random_uuid(),
  rodada_id uuid not null references public.pista_ops_rounds(id) on delete restrict,
  dupla_id uuid not null references public.duplas(id) on delete restrict,
  corrida_id uuid references public.pista_ops_runs(id) on delete restrict,
  tipo text not null check (tipo in ('regular', 'rabo_da_gata')),
  estado text not null default 'na_fila'
    check (estado in ('na_fila', 'chamada', 'retorno_pendente', 'aguardando_proximo', 'concluida', 'encaminhada')),
  eh_retorno boolean not null default false,
  competidor_real_id uuid references public.competidores(id) on delete restrict,
  ordem_fila bigint generated always as identity,
  criado_em timestamptz not null default now(),
  constraint pista_ops_queue_kind_ck check (
    (tipo = 'regular' and corrida_id is not null)
    or (tipo = 'rabo_da_gata' and corrida_id is null and not eh_retorno)
  )
);
create unique index pista_ops_queue_run_per_round_uq
  on public.pista_ops_queue_items(rodada_id, corrida_id) where tipo = 'regular';
create index pista_ops_queue_order_idx
  on public.pista_ops_queue_items(rodada_id, estado, ordem_fila);
create unique index pista_ops_rabo_round_entry_uq
  on public.pista_ops_queue_items(rodada_id, dupla_id) where tipo = 'rabo_da_gata';

create table public.pista_ops_call_requests (
  id uuid primary key default gen_random_uuid(),
  rodada_id uuid not null references public.pista_ops_rounds(id) on delete restrict,
  request_id uuid not null,
  resultado jsonb,
  criado_em timestamptz not null default now(),
  unique(rodada_id, request_id)
);

create table public.pista_ops_positions (
  rodada_id uuid not null references public.pista_ops_rounds(id) on delete restrict,
  numero_posicao integer not null check (numero_posicao > 0),
  estado text not null default 'livre' check (estado in ('livre', 'ocupada', 'consumida')),
  item_fila_id uuid unique references public.pista_ops_queue_items(id) on delete restrict,
  primary key(rodada_id, numero_posicao),
  constraint pista_ops_position_item_ck check (
    (estado = 'ocupada' and item_fila_id is not null)
    or (estado in ('livre', 'consumida') and item_fila_id is null)
  )
);

create table public.pista_ops_result_corrections (
  id uuid primary key default gen_random_uuid(),
  corrida_id uuid not null references public.pista_ops_runs(id) on delete restrict,
  resultado_anterior text not null check (resultado_anterior in ('zero', 'valeu_boi')),
  pontuacao_anterior numeric(12, 3) not null,
  resultado_novo text not null check (resultado_novo in ('zero', 'valeu_boi')),
  pontuacao_nova numeric(12, 3) not null,
  autor_id uuid not null references public.perfis(id) on delete restrict,
  ocorrido_em timestamptz not null default now(),
  justificativa text not null check (length(btrim(justificativa)) > 0),
  constraint pista_ops_correction_score_ck check (
    pontuacao_anterior >= 0 and pontuacao_nova >= 0
    and (resultado_anterior <> 'zero' or pontuacao_anterior = 0)
    and (resultado_novo <> 'zero' or pontuacao_nova = 0)
  )
);
create index pista_ops_corrections_run_idx
  on public.pista_ops_result_corrections(corrida_id, ocorrido_em desc);

create table public.pista_ops_prize_versions (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.eventos(id) on delete restrict,
  categoria_id uuid not null references public.categorias(id) on delete restrict,
  versao integer not null check (versao > 0),
  colocacoes jsonb not null check (jsonb_typeof(colocacoes) = 'array' and jsonb_array_length(colocacoes) > 0),
  criado_por uuid not null references public.perfis(id) on delete restrict,
  criado_em timestamptz not null default now(),
  unique(evento_id, categoria_id, versao)
);
create index pista_ops_prizes_current_idx
  on public.pista_ops_prize_versions(evento_id, categoria_id, versao desc);

create table public.pista_ops_ties (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.eventos(id) on delete restrict,
  categoria_id uuid not null references public.categorias(id) on delete restrict,
  participantes jsonb not null check (jsonb_typeof(participantes) = 'array' and jsonb_array_length(participantes) >= 2),
  decisao text not null check (length(btrim(decisao)) > 0),
  termos text not null check (length(btrim(termos)) > 0),
  campeao_id uuid,
  divisao_premio jsonb,
  criado_por uuid not null references public.perfis(id) on delete restrict,
  criado_em timestamptz not null default now(),
  constraint pista_ops_tie_no_decision_ck check (campeao_id is null and divisao_premio is null)
);
create index pista_ops_ties_scope_idx
  on public.pista_ops_ties(evento_id, categoria_id, criado_em desc);

alter table public.pista_ops_members enable row level security;
alter table public.pista_ops_first_organizer_audit enable row level security;
alter table public.pista_ops_settings enable row level security;
alter table public.pista_ops_rounds enable row level security;
alter table public.pista_ops_runs enable row level security;
alter table public.pista_ops_queue_items enable row level security;
alter table public.pista_ops_call_requests enable row level security;
alter table public.pista_ops_positions enable row level security;
alter table public.pista_ops_result_corrections enable row level security;
alter table public.pista_ops_prize_versions enable row level security;
alter table public.pista_ops_ties enable row level security;

revoke all on public.pista_ops_members, public.pista_ops_first_organizer_audit,
  public.pista_ops_settings,
  public.pista_ops_rounds, public.pista_ops_runs, public.pista_ops_queue_items,
  public.pista_ops_call_requests,
  public.pista_ops_positions, public.pista_ops_result_corrections,
  public.pista_ops_prize_versions, public.pista_ops_ties from public, anon, authenticated;

create or replace function public.pista_ops_check_access(p_evento_id uuid, p_funcoes text[])
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  profile_park_id uuid;
  event_park_id uuid;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'PISTA_AUTH_REQUIRED';
  end if;

  select p.parque_id into profile_park_id
    from public.perfis p where p.id = actor_id;
  if not found or profile_park_id is null then
    raise exception using errcode = '42501', message = 'PISTA_PROFILE_REQUIRED';
  end if;

  select e.parque_id into event_park_id
    from public.eventos e where e.id = p_evento_id;
  if not found or event_park_id is distinct from profile_park_id then
    raise exception using errcode = '42501', message = 'PISTA_EVENT_PARK_MISMATCH';
  end if;

  if not exists (
    select 1 from public.pista_ops_members m
     where m.evento_id = p_evento_id
       and m.usuario_id = actor_id
       and m.ativo
       and m.funcao = any(p_funcoes)
  ) then
    raise exception using errcode = '42501', message = 'PISTA_EVENT_ROLE_REQUIRED';
  end if;
  return actor_id;
end;
$$;

create or replace function public.pista_ops_lock_category(p_evento_id uuid, p_categoria_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
begin
  perform 1 from public.categorias c
   where c.id = p_categoria_id and c.evento_id = p_evento_id
   for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'PISTA_CATEGORY_OUT_OF_EVENT';
  end if;
end;
$$;

create or replace function public.pista_ops_configurar_membro(
  p_evento_id uuid,
  p_usuario_id uuid,
  p_funcao text,
  p_ativo boolean
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  actor_id uuid;
  target_id uuid;
  target_park_id uuid;
  event_park_id uuid;
begin
  actor_id := public.pista_ops_check_access(p_evento_id, array['organizador']);
  if p_funcao not in ('organizador', 'escritorio', 'locutor') then
    raise exception using errcode = '22023', message = 'PISTA_INVALID_ROLE';
  end if;

  select e.parque_id into event_park_id from public.eventos e where e.id = p_evento_id for update;
  select p.id, p.parque_id into target_id, target_park_id
    from public.perfis p where p.id = p_usuario_id;
  if not found or target_park_id is distinct from event_park_id then
    raise exception using errcode = '42501', message = 'PISTA_MEMBER_PARK_MISMATCH';
  end if;

  if p_ativo then
    select m.id into target_id from public.pista_ops_members m
     where m.evento_id = p_evento_id and m.usuario_id = p_usuario_id
       and m.funcao = p_funcao and m.ativo for update;
    if found then return target_id; end if;
    insert into public.pista_ops_members(evento_id, usuario_id, funcao, ativo, criado_por)
    values (p_evento_id, p_usuario_id, p_funcao, true, actor_id)
    returning id into target_id;
  else
    update public.pista_ops_members
       set ativo = false, revogado_em = now(), revogado_por = actor_id
     where evento_id = p_evento_id and usuario_id = p_usuario_id
       and funcao = p_funcao and ativo
    returning id into target_id;
    if not found then
      raise exception using errcode = 'P0001', message = 'PISTA_ACTIVE_MEMBER_NOT_FOUND';
    end if;
  end if;
  return target_id;
end;
$$;

create or replace function public.pista_ops_configurar_substituicao(
  p_evento_id uuid,
  p_permitir boolean
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare actor_id uuid;
begin
  actor_id := public.pista_ops_check_access(p_evento_id, array['organizador']);
  insert into public.pista_ops_settings(evento_id, permite_substituicao, atualizado_por)
  values (p_evento_id, p_permitir, actor_id)
  on conflict (evento_id) do update
    set permite_substituicao = excluded.permite_substituicao,
        atualizado_em = now(), atualizado_por = excluded.atualizado_por;
  return p_permitir;
end;
$$;

create or replace function public.pista_ops_planejar_rodizio(
  p_evento_id uuid,
  p_categoria_id uuid,
  p_quantidade_bois integer
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  actor_id uuid;
  next_number integer;
  new_id uuid;
begin
  actor_id := public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio']);
  if p_quantidade_bois is null or p_quantidade_bois < 1 then
    raise exception using errcode = '22023', message = 'PISTA_INVALID_BULL_COUNT';
  end if;
  perform public.pista_ops_lock_category(p_evento_id, p_categoria_id);

  if exists (
    select 1 from public.pista_ops_rounds r
     where r.evento_id = p_evento_id and r.categoria_id = p_categoria_id
       and r.estado = 'ativo'
  ) then
    raise exception using errcode = 'P0001', message = 'PISTA_STARTED_ROUND_POLICY_PENDING';
  end if;

  select coalesce(max(r.numero), 0) + 1 into next_number
    from public.pista_ops_rounds r
   where r.evento_id = p_evento_id and r.categoria_id = p_categoria_id;
  insert into public.pista_ops_rounds(
    evento_id, categoria_id, numero, quantidade_bois, criado_por
  ) values (
    p_evento_id, p_categoria_id, next_number, p_quantidade_bois, actor_id
  ) returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.pista_ops_iniciar_rodizio(p_rodizio_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  target public.pista_ops_rounds%rowtype;
  actor_id uuid;
  prior_round public.pista_ops_rounds%rowtype;
  eligible record;
begin
  select * into target from public.pista_ops_rounds where id = p_rodizio_id;
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_ROUND_NOT_FOUND'; end if;
  actor_id := public.pista_ops_check_access(target.evento_id, array['organizador', 'escritorio', 'locutor']);
  perform public.pista_ops_lock_category(target.evento_id, target.categoria_id);
  select * into target from public.pista_ops_rounds where id = p_rodizio_id for update;
  if target.estado <> 'planejado' then
    raise exception using errcode = 'P0001', message = 'PISTA_ROUND_ALREADY_STARTED';
  end if;
  if exists (
    select 1 from public.pista_ops_rounds r
     where r.evento_id = target.evento_id and r.categoria_id = target.categoria_id
       and r.estado = 'ativo'
  ) then
    raise exception using errcode = 'P0001', message = 'PISTA_ACTIVE_ROUND_EXISTS';
  end if;
  if exists (
    select 1 from public.pista_ops_rounds r
     where r.evento_id = target.evento_id and r.categoria_id = target.categoria_id
       and r.estado = 'planejado' and r.numero < target.numero
  ) then
    raise exception using errcode = 'P0001', message = 'PISTA_ROUND_ORDER_REQUIRED';
  end if;

  insert into public.pista_ops_settings(evento_id, atualizado_por)
  values (target.evento_id, actor_id) on conflict (evento_id) do nothing;

  insert into public.pista_ops_runs(evento_id, categoria_id, dupla_id, numero_corrida)
  select target.evento_id, target.categoria_id, d.id, n.run_number::smallint
    from public.duplas d cross join generate_series(1, 2) as n(run_number)
   where d.evento_id = target.evento_id and d.categoria_id = target.categoria_id
    and d.status_pagamento is distinct from 'cancelado'
  on conflict (dupla_id, numero_corrida) do nothing;

  for eligible in
    select d.id as dupla_id, d.status_pagamento
      from public.duplas d
     where d.evento_id = target.evento_id and d.categoria_id = target.categoria_id
      and d.status_pagamento is distinct from 'cancelado'
     order by d.numero_senha asc, d.created_at asc, d.id asc
  loop
    if (select count(*) from public.pista_ops_runs x where x.dupla_id = eligible.dupla_id) <> 2 then
      raise exception using errcode = 'P0001', message = 'PISTA_REGULAR_RUN_COUNT_INVALID';
    end if;
  end loop;

  update public.pista_ops_queue_items q
     set estado = 'encaminhada'
    from public.pista_ops_runs r
   where q.corrida_id = r.id and q.estado in ('na_fila', 'retorno_pendente', 'aguardando_proximo')
     and r.evento_id = target.evento_id and r.categoria_id = target.categoria_id
     and r.estado in ('pendente', 'retorno_pendente') and q.rodada_id <> target.id;

    insert into public.pista_ops_queue_items(rodada_id, dupla_id, corrida_id, tipo, estado, eh_retorno, competidor_real_id)
  select target.id, r.dupla_id, r.id, 'regular',
         case when r.estado = 'retorno_pendente' then 'retorno_pendente' else 'na_fila' end,
      r.estado = 'retorno_pendente', r.competidor_real_id
    from public.pista_ops_runs r
    join public.duplas d on d.id = r.dupla_id
   where r.evento_id = target.evento_id and r.categoria_id = target.categoria_id
     and r.estado in ('pendente', 'retorno_pendente')
    and d.status_pagamento is distinct from 'cancelado'
   order by d.numero_senha asc, d.created_at asc, d.id asc, r.numero_corrida asc
  on conflict (rodada_id, corrida_id) where tipo = 'regular' do nothing;

  insert into public.pista_ops_queue_items(rodada_id, dupla_id, tipo, estado)
  select target.id, q.dupla_id, 'rabo_da_gata', 'na_fila'
    from public.pista_ops_queue_items q
    join public.pista_ops_rounds old_round on old_round.id = q.rodada_id
   where old_round.evento_id = target.evento_id and old_round.categoria_id = target.categoria_id
     and q.tipo = 'rabo_da_gata' and q.estado = 'aguardando_proximo'
     and q.rodada_id <> target.id
  order by q.ordem_fila
  on conflict (rodada_id, dupla_id) where tipo = 'rabo_da_gata' do nothing;

  update public.pista_ops_queue_items q
     set estado = 'encaminhada'
   where q.tipo = 'rabo_da_gata' and q.estado = 'aguardando_proximo'
     and q.rodada_id <> target.id
     and q.rodada_id in (
       select r.id from public.pista_ops_rounds r
        where r.evento_id = target.evento_id and r.categoria_id = target.categoria_id
     );

  insert into public.pista_ops_positions(rodada_id, numero_posicao)
  select target.id, slot from generate_series(1, target.quantidade_bois) as slot;

  update public.pista_ops_runs r
     set rodada_atual_id = target.id, atualizado_em = now()
   where r.evento_id = target.evento_id and r.categoria_id = target.categoria_id
     and r.estado in ('pendente', 'retorno_pendente');

  update public.pista_ops_rounds
     set estado = 'ativo', iniciado_em = now(), iniciado_por = actor_id
   where id = target.id;

  return jsonb_build_object('status', 'ativo', 'rodizio_id', target.id);
end;
$$;

create or replace function public.pista_ops_chamar_proxima(p_rodizio_id uuid, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  target public.pista_ops_rounds%rowtype;
  actor_id uuid;
  item public.pista_ops_queue_items%rowtype;
  position_number integer;
  result_payload jsonb;
  request_row_id uuid;
begin
  if p_request_id is null then
    raise exception using errcode = '22023', message = 'PISTA_REQUEST_ID_REQUIRED';
  end if;
  select * into target from public.pista_ops_rounds where id = p_rodizio_id;
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_ROUND_NOT_FOUND'; end if;
  actor_id := public.pista_ops_check_access(target.evento_id, array['organizador', 'escritorio', 'locutor']);
  perform public.pista_ops_lock_category(target.evento_id, target.categoria_id);
  select * into target from public.pista_ops_rounds where id = p_rodizio_id for update;
  select r.id, r.resultado into request_row_id, result_payload
    from public.pista_ops_call_requests r
   where r.rodada_id = target.id and r.request_id = p_request_id for update;
  if found then
    if result_payload is null then
      raise exception using errcode = 'P0001', message = 'PISTA_REQUEST_IN_PROGRESS';
    end if;
    return result_payload;
  end if;
  insert into public.pista_ops_call_requests(rodada_id, request_id)
  values (target.id, p_request_id) returning id into request_row_id;
  if target.estado <> 'ativo' then
    raise exception using errcode = 'P0001', message = 'PISTA_ROUND_NOT_ACTIVE';
  end if;

  update public.pista_ops_queue_items q set estado = 'encaminhada'
   from public.duplas d
   where q.dupla_id = d.id and q.rodada_id = target.id
     and q.estado = 'na_fila' and d.status_pagamento = 'cancelado';
  select * into item from public.pista_ops_queue_items q
   where q.rodada_id = target.id and q.estado = 'na_fila'
     and exists (select 1 from public.duplas d where d.id = q.dupla_id
                  and d.status_pagamento is distinct from 'cancelado')
   order by q.ordem_fila for update skip locked limit 1;
  if not found then
    if exists (
      select 1 from public.pista_ops_runs r join public.duplas d on d.id = r.dupla_id
       where r.evento_id = target.evento_id and r.categoria_id = target.categoria_id
         and r.estado in ('pendente', 'retorno_pendente')
         and d.status_pagamento is distinct from 'cancelado'
    ) or exists (
      select 1 from public.pista_ops_queue_items q
       where q.rodada_id = target.id and q.estado in ('retorno_pendente', 'aguardando_proximo')
    ) then
      update public.pista_ops_rounds set estado = 'aguardando_proximo_rodizio' where id = target.id;
      result_payload := jsonb_build_object('status', 'aguardando_proximo_rodizio');
      update public.pista_ops_call_requests set resultado = result_payload where id = request_row_id;
      return result_payload;
    end if;
    update public.pista_ops_rounds set estado = 'finalizado' where id = target.id;
    result_payload := jsonb_build_object('status', 'fila_concluida');
    update public.pista_ops_call_requests set resultado = result_payload where id = request_row_id;
    return result_payload;
  end if;

  select p.numero_posicao into position_number from public.pista_ops_positions p
   where p.rodada_id = target.id and p.estado = 'livre'
   order by p.numero_posicao for update skip locked limit 1;
  if position_number is null then
    update public.pista_ops_queue_items set estado = 'aguardando_proximo'
     where rodada_id = target.id and estado = 'na_fila';
    update public.pista_ops_rounds set estado = 'aguardando_proximo_rodizio' where id = target.id;
    result_payload := jsonb_build_object('status', 'aguardando_proximo_rodizio');
    update public.pista_ops_call_requests set resultado = result_payload where id = request_row_id;
    return result_payload;
  end if;

  update public.pista_ops_queue_items set estado = 'chamada' where id = item.id;
  update public.pista_ops_positions
     set estado = 'ocupada', item_fila_id = item.id
   where rodada_id = target.id and numero_posicao = position_number and estado = 'livre';
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_POSITION_RACE'; end if;
  if item.tipo = 'regular' then
    update public.pista_ops_runs set estado = 'em_curso', atualizado_em = now()
     where id = item.corrida_id and estado in ('pendente', 'retorno_pendente');
    if not found then raise exception using errcode = 'P0001', message = 'PISTA_RUN_NOT_CALLABLE'; end if;
  end if;
  result_payload := jsonb_build_object('status', 'chamada', 'item_id', item.id, 'posicao', position_number,
                                       'tipo', item.tipo, 'eh_retorno', item.eh_retorno);
  update public.pista_ops_call_requests set resultado = result_payload where id = request_row_id;
  return result_payload;
end;
$$;

create or replace function public.pista_ops_registrar_resultado(
  p_item_fila_id uuid,
  p_resultado text,
  p_pontuacao numeric
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
  select q.* into item from public.pista_ops_queue_items q where q.id = p_item_fila_id;
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_QUEUE_ITEM_NOT_FOUND'; end if;
  select * into target_round from public.pista_ops_rounds where id = item.rodada_id;
  actor_id := public.pista_ops_check_access(target_round.evento_id, array['organizador', 'locutor']);
  perform public.pista_ops_lock_category(target_round.evento_id, target_round.categoria_id);
  select q.* into item from public.pista_ops_queue_items q where q.id = p_item_fila_id for update;
  if item.estado <> 'chamada' or item.tipo <> 'regular' then
    raise exception using errcode = 'P0001', message = 'PISTA_RESULT_NOT_CALLABLE';
  end if;
  if p_resultado not in ('zero', 'valeu_boi') then
    raise exception using errcode = '22023', message = 'PISTA_INVALID_RESULT';
  end if;
  if p_resultado = 'valeu_boi' and (p_pontuacao is null or p_pontuacao < 0) then
    raise exception using errcode = '22023', message = 'PISTA_SCORE_REQUIRED';
  end if;
  if p_resultado = 'zero' and p_pontuacao is distinct from 0::numeric then
    raise exception using errcode = '22023', message = 'PISTA_ZERO_SCORE_MUST_BE_ZERO';
  end if;

  update public.pista_ops_runs
     set estado = p_resultado, pontuacao = p_pontuacao,
         retornos_realizados = retornos_realizados + case when item.eh_retorno then 1 else 0 end,
         atualizado_em = now()
   where id = item.corrida_id and estado = 'em_curso';
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_RUN_NOT_RUNNING'; end if;
  update public.pista_ops_positions
     set estado = 'consumida', item_fila_id = null
   where rodada_id = item.rodada_id and item_fila_id = item.id and estado = 'ocupada';
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_POSITION_RACE'; end if;
  update public.pista_ops_queue_items set estado = 'concluida' where id = item.id;
  return item.corrida_id;
end;
$$;

create or replace function public.pista_ops_registrar_retorno(p_item_fila_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  item public.pista_ops_queue_items%rowtype;
  target_round public.pista_ops_rounds%rowtype;
  actor_id uuid;
begin
  select q.* into item from public.pista_ops_queue_items q where q.id = p_item_fila_id;
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_QUEUE_ITEM_NOT_FOUND'; end if;
  select * into target_round from public.pista_ops_rounds where id = item.rodada_id;
  actor_id := public.pista_ops_check_access(target_round.evento_id, array['organizador', 'locutor']);
  perform public.pista_ops_lock_category(target_round.evento_id, target_round.categoria_id);
  select q.* into item from public.pista_ops_queue_items q where q.id = p_item_fila_id for update;
  if item.estado <> 'chamada' or item.tipo <> 'regular' then
    raise exception using errcode = 'P0001', message = 'PISTA_RETURN_NOT_RUNNING';
  end if;
  update public.pista_ops_runs set estado = 'retorno_pendente', atualizado_em = now()
   where id = item.corrida_id and estado = 'em_curso';
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_RUN_NOT_RUNNING'; end if;
  update public.pista_ops_positions set estado = 'livre', item_fila_id = null
   where rodada_id = item.rodada_id and item_fila_id = item.id and estado = 'ocupada';
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_POSITION_RACE'; end if;
  update public.pista_ops_queue_items set estado = 'retorno_pendente' where id = item.id;
  return jsonb_build_object('status', 'retorno_pendente', 'consumiu_boi', false, 'item_id', item.id);
end;
$$;

create or replace function public.pista_ops_liberar_retorno(p_item_fila_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  item public.pista_ops_queue_items%rowtype;
  target_round public.pista_ops_rounds%rowtype;
  actor_id uuid;
begin
  select q.* into item from public.pista_ops_queue_items q where q.id = p_item_fila_id;
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_QUEUE_ITEM_NOT_FOUND'; end if;
  select * into target_round from public.pista_ops_rounds where id = item.rodada_id;
  actor_id := public.pista_ops_check_access(target_round.evento_id, array['organizador', 'locutor']);
  perform public.pista_ops_lock_category(target_round.evento_id, target_round.categoria_id);
  select q.* into item from public.pista_ops_queue_items q where q.id = p_item_fila_id for update;
  if item.estado <> 'retorno_pendente' then
    raise exception using errcode = 'P0001', message = 'PISTA_RETURN_NOT_PENDING';
  end if;
  if target_round.estado <> 'ativo' then
    return jsonb_build_object('status', 'aguardando_proximo_rodizio', 'item_id', item.id);
  end if;
  if not exists (
    select 1 from public.pista_ops_positions p
     where p.rodada_id = target_round.id and p.estado = 'livre'
  ) then
    return jsonb_build_object('status', 'aguardando_proximo_rodizio', 'item_id', item.id);
  end if;
  update public.pista_ops_queue_items set estado = 'na_fila', eh_retorno = true where id = item.id;
  update public.pista_ops_runs set estado = 'pendente', atualizado_em = now()
   where id = item.corrida_id and estado = 'retorno_pendente';
  return jsonb_build_object('status', 'liberado', 'item_id', item.id);
end;
$$;

create or replace function public.pista_ops_rabo_da_gata(
  p_rodizio_id uuid,
  p_dupla_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  target_round public.pista_ops_rounds%rowtype;
  actor_id uuid;
  new_status text;
  item_id uuid;
begin
  select * into target_round from public.pista_ops_rounds where id = p_rodizio_id;
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_ROUND_NOT_FOUND'; end if;
  actor_id := public.pista_ops_check_access(target_round.evento_id, array['organizador', 'escritorio', 'locutor']);
  perform public.pista_ops_lock_category(target_round.evento_id, target_round.categoria_id);
  select * into target_round from public.pista_ops_rounds where id = p_rodizio_id for update;
  if target_round.estado <> 'ativo' then raise exception using errcode = 'P0001', message = 'PISTA_ROUND_NOT_ACTIVE'; end if;
  if not exists (
    select 1 from public.duplas d where d.id = p_dupla_id
      and d.evento_id = target_round.evento_id and d.categoria_id = target_round.categoria_id
      and d.status_pagamento is distinct from 'cancelado'
  ) then raise exception using errcode = 'P0001', message = 'PISTA_ENTRY_NOT_ELIGIBLE'; end if;

  new_status := case when exists (
    select 1 from public.pista_ops_positions p where p.rodada_id = target_round.id and p.estado = 'livre'
  ) then 'na_fila' else 'aguardando_proximo' end;
  insert into public.pista_ops_queue_items(rodada_id, dupla_id, tipo, estado)
  values (target_round.id, p_dupla_id, 'rabo_da_gata', new_status)
  returning id into item_id;
  return jsonb_build_object(
    'status', case when new_status = 'na_fila' then 'encaminhado' else 'aguardando_proximo_rodizio' end,
    'item_id', item_id,
    'reservou_posicao', false
  );
end;
$$;

create or replace function public.pista_ops_finalizar_rabo_da_gata(p_item_fila_id uuid)
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
  select q.* into item from public.pista_ops_queue_items q where q.id = p_item_fila_id;
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_QUEUE_ITEM_NOT_FOUND'; end if;
  select * into target_round from public.pista_ops_rounds where id = item.rodada_id;
  actor_id := public.pista_ops_check_access(target_round.evento_id, array['organizador', 'locutor']);
  perform public.pista_ops_lock_category(target_round.evento_id, target_round.categoria_id);
  select q.* into item from public.pista_ops_queue_items q where q.id = p_item_fila_id for update;
  if item.tipo <> 'rabo_da_gata' or item.estado <> 'chamada' then
    raise exception using errcode = 'P0001', message = 'PISTA_RABO_NOT_CALLABLE';
  end if;
  update public.pista_ops_positions set estado = 'livre', item_fila_id = null
   where rodada_id = item.rodada_id and item_fila_id = item.id and estado = 'ocupada';
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_POSITION_RACE'; end if;
  update public.pista_ops_queue_items set estado = 'concluida' where id = item.id;
  return item.id;
end;
$$;

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
  select q.* into item from public.pista_ops_queue_items q where q.id = p_item_fila_id;
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_QUEUE_ITEM_NOT_FOUND'; end if;
  select * into target_round from public.pista_ops_rounds where id = item.rodada_id;
  actor_id := public.pista_ops_check_access(target_round.evento_id, array['organizador']);
  perform public.pista_ops_lock_category(target_round.evento_id, target_round.categoria_id);
  if not coalesce((select s.permite_substituicao from public.pista_ops_settings s where s.evento_id = target_round.evento_id), false) then
    raise exception using errcode = 'P0001', message = 'PISTA_SUBSTITUTION_DISABLED';
  end if;
  if not exists (
    select 1 from public.competidores c join public.eventos e on e.id = target_round.evento_id
     where c.id = p_competidor_id and c.parque_id = e.parque_id
  ) then raise exception using errcode = '42501', message = 'PISTA_SUBSTITUTE_PARK_MISMATCH'; end if;
  update public.pista_ops_queue_items set competidor_real_id = p_competidor_id
   where id = p_item_fila_id and estado in ('na_fila', 'chamada', 'retorno_pendente', 'aguardando_proximo');
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_SUBSTITUTION_STATE_INVALID'; end if;
  if item.corrida_id is not null then
    update public.pista_ops_runs set competidor_real_id = p_competidor_id, atualizado_em = now()
     where id = item.corrida_id and estado in ('pendente', 'retorno_pendente', 'em_curso');
  end if;
  return p_competidor_id;
end;
$$;

create or replace function public.pista_ops_corrigir_resultado(
  p_corrida_id uuid,
  p_resultado text,
  p_pontuacao numeric,
  p_justificativa text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  target public.pista_ops_runs%rowtype;
  actor_id uuid;
begin
  select * into target from public.pista_ops_runs where id = p_corrida_id;
  if not found then raise exception using errcode = 'P0001', message = 'PISTA_RUN_NOT_FOUND'; end if;
  actor_id := public.pista_ops_check_access(target.evento_id, array['organizador', 'locutor']);
  perform public.pista_ops_lock_category(target.evento_id, target.categoria_id);
  select * into target from public.pista_ops_runs where id = p_corrida_id for update;
  if target.estado not in ('zero', 'valeu_boi') then
    raise exception using errcode = 'P0001', message = 'PISTA_RESULT_NOT_CORRECTABLE';
  end if;
  if p_resultado not in ('zero', 'valeu_boi')
    or (p_resultado = 'valeu_boi' and (p_pontuacao is null or p_pontuacao < 0))
    or (p_resultado = 'zero' and p_pontuacao is distinct from 0::numeric) then
    raise exception using errcode = '22023', message = 'PISTA_INVALID_CORRECTION';
  end if;
  if p_justificativa is null or length(btrim(p_justificativa)) = 0 then
    raise exception using errcode = '22023', message = 'PISTA_CORRECTION_REASON_REQUIRED';
  end if;
  insert into public.pista_ops_result_corrections(
    corrida_id, resultado_anterior, pontuacao_anterior, resultado_novo,
    pontuacao_nova, autor_id, justificativa
  ) values (
    target.id, target.estado, target.pontuacao, p_resultado,
    p_pontuacao, actor_id, btrim(p_justificativa)
  );
  update public.pista_ops_runs
     set estado = p_resultado, pontuacao = p_pontuacao, atualizado_em = now()
   where id = target.id;
  return target.id;
end;
$$;

create or replace function public.pista_ops_salvar_premiacao(
  p_evento_id uuid,
  p_categoria_id uuid,
  p_colocacoes jsonb
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  actor_id uuid;
  next_version integer;
begin
  actor_id := public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio']);
  perform public.pista_ops_lock_category(p_evento_id, p_categoria_id);
  if jsonb_typeof(p_colocacoes) <> 'array' or jsonb_array_length(p_colocacoes) < 1
    or exists (
      select 1 from jsonb_array_elements(p_colocacoes) as items(value)
       where jsonb_typeof(items.value) <> 'object'
         or not (items.value ? 'colocacao') or not (items.value ? 'valor')
         or (items.value->>'colocacao') !~ '^[1-9][0-9]*$'
         or (items.value->>'valor') !~ '^[0-9]+([.][0-9]+)?$'
    )
        or (select count(*) <> count(distinct (items.value->>'colocacao'))
          from jsonb_array_elements(p_colocacoes) as items(value)) then
    raise exception using errcode = '22023', message = 'PISTA_INVALID_PRIZE_PLACES';
  end if;
  select coalesce(max(v.versao), 0) + 1 into next_version
    from public.pista_ops_prize_versions v
   where v.evento_id = p_evento_id and v.categoria_id = p_categoria_id;
  insert into public.pista_ops_prize_versions(
    evento_id, categoria_id, versao, colocacoes, criado_por
  ) values (p_evento_id, p_categoria_id, next_version, p_colocacoes, actor_id);
  return next_version;
end;
$$;

create or replace function public.pista_ops_registrar_empate(
  p_evento_id uuid,
  p_categoria_id uuid,
  p_participantes jsonb,
  p_decisao text,
  p_termos text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  actor_id uuid;
  new_id uuid;
begin
  actor_id := public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio']);
  perform public.pista_ops_lock_category(p_evento_id, p_categoria_id);
  if jsonb_typeof(p_participantes) <> 'array' or jsonb_array_length(p_participantes) < 2
    or exists (select 1 from jsonb_array_elements(p_participantes) as items(value)
          where jsonb_typeof(items.value) <> 'string')
    or p_decisao is null or length(btrim(p_decisao)) = 0
    or p_termos is null or length(btrim(p_termos)) = 0 then
    raise exception using errcode = '22023', message = 'PISTA_TIE_TERMS_REQUIRED';
  end if;
  insert into public.pista_ops_ties(evento_id, categoria_id, participantes, decisao, termos, criado_por)
  values (p_evento_id, p_categoria_id, p_participantes, btrim(p_decisao), btrim(p_termos), actor_id)
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.pista_ops_state(p_evento_id uuid, p_categoria_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  actor_id uuid;
  event_name text;
  result jsonb;
begin
  actor_id := public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio', 'locutor']);
  select e.nome into event_name from public.eventos e where e.id = p_evento_id;
  if p_categoria_id is not null and not exists (
    select 1 from public.categorias c where c.id = p_categoria_id and c.evento_id = p_evento_id
  ) then raise exception using errcode = 'P0001', message = 'PISTA_CATEGORY_OUT_OF_EVENT'; end if;

  select jsonb_build_object(
    'evento', jsonb_build_object('id', p_evento_id, 'nome', event_name),
    'minhas_funcoes', coalesce((
      select jsonb_agg(m.funcao order by m.funcao)
        from public.pista_ops_members m
       where m.evento_id = p_evento_id and m.usuario_id = actor_id and m.ativo
    ), '[]'::jsonb),
    'categorias', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'ordem', c.ordem) order by c.ordem, c.nome)
        from public.categorias c where c.evento_id = p_evento_id
    ), '[]'::jsonb),
    'categoria_id', p_categoria_id,
    'permite_substituicao', coalesce((
      select s.permite_substituicao from public.pista_ops_settings s where s.evento_id = p_evento_id
    ), false),
    'duplas', case when p_categoria_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'numero_senha', d.numero_senha)
                       order by d.numero_senha, d.created_at, d.id)
        from public.duplas d where d.evento_id = p_evento_id and d.categoria_id = p_categoria_id
          and d.status_pagamento is distinct from 'cancelado'
    ), '[]'::jsonb) end,
    'competidores', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome) order by c.nome, c.id)
        from public.competidores c join public.eventos e on e.id = p_evento_id
       where c.parque_id = e.parque_id
    ), '[]'::jsonb),
    'membros', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'usuario_id', m.usuario_id, 'funcao', m.funcao)
                       order by m.funcao, m.usuario_id)
        from public.pista_ops_members m where m.evento_id = p_evento_id and m.ativo
    ), '[]'::jsonb),
    'rodizios', case when p_categoria_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'numero', r.numero, 'quantidade_bois', r.quantidade_bois, 'estado', r.estado,
        'fila', coalesce((select jsonb_agg(jsonb_build_object(
          'id', q.id, 'dupla_id', q.dupla_id, 'numero_senha', d.numero_senha,
          'tipo', q.tipo, 'estado', q.estado, 'eh_retorno', q.eh_retorno,
          'corrida_id', q.corrida_id, 'numero_corrida', run.numero_corrida,
          'competidor_real_id', q.competidor_real_id
        ) order by q.ordem_fila) from public.pista_ops_queue_items q
          join public.duplas d on d.id = q.dupla_id
          left join public.pista_ops_runs run on run.id = q.corrida_id
          where q.rodada_id = r.id and q.estado <> 'encaminhada'), '[]'::jsonb),
        'posicoes', coalesce((select jsonb_agg(jsonb_build_object(
          'numero', p.numero_posicao, 'estado', p.estado, 'item_id', p.item_fila_id
        ) order by p.numero_posicao) from public.pista_ops_positions p where p.rodada_id = r.id), '[]'::jsonb),
        'corridas', coalesce((select jsonb_agg(jsonb_build_object(
          'id', run.id, 'dupla_id', run.dupla_id, 'numero_senha', d.numero_senha,
          'numero_corrida', run.numero_corrida, 'estado', run.estado, 'pontuacao', run.pontuacao,
          'retornos_realizados', run.retornos_realizados, 'competidor_real_id', run.competidor_real_id
        ) order by d.numero_senha, d.created_at, d.id, run.numero_corrida)
          from public.pista_ops_runs run join public.duplas d on d.id = run.dupla_id
          where run.evento_id = p_evento_id and run.categoria_id = p_categoria_id
            and run.rodada_atual_id = r.id), '[]'::jsonb)
      ) order by r.numero desc) from public.pista_ops_rounds r
       where r.evento_id = p_evento_id and r.categoria_id = p_categoria_id
    ), '[]'::jsonb) end,
    'correcoes', case when p_categoria_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'corrida_id', c.corrida_id, 'resultado_anterior', c.resultado_anterior,
        'pontuacao_anterior', c.pontuacao_anterior, 'resultado_novo', c.resultado_novo,
        'pontuacao_nova', c.pontuacao_nova, 'autor_id', c.autor_id,
        'ocorrido_em', c.ocorrido_em, 'justificativa', c.justificativa
      ) order by c.ocorrido_em desc) from public.pista_ops_result_corrections c
      join public.pista_ops_runs run on run.id = c.corrida_id
      where run.evento_id = p_evento_id and run.categoria_id = p_categoria_id
    ), '[]'::jsonb) end,
    'premiacoes', case when p_categoria_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('id', v.id, 'versao', v.versao,
        'colocacoes', v.colocacoes, 'criado_em', v.criado_em)
        order by v.versao desc) from public.pista_ops_prize_versions v
       where v.evento_id = p_evento_id and v.categoria_id = p_categoria_id
    ), '[]'::jsonb) end,
    'empates', case when p_categoria_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'participantes', t.participantes,
        'decisao', t.decisao, 'termos', t.termos, 'criado_em', t.criado_em)
        order by t.criado_em desc) from public.pista_ops_ties t
       where t.evento_id = p_evento_id and t.categoria_id = p_categoria_id
    ), '[]'::jsonb) end
  ) into result;
  return result;
end;
$$;

revoke all on function public.pista_ops_check_access(uuid, text[]) from public, anon, authenticated;
revoke all on function public.pista_ops_lock_category(uuid, uuid) from public, anon, authenticated;
revoke all on function public.pista_ops_configurar_membro(uuid, uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.pista_ops_configurar_substituicao(uuid, boolean) from public, anon, authenticated;
revoke all on function public.pista_ops_planejar_rodizio(uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.pista_ops_iniciar_rodizio(uuid) from public, anon, authenticated;
revoke all on function public.pista_ops_chamar_proxima(uuid, uuid) from public, anon, authenticated;
revoke all on function public.pista_ops_registrar_resultado(uuid, text, numeric) from public, anon, authenticated;
revoke all on function public.pista_ops_registrar_retorno(uuid) from public, anon, authenticated;
revoke all on function public.pista_ops_liberar_retorno(uuid) from public, anon, authenticated;
revoke all on function public.pista_ops_rabo_da_gata(uuid, uuid) from public, anon, authenticated;
revoke all on function public.pista_ops_finalizar_rabo_da_gata(uuid) from public, anon, authenticated;
revoke all on function public.pista_ops_substituir_dupla(uuid, uuid) from public, anon, authenticated;
revoke all on function public.pista_ops_corrigir_resultado(uuid, text, numeric, text) from public, anon, authenticated;
revoke all on function public.pista_ops_salvar_premiacao(uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.pista_ops_registrar_empate(uuid, uuid, jsonb, text, text) from public, anon, authenticated;
revoke all on function public.pista_ops_state(uuid, uuid) from public, anon, authenticated;

grant execute on function public.pista_ops_configurar_membro(uuid, uuid, text, boolean) to authenticated;
grant execute on function public.pista_ops_configurar_substituicao(uuid, boolean) to authenticated;
grant execute on function public.pista_ops_planejar_rodizio(uuid, uuid, integer) to authenticated;
grant execute on function public.pista_ops_iniciar_rodizio(uuid) to authenticated;
grant execute on function public.pista_ops_chamar_proxima(uuid, uuid) to authenticated;
grant execute on function public.pista_ops_registrar_resultado(uuid, text, numeric) to authenticated;
grant execute on function public.pista_ops_registrar_retorno(uuid) to authenticated;
grant execute on function public.pista_ops_liberar_retorno(uuid) to authenticated;
grant execute on function public.pista_ops_rabo_da_gata(uuid, uuid) to authenticated;
grant execute on function public.pista_ops_finalizar_rabo_da_gata(uuid) to authenticated;
grant execute on function public.pista_ops_substituir_dupla(uuid, uuid) to authenticated;
grant execute on function public.pista_ops_corrigir_resultado(uuid, text, numeric, text) to authenticated;
grant execute on function public.pista_ops_salvar_premiacao(uuid, uuid, jsonb) to authenticated;
grant execute on function public.pista_ops_registrar_empate(uuid, uuid, jsonb, text, text) to authenticated;
grant execute on function public.pista_ops_state(uuid, uuid) to authenticated;

commit;