-- Connect Vaquejada: persistence for Pista.
-- Apply only after reviewing the preflight against the live database.
-- This file has not been executed.

begin;

do $$
declare
  v_column record;
  v_data_type text;
  v_inconsistent_duplas bigint;
begin
  if to_regclass('public.perfis') is null
    or to_regclass('public.parques') is null
    or to_regclass('public.eventos') is null
    or to_regclass('public.categorias') is null
    or to_regclass('public.competidores') is null
    or to_regclass('public.duplas') is null then
    raise exception 'Pista migration requires all six confirmed public tables';
  end if;

  if to_regprocedure('public.meu_parque_id()') is null then
    raise exception 'Pista migration requires public.meu_parque_id()';
  end if;

  if current_setting('server_version_num')::integer < 150000 then
    raise exception 'Pista migration requires PostgreSQL 15+ for security-invoker views';
  end if;

  for v_column in
    select * from (values
      ('perfis', 'id'),
      ('perfis', 'parque_id'),
      ('eventos', 'id'),
      ('eventos', 'parque_id'),
      ('categorias', 'id'),
      ('categorias', 'evento_id'),
      ('competidores', 'id'),
      ('competidores', 'parque_id'),
      ('duplas', 'id'),
      ('duplas', 'evento_id'),
      ('duplas', 'categoria_id'),
      ('duplas', 'puxador_id')
    ) as required(table_name, column_name)
  loop
    select c.data_type
      into v_data_type
      from information_schema.columns c
     where c.table_schema = 'public'
       and c.table_name = v_column.table_name
       and c.column_name = v_column.column_name;

    if v_data_type is distinct from 'uuid' then
      raise exception 'Expected public.%.% to be uuid, found %',
        v_column.table_name, v_column.column_name, coalesce(v_data_type, 'missing');
    end if;
  end loop;

  select count(*) into v_inconsistent_duplas
    from public.duplas d
    left join public.categorias c
      on c.id = d.categoria_id
     and c.evento_id = d.evento_id
   where d.categoria_id is null
      or c.id is null;

  if v_inconsistent_duplas > 0 then
    raise exception '% duplas have a missing or cross-event category; repair is required before adding the composite FK',
      v_inconsistent_duplas;
  end if;
end;
$$;

-- Composite unique keys are targets for the event/category integrity FKs below.
alter table public.categorias
  add constraint categorias_id_evento_pista_uq unique (id, evento_id);

alter table public.duplas
  alter column categoria_id set not null,
  add constraint duplas_id_evento_categoria_pista_uq
    unique (id, evento_id, categoria_id),
  add constraint duplas_categoria_evento_pista_fk
    foreign key (categoria_id, evento_id)
    references public.categorias (id, evento_id)
    on update restrict on delete restrict;

create table public.pista_membros_evento (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.eventos (id) on delete restrict,
  usuario_id uuid not null references auth.users (id) on delete restrict,
  funcao text not null check (funcao in ('organizador', 'escritorio', 'locutor')),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  criado_por uuid references auth.users (id) on delete restrict,
  revogado_em timestamptz,
  revogado_por uuid references auth.users (id) on delete restrict,
  constraint pista_membros_revogacao_ck check (
    (ativo and revogado_em is null and revogado_por is null)
    or (not ativo and revogado_em is not null and revogado_por is not null)
  ),
  constraint pista_membros_id_evento_uq unique (id, evento_id)
);

create unique index pista_membros_ativos_uq
  on public.pista_membros_evento (evento_id, usuario_id, funcao)
  where ativo;

create table public.pista_evento_config (
  evento_id uuid primary key references public.eventos (id) on delete restrict,
  permite_substituicao boolean not null default false,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid not null references auth.users (id) on delete restrict
);

create table public.pista_rodizios (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null,
  categoria_id uuid not null,
  numero integer not null check (numero > 0),
  quantidade_bois integer not null check (quantidade_bois > 0),
  estado text not null default 'planejado'
    check (estado in ('planejado', 'em_andamento', 'concluido')),
  criado_em timestamptz not null default now(),
  criado_por uuid not null references auth.users (id) on delete restrict,
  iniciado_em timestamptz,
  concluido_em timestamptz,
  constraint pista_rodizios_categoria_evento_fk
    foreign key (categoria_id, evento_id)
    references public.categorias (id, evento_id)
    on update restrict on delete restrict,
  constraint pista_rodizios_numero_uq unique (evento_id, categoria_id, numero),
  constraint pista_rodizios_escopo_uq unique (id, evento_id, categoria_id),
  constraint pista_rodizios_capacidade_uq unique (id, quantidade_bois),
  constraint pista_rodizios_timestamps_ck check (
    (estado = 'planejado' and iniciado_em is null and concluido_em is null)
    or (estado = 'em_andamento' and iniciado_em is not null and concluido_em is null)
    or (estado = 'concluido' and iniciado_em is not null and concluido_em is not null)
  )
);

create unique index pista_rodizios_ativos_categoria_uq
  on public.pista_rodizios (evento_id, categoria_id)
  where estado = 'em_andamento';

create table public.pista_fila (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null,
  categoria_id uuid not null,
  rodizio_id uuid not null,
  dupla_id uuid not null,
  numero_corrida smallint not null check (numero_corrida in (1, 2)),
  ordem bigint not null check (ordem > 0),
  estado text not null default 'aguardando'
    check (estado in (
      'aguardando', 'reservada', 'chamada', 'em_corrida',
      'retorno_pendente', 'concluida', 'encaminhada', 'rabo_da_gata'
    )),
  posicao_boi integer,
  competidor_id uuid references public.competidores (id) on delete restrict,
  origem_fila_id uuid,
  criado_em timestamptz not null default now(),
  criado_por uuid not null references auth.users (id) on delete restrict,
  constraint pista_fila_rodizio_fk
    foreign key (rodizio_id, evento_id, categoria_id)
    references public.pista_rodizios (id, evento_id, categoria_id)
    on update restrict on delete restrict,
  constraint pista_fila_dupla_fk
    foreign key (dupla_id, evento_id, categoria_id)
    references public.duplas (id, evento_id, categoria_id)
    on update restrict on delete restrict,
  constraint pista_fila_origem_fk
    foreign key (origem_fila_id, evento_id, categoria_id, dupla_id, numero_corrida)
    references public.pista_fila (id, evento_id, categoria_id, dupla_id, numero_corrida)
    on update restrict on delete restrict,
  constraint pista_fila_posicao_estado_ck check (
    (estado in ('reservada', 'em_corrida') and posicao_boi is not null)
    or estado = 'chamada'
    or (estado not in ('reservada', 'em_corrida', 'chamada') and posicao_boi is null)
  ),
  constraint pista_fila_competidor_corrida_ck check (
    (estado = 'em_corrida') = (competidor_id is not null)
  ),
  constraint pista_fila_id_rodizio_uq unique (id, rodizio_id),
  constraint pista_fila_historico_uq
    unique (id, evento_id, categoria_id, rodizio_id, dupla_id, numero_corrida),
  constraint pista_fila_origem_escopo_uq
    unique (id, evento_id, categoria_id, dupla_id, numero_corrida),
  constraint pista_fila_ordem_uq unique (rodizio_id, ordem)
    deferrable initially deferred
);

create table public.pista_posicoes (
  rodizio_id uuid not null,
  numero integer not null check (numero > 0),
  quantidade_bois integer not null,
  estado text not null default 'livre'
    check (estado in ('livre', 'reservada', 'consumida')),
  fila_id uuid,
  primary key (rodizio_id, numero),
  constraint pista_posicoes_rodizio_fk
    foreign key (rodizio_id, quantidade_bois)
    references public.pista_rodizios (id, quantidade_bois)
    on update restrict on delete restrict,
  constraint pista_posicoes_capacidade_ck check (numero <= quantidade_bois),
  constraint pista_posicoes_fila_fk
    foreign key (fila_id, rodizio_id)
    references public.pista_fila (id, rodizio_id)
    on update restrict on delete restrict,
  constraint pista_posicoes_estado_fila_ck check (
    (estado = 'livre' and fila_id is null)
    or (estado in ('reservada', 'consumida') and fila_id is not null)
  )
);

alter table public.pista_fila
  add constraint pista_fila_posicao_fk
    foreign key (rodizio_id, posicao_boi)
    references public.pista_posicoes (rodizio_id, numero)
    on update restrict on delete restrict;

create unique index pista_posicoes_fila_uq
  on public.pista_posicoes (fila_id)
  where fila_id is not null;

create index pista_fila_proxima_idx
  on public.pista_fila (rodizio_id, ordem)
  where estado in ('aguardando', 'reservada');

create unique index pista_fila_uma_ativa_rodizio_uq
  on public.pista_fila (rodizio_id)
  where estado in ('chamada', 'em_corrida');

create table public.pista_corridas (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null,
  categoria_id uuid not null,
  rodizio_id uuid not null,
  fila_id uuid not null,
  dupla_id uuid not null,
  numero_corrida smallint not null check (numero_corrida in (1, 2)),
  posicao_boi integer not null,
  competidor_id uuid not null references public.competidores (id) on delete restrict,
  resultado text not null check (resultado in ('valeu_boi', 'zero')),
  pontuacao numeric not null,
  juiz_informado_por uuid not null references auth.users (id) on delete restrict,
  registrado_em timestamptz not null default now(),
  constraint pista_corridas_fila_fk
    foreign key (fila_id, evento_id, categoria_id, rodizio_id, dupla_id, numero_corrida)
    references public.pista_fila
      (id, evento_id, categoria_id, rodizio_id, dupla_id, numero_corrida)
    on update restrict on delete restrict,
  constraint pista_corridas_posicao_fk
    foreign key (rodizio_id, posicao_boi)
    references public.pista_posicoes (rodizio_id, numero)
    on update restrict on delete restrict,
  constraint pista_corridas_resultado_ck
    check (resultado <> 'zero' or pontuacao = 0),
  constraint pista_corridas_uma_por_numero_uq unique (dupla_id, numero_corrida),
  constraint pista_corridas_posicao_uq unique (rodizio_id, posicao_boi)
);

create table public.pista_correcoes_corrida (
  id uuid primary key default gen_random_uuid(),
  corrida_id uuid not null references public.pista_corridas (id) on delete restrict,
  revisao integer not null check (revisao > 0),
  resultado text not null check (resultado in ('valeu_boi', 'zero')),
  pontuacao numeric not null,
  corrigido_por uuid not null references auth.users (id) on delete restrict,
  corrigido_em timestamptz not null default now(),
  constraint pista_correcao_zero_ck check (resultado <> 'zero' or pontuacao = 0),
  constraint pista_correcao_revisao_uq unique (corrida_id, revisao)
);

create index pista_correcao_corrida_historico_idx
  on public.pista_correcoes_corrida (corrida_id, corrigido_em, id);

create view public.pista_resultados_vigentes
with (security_invoker = true)
as
select r.id as corrida_id,
       r.evento_id,
       r.categoria_id,
       r.rodizio_id,
       r.dupla_id,
       r.numero_corrida,
       coalesce(c.resultado, r.resultado) as resultado,
       coalesce(c.pontuacao, r.pontuacao) as pontuacao
  from public.pista_corridas r
  left join lateral (
    select cc.resultado, cc.pontuacao
      from public.pista_correcoes_corrida cc
     where cc.corrida_id = r.id
    order by cc.revisao desc
     limit 1
  ) c on true;

create view public.pista_parciais
with (security_invoker = true)
as
select r.evento_id,
       r.categoria_id,
       r.dupla_id,
       count(*)::integer as corridas_concluidas,
       sum(r.pontuacao) as pontuacao_total
  from public.pista_resultados_vigentes r
 group by r.evento_id, r.categoria_id, r.dupla_id;

create table public.pista_ocorrencias (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null,
  categoria_id uuid not null,
  rodizio_id uuid not null,
  fila_id uuid not null,
  dupla_id uuid not null,
  numero_corrida smallint not null check (numero_corrida in (1, 2)),
  tipo text not null check (tipo in ('retorno', 'rabo_da_gata', 'retorno_liberado')),
  posicao_boi integer,
  destino text check (destino in ('rodizio_atual', 'proximo_rodizio')),
  destino_rodizio_id uuid,
  origem_ocorrencia_id uuid references public.pista_ocorrencias (id) on delete restrict,
  registrado_por uuid not null references auth.users (id) on delete restrict,
  registrado_em timestamptz not null default now(),
  constraint pista_ocorrencias_fila_fk
    foreign key (fila_id, evento_id, categoria_id, rodizio_id, dupla_id, numero_corrida)
    references public.pista_fila
      (id, evento_id, categoria_id, rodizio_id, dupla_id, numero_corrida)
    on update restrict on delete restrict,
  constraint pista_ocorrencias_posicao_fk
    foreign key (rodizio_id, posicao_boi)
    references public.pista_posicoes (rodizio_id, numero)
    on update restrict on delete restrict,
  constraint pista_ocorrencias_destino_fk
    foreign key (destino_rodizio_id, evento_id, categoria_id)
    references public.pista_rodizios (id, evento_id, categoria_id)
    on update restrict on delete restrict,
  constraint pista_ocorrencias_origem_ck check (
    (tipo = 'retorno' and posicao_boi is not null and destino is null
      and destino_rodizio_id is null and origem_ocorrencia_id is null)
    or (tipo = 'rabo_da_gata' and posicao_boi is null and destino is null
      and destino_rodizio_id is not null and origem_ocorrencia_id is null)
    or (tipo = 'retorno_liberado' and destino is not null and destino_rodizio_id is not null
      and origem_ocorrencia_id is not null
      and ((destino = 'rodizio_atual' and posicao_boi is not null)
        or (destino = 'proximo_rodizio' and posicao_boi is null)))
  ),
  constraint pista_ocorrencias_id_escopo_uq
    unique (id, evento_id, categoria_id, rodizio_id, fila_id, dupla_id)
);

create unique index pista_retorno_liberado_unico_idx
  on public.pista_ocorrencias (origem_ocorrencia_id)
  where tipo = 'retorno_liberado';

create index pista_ocorrencias_inscricao_historico_idx
  on public.pista_ocorrencias (dupla_id, registrado_em, id);

create table public.pista_premiacoes (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null,
  categoria_id uuid not null,
  colocacao integer not null check (colocacao > 0),
  versao integer not null check (versao > 0),
  valor numeric not null,
  termos text not null,
  criado_por uuid not null references auth.users (id) on delete restrict,
  criado_em timestamptz not null default now(),
  constraint pista_premiacoes_categoria_fk
    foreign key (categoria_id, evento_id)
    references public.categorias (id, evento_id)
    on update restrict on delete restrict,
  constraint pista_premiacoes_versao_uq
    unique (evento_id, categoria_id, colocacao, versao)
);

create view public.pista_premiacoes_vigentes
with (security_invoker = true)
as
select distinct on (evento_id, categoria_id, colocacao)
       id, evento_id, categoria_id, colocacao, versao, valor, termos,
       criado_por, criado_em
  from public.pista_premiacoes
 order by evento_id, categoria_id, colocacao, versao desc;

create table public.pista_empates (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null,
  categoria_id uuid not null,
  colocacao integer not null check (colocacao > 0),
  decisao text not null check (decisao in ('continuar_disputa', 'racha')),
  termos text not null,
  registrado_por uuid not null references auth.users (id) on delete restrict,
  registrado_em timestamptz not null default now(),
  constraint pista_empates_categoria_fk
    foreign key (categoria_id, evento_id)
    references public.categorias (id, evento_id)
    on update restrict on delete restrict,
  constraint pista_empates_id_escopo_uq unique (id, evento_id, categoria_id)
);

create table public.pista_empate_inscricoes (
  empate_id uuid not null,
  evento_id uuid not null,
  categoria_id uuid not null,
  dupla_id uuid not null,
  valor_acordado numeric,
  primary key (empate_id, dupla_id),
  constraint pista_empate_inscricoes_empate_fk
    foreign key (empate_id, evento_id, categoria_id)
    references public.pista_empates (id, evento_id, categoria_id)
    on update restrict on delete restrict,
  constraint pista_empate_inscricoes_dupla_fk
    foreign key (dupla_id, evento_id, categoria_id)
    references public.duplas (id, evento_id, categoria_id)
    on update restrict on delete restrict
);

-- This helper is SECURITY DEFINER only to avoid RLS recursion while reading
-- the membership table. Every RPC still performs explicit role/event checks.
create function public.pista_tem_funcao(p_evento_id uuid, p_funcoes text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and exists (
       select 1
         from public.eventos e
         join public.pista_membros_evento m on m.evento_id = e.id
        where e.id = p_evento_id
          and e.parque_id = public.meu_parque_id()
          and m.usuario_id = auth.uid()
          and m.ativo
          and m.funcao = any (p_funcoes)
     );
$$;

create function public.pista_exigir_funcao(p_evento_id uuid, p_funcoes text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null
     or not public.pista_tem_funcao(p_evento_id, p_funcoes) then
    raise exception 'Acesso negado para este evento'
      using errcode = '42501';
  end if;
end;
$$;

create function public.pista_ativar_planejado(p_evento_id uuid, p_categoria_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rodizio public.pista_rodizios%rowtype;
begin
  if exists (
    select 1 from public.pista_rodizios r
     where r.evento_id = p_evento_id
       and r.categoria_id = p_categoria_id
       and r.estado = 'em_andamento'
  ) then
    return null;
  end if;

  select * into v_rodizio
    from public.pista_rodizios r
   where r.evento_id = p_evento_id
     and r.categoria_id = p_categoria_id
     and r.estado = 'planejado'
     and exists (
       select 1 from public.pista_fila f
        where f.rodizio_id = r.id
          and f.estado in ('aguardando', 'reservada')
     )
   order by r.numero
   limit 1
   for update;

  if not found then
    return null;
  end if;

  update public.pista_rodizios
     set estado = 'em_andamento', iniciado_em = now()
   where id = v_rodizio.id;

  insert into public.pista_posicoes (rodizio_id, numero, quantidade_bois)
  select v_rodizio.id, n, v_rodizio.quantidade_bois
    from pg_catalog.generate_series(1, v_rodizio.quantidade_bois) as s(n);

  return v_rodizio.id;
end;
$$;

create function public.pista_tentar_avancar(p_rodizio_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_atual public.pista_rodizios%rowtype;
  v_proximo public.pista_rodizios%rowtype;
  v_fila_id uuid;
  v_ordem bigint;
  v_disponiveis integer;
begin
  select * into v_atual
    from public.pista_rodizios
   where id = p_rodizio_id
   for update;

  if not found or v_atual.estado <> 'em_andamento' then
    return null;
  end if;

  select count(*) into v_disponiveis
    from public.pista_posicoes p
   where p.rodizio_id = v_atual.id
     and p.estado = 'livre';

  if v_disponiveis = 0 and exists (
    select 1 from public.pista_fila f
     where f.rodizio_id = v_atual.id
       and (f.estado = 'aguardando'
         or (f.estado = 'chamada' and f.posicao_boi is null))
  ) then
    select * into v_proximo
      from public.pista_rodizios r
     where r.evento_id = v_atual.evento_id
       and r.categoria_id = v_atual.categoria_id
       and r.estado = 'planejado'
     order by r.numero
     limit 1
     for update;

    if found then
      for v_fila_id in
        select f.id
          from public.pista_fila f
         where f.rodizio_id = v_atual.id
           and (f.estado = 'aguardando'
             or (f.estado = 'chamada' and f.posicao_boi is null))
         order by f.ordem
         for update
      loop
        update public.pista_fila
           set estado = 'encaminhada'
         where id = v_fila_id;

        select coalesce(max(f.ordem), 0) + 1 into v_ordem
          from public.pista_fila f
         where f.rodizio_id = v_proximo.id;

        insert into public.pista_fila (
          evento_id, categoria_id, rodizio_id, dupla_id, numero_corrida,
          ordem, estado, origem_fila_id, criado_por
        )
        select f.evento_id, f.categoria_id, v_proximo.id, f.dupla_id,
             f.numero_corrida, v_ordem, 'aguardando', f.id, auth.uid()
          from public.pista_fila f
           where f.id = v_fila_id;
      end loop;
    end if;
  end if;

  if exists (
    select 1 from public.pista_fila f
     where f.rodizio_id = v_atual.id
       and f.estado in ('aguardando', 'reservada', 'chamada', 'em_corrida')
  ) then
    return null;
  end if;

  update public.pista_rodizios
     set estado = 'concluido', concluido_em = now()
   where id = v_atual.id;

  return public.pista_ativar_planejado(v_atual.evento_id, v_atual.categoria_id);
end;
$$;

create function public.pista_configurar_evento(
  p_evento_id uuid,
  p_permite_substituicao boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.pista_exigir_funcao(p_evento_id, array['organizador']::text[]);
  insert into public.pista_evento_config
    (evento_id, permite_substituicao, atualizado_por)
  values (p_evento_id, p_permite_substituicao, auth.uid())
  on conflict (evento_id) do update
    set permite_substituicao = excluded.permite_substituicao,
        atualizado_em = now(), atualizado_por = auth.uid();
end;
$$;

create function public.pista_designar_membro(
  p_evento_id uuid,
  p_usuario_id uuid,
  p_funcao text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parque_evento uuid;
  v_parque_usuario uuid;
  v_id uuid;
begin
  perform public.pista_exigir_funcao(p_evento_id, array['organizador']::text[]);
  if p_funcao not in ('organizador', 'escritorio', 'locutor') then
    raise exception 'Função de evento inválida' using errcode = '22023';
  end if;

  select parque_id into v_parque_evento
    from public.eventos where id = p_evento_id;
  select parque_id into v_parque_usuario
    from public.perfis where id = p_usuario_id;

  if v_parque_evento is null or v_parque_usuario is distinct from v_parque_evento then
    raise exception 'Usuário e evento devem pertencer ao mesmo parque'
      using errcode = '23514';
  end if;

  update public.pista_membros_evento
     set ativo = true, revogado_em = null, revogado_por = null
   where evento_id = p_evento_id
     and usuario_id = p_usuario_id
     and funcao = p_funcao
     and ativo
  returning id into v_id;

  if v_id is null then
    insert into public.pista_membros_evento
      (evento_id, usuario_id, funcao, criado_por)
    values (p_evento_id, p_usuario_id, p_funcao, auth.uid())
    returning id into v_id;
  end if;
  return v_id;
end;
$$;

create function public.pista_revogar_membro(p_membro_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_evento_id uuid;
begin
  select evento_id into v_evento_id
    from public.pista_membros_evento where id = p_membro_id for update;
  if v_evento_id is null then
    raise exception 'Atribuição não encontrada' using errcode = 'P0002';
  end if;
  perform public.pista_exigir_funcao(v_evento_id, array['organizador']::text[]);
  update public.pista_membros_evento
     set ativo = false, revogado_em = now(), revogado_por = auth.uid()
   where id = p_membro_id and ativo;
end;
$$;

create function public.pista_planejar_rodizio(
  p_evento_id uuid,
  p_categoria_id uuid,
  p_quantidade_bois integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_numero integer;
  v_id uuid;
begin
  perform public.pista_exigir_funcao(p_evento_id, array['organizador']::text[]);
  if p_quantidade_bois <= 0 then
    raise exception 'A quantidade de bois deve ser positiva' using errcode = '22023';
  end if;

  perform 1 from public.categorias
   where id = p_categoria_id and evento_id = p_evento_id
   for update;
  if not found then
    raise exception 'Categoria não pertence ao evento' using errcode = '23514';
  end if;

  select coalesce(max(numero), 0) + 1 into v_numero
    from public.pista_rodizios
   where evento_id = p_evento_id and categoria_id = p_categoria_id;

  insert into public.pista_rodizios
    (evento_id, categoria_id, numero, quantidade_bois, criado_por)
  values (p_evento_id, p_categoria_id, v_numero, p_quantidade_bois, auth.uid())
  returning id into v_id;

  perform public.pista_tentar_avancar(
    coalesce((select r.id from public.pista_rodizios r
               where r.evento_id = p_evento_id
                 and r.categoria_id = p_categoria_id
                 and r.estado = 'em_andamento'), v_id)
  );
  if not exists (select 1 from public.pista_rodizios r
                  where r.evento_id = p_evento_id
                    and r.categoria_id = p_categoria_id
                    and r.estado = 'em_andamento') then
    perform public.pista_ativar_planejado(p_evento_id, p_categoria_id);
  end if;

  return v_id;
end;
$$;

create function public.pista_iniciar_rodizio(
  p_rodizio_id uuid,
  p_duplas uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rodizio public.pista_rodizios%rowtype;
  v_evento_id uuid;
  v_categoria_id uuid;
begin
  select r.evento_id, r.categoria_id into v_evento_id, v_categoria_id
    from public.pista_rodizios r where r.id = p_rodizio_id;
  if v_evento_id is null then
    raise exception 'Rodízio não encontrado' using errcode = 'P0002';
  end if;
  perform public.pista_exigir_funcao(v_evento_id, array['organizador', 'locutor']::text[]);
  perform 1 from public.categorias
   where id = v_categoria_id and evento_id = v_evento_id for update;
  select * into v_rodizio from public.pista_rodizios
   where id = p_rodizio_id for update;

  if v_rodizio.estado <> 'planejado'
     or exists (select 1 from public.pista_rodizios r
                 where r.evento_id = v_rodizio.evento_id
                   and r.categoria_id = v_rodizio.categoria_id
                   and r.estado = 'em_andamento') then
    raise exception 'A categoria já possui rodízio ativo ou este rodízio não está planejado'
      using errcode = '23514';
  end if;
  if coalesce(cardinality(p_duplas), 0) = 0
     or cardinality(p_duplas) <> (
       select count(distinct selected.id) from unnest(p_duplas) as selected(id)
     ) then
    raise exception 'Informe inscrições distintas para iniciar a fila' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(p_duplas) as selected(id)
    left join public.duplas d on d.id = selected.id
      and d.evento_id = v_rodizio.evento_id
      and d.categoria_id = v_rodizio.categoria_id
    where d.id is null or d.status_pagamento = 'cancelado'
  ) then
    raise exception 'Todas as inscrições devem pertencer ao evento e categoria do rodízio e não podem estar canceladas'
      using errcode = '23514';
  end if;

  update public.pista_rodizios
     set estado = 'em_andamento', iniciado_em = now()
   where id = v_rodizio.id;
  insert into public.pista_posicoes (rodizio_id, numero, quantidade_bois)
  select v_rodizio.id, n, v_rodizio.quantidade_bois
    from pg_catalog.generate_series(1, v_rodizio.quantidade_bois) s(n);

  insert into public.pista_fila (
    evento_id, categoria_id, rodizio_id, dupla_id, numero_corrida,
    ordem, estado, criado_por
  )
  select v_rodizio.evento_id, v_rodizio.categoria_id, v_rodizio.id,
         d.id, runs.numero_corrida,
         row_number() over (order by d.numero_senha, d.created_at, runs.numero_corrida),
         'aguardando', auth.uid()
    from unnest(p_duplas) selected(id)
    join public.duplas d on d.id = selected.id
    cross join (values (1::smallint), (2::smallint)) runs(numero_corrida)
   order by d.numero_senha, d.created_at, runs.numero_corrida;
end;
$$;

create function public.pista_chamar_proxima(p_rodizio_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rodizio public.pista_rodizios%rowtype;
  v_fila public.pista_fila%rowtype;
  v_evento_id uuid;
begin
  select evento_id into v_evento_id from public.pista_rodizios where id = p_rodizio_id;
  if v_evento_id is null then
    raise exception 'Rodízio não encontrado' using errcode = 'P0002';
  end if;
  perform public.pista_exigir_funcao(v_evento_id, array['organizador', 'locutor']::text[]);
  select * into v_rodizio from public.pista_rodizios
   where id = p_rodizio_id for update;
  if not found or v_rodizio.estado <> 'em_andamento' then
    raise exception 'Rodízio não está em andamento' using errcode = '23514';
  end if;
  if exists (select 1 from public.pista_fila f where f.rodizio_id = p_rodizio_id
              and f.estado in ('chamada', 'em_corrida')) then
    raise exception 'Já há uma inscrição em operação neste rodízio' using errcode = '23514';
  end if;

  select * into v_fila from public.pista_fila f
   where f.rodizio_id = p_rodizio_id and f.estado in ('aguardando', 'reservada')
   order by f.ordem
   limit 1 for update skip locked;
  if not found then
    perform public.pista_tentar_avancar(p_rodizio_id);
    return null;
  end if;

  if v_fila.estado = 'aguardando'
     and not exists (select 1 from public.pista_posicoes p
                      where p.rodizio_id = p_rodizio_id and p.estado = 'livre') then
    perform public.pista_tentar_avancar(p_rodizio_id);
    return null;
  end if;

  update public.pista_fila set estado = 'chamada' where id = v_fila.id;
  return v_fila.id;
end;
$$;

create function public.pista_iniciar_corrida(
  p_fila_id uuid,
  p_competidor_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fila public.pista_fila%rowtype;
  v_rodizio public.pista_rodizios%rowtype;
  v_rodizio_id uuid;
  v_evento_id uuid;
  v_evento_parque uuid;
  v_puxador_id uuid;
  v_permite_substituicao boolean;
  v_posicao integer;
begin
  select rodizio_id, evento_id into v_rodizio_id, v_evento_id
    from public.pista_fila where id = p_fila_id;
  if v_rodizio_id is null then raise exception 'Fila não encontrada' using errcode = 'P0002'; end if;
  perform public.pista_exigir_funcao(v_evento_id, array['organizador', 'locutor']::text[]);
  select * into v_rodizio from public.pista_rodizios where id = v_rodizio_id for update;
  select * into v_fila from public.pista_fila where id = p_fila_id for update;
  if v_rodizio.estado <> 'em_andamento' or v_fila.estado <> 'chamada' then
    raise exception 'Inscrição não está chamada em rodízio ativo' using errcode = '23514';
  end if;

  select e.parque_id, d.puxador_id, coalesce(c.permite_substituicao, false)
    into v_evento_parque, v_puxador_id, v_permite_substituicao
    from public.eventos e
    join public.duplas d on d.evento_id = e.id and d.id = v_fila.dupla_id
    left join public.pista_evento_config c on c.evento_id = e.id
   where e.id = v_fila.evento_id;

  if not exists (select 1 from public.competidores c
                  where c.id = p_competidor_id and c.parque_id = v_evento_parque) then
    raise exception 'Competidor não pertence ao parque do evento' using errcode = '23514';
  end if;
  if p_competidor_id <> v_puxador_id and not v_permite_substituicao then
    raise exception 'Substituição não está permitida neste evento' using errcode = '42501';
  end if;

  if v_fila.posicao_boi is not null then
    select p.numero into v_posicao from public.pista_posicoes p
     where p.rodizio_id = v_rodizio.id
       and p.numero = v_fila.posicao_boi
       and p.estado = 'reservada'
       and p.fila_id = v_fila.id
     for update;
  else
    select p.numero into v_posicao from public.pista_posicoes p
     where p.rodizio_id = v_rodizio.id and p.estado = 'livre'
     order by p.numero limit 1 for update skip locked;
  end if;
  if v_posicao is null then
    update public.pista_fila set estado = 'aguardando', competidor_id = null
     where id = v_fila.id and estado = 'chamada' and posicao_boi is null;
    perform public.pista_tentar_avancar(v_rodizio.id);
    return null;
  end if;

  if v_fila.posicao_boi is null then
    update public.pista_posicoes
       set estado = 'reservada', fila_id = v_fila.id
     where rodizio_id = v_rodizio.id and numero = v_posicao and estado = 'livre';
    if not found then
      raise exception 'A posição deixou de estar disponível' using errcode = '23514';
    end if;
  end if;
  update public.pista_fila
     set estado = 'em_corrida', posicao_boi = v_posicao, competidor_id = p_competidor_id
   where id = v_fila.id;
  return v_posicao;
end;
$$;

create function public.pista_registrar_resultado(
  p_fila_id uuid,
  p_resultado text,
  p_pontuacao numeric
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fila public.pista_fila%rowtype;
  v_corrida_id uuid;
  v_rodizio_id uuid;
  v_evento_id uuid;
begin
  select rodizio_id, evento_id into v_rodizio_id, v_evento_id
    from public.pista_fila where id = p_fila_id;
  if v_rodizio_id is null then
    raise exception 'Não há corrida ativa para esta inscrição' using errcode = '23514';
  end if;
  perform public.pista_exigir_funcao(v_evento_id, array['organizador', 'locutor']::text[]);
  perform 1 from public.pista_rodizios where id = v_rodizio_id for update;
  select * into v_fila from public.pista_fila where id = p_fila_id for update;
  if v_fila.estado <> 'em_corrida' then
    raise exception 'Não há corrida ativa para esta inscrição' using errcode = '23514';
  end if;
  if p_resultado not in ('valeu_boi', 'zero') or p_pontuacao is null
     or (p_resultado = 'zero' and p_pontuacao <> 0) then
    raise exception 'Resultado ou pontuação inválidos' using errcode = '22023';
  end if;

  insert into public.pista_corridas (
    evento_id, categoria_id, rodizio_id, fila_id, dupla_id,
    numero_corrida, posicao_boi, competidor_id, resultado, pontuacao, juiz_informado_por
  ) values (
    v_fila.evento_id, v_fila.categoria_id, v_fila.rodizio_id, v_fila.id,
    v_fila.dupla_id, v_fila.numero_corrida, v_fila.posicao_boi,
    v_fila.competidor_id, p_resultado, p_pontuacao, auth.uid()
  ) returning id into v_corrida_id;

  update public.pista_posicoes set estado = 'consumida'
   where rodizio_id = v_fila.rodizio_id and numero = v_fila.posicao_boi
     and fila_id = v_fila.id and estado = 'reservada';
  if not found then
    raise exception 'A posição da corrida não está reservada' using errcode = '23514';
  end if;
  update public.pista_fila set estado = 'concluida', posicao_boi = null
   where id = v_fila.id;
  perform public.pista_tentar_avancar(v_fila.rodizio_id);
  return v_corrida_id;
end;
$$;

create function public.pista_registrar_retorno(p_fila_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fila public.pista_fila%rowtype;
  v_ocorrencia_id uuid;
  v_rodizio_id uuid;
begin
  select rodizio_id into v_rodizio_id from public.pista_fila where id = p_fila_id;
  if v_rodizio_id is null then
    raise exception 'Retorno exige corrida em andamento' using errcode = '23514';
  end if;
  perform 1 from public.pista_rodizios where id = v_rodizio_id for update;
  select * into v_fila from public.pista_fila where id = p_fila_id for update;
  if v_fila.estado <> 'em_corrida' then
    raise exception 'Retorno exige corrida em andamento' using errcode = '23514';
  end if;
  perform public.pista_exigir_funcao(v_fila.evento_id, array['organizador', 'locutor']::text[]);

  insert into public.pista_ocorrencias (
    evento_id, categoria_id, rodizio_id, fila_id, dupla_id, numero_corrida, tipo,
    posicao_boi, registrado_por
  ) values (
    v_fila.evento_id, v_fila.categoria_id, v_fila.rodizio_id, v_fila.id,
    v_fila.dupla_id, v_fila.numero_corrida, 'retorno', v_fila.posicao_boi, auth.uid()
  ) returning id into v_ocorrencia_id;

  -- Keep the same reserved position attached to this pending regular run.
  update public.pista_fila
     set estado = 'retorno_pendente', posicao_boi = null, competidor_id = null
   where id = v_fila.id;
  perform public.pista_tentar_avancar(v_fila.rodizio_id);
  return v_ocorrencia_id;
end;
$$;

create function public.pista_registrar_rabo_da_gata(p_fila_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fila public.pista_fila%rowtype;
  v_rodizio public.pista_rodizios%rowtype;
  v_destino public.pista_rodizios%rowtype;
  v_ordem bigint;
  v_nova_fila uuid;
  v_ocorrencia_id uuid;
  v_rodizio_id uuid;
begin
  select rodizio_id into v_rodizio_id from public.pista_fila where id = p_fila_id;
  if v_rodizio_id is null then
    raise exception 'Rabo da Gata só pode ser registrado para inscrição chamada, antes da corrida'
      using errcode = '23514';
  end if;
  perform 1 from public.pista_rodizios where id = v_rodizio_id for update;
  select * into v_fila from public.pista_fila where id = p_fila_id for update;
  if v_fila.estado <> 'chamada' then
    raise exception 'Rabo da Gata só pode ser registrado para inscrição chamada, antes da corrida'
      using errcode = '23514';
  end if;
  perform public.pista_exigir_funcao(v_fila.evento_id, array['organizador', 'locutor']::text[]);
  select * into v_rodizio from public.pista_rodizios where id = v_fila.rodizio_id for update;

  if v_fila.posicao_boi is not null then
    update public.pista_posicoes set estado = 'livre', fila_id = null
     where rodizio_id = v_fila.rodizio_id and numero = v_fila.posicao_boi
       and fila_id = v_fila.id and estado = 'reservada';
    if not found then
      raise exception 'A reserva da posição não pôde ser liberada' using errcode = '23514';
    end if;
    update public.pista_fila set posicao_boi = null where id = v_fila.id;
    v_fila.posicao_boi := null;
  end if;

  if exists (select 1 from public.pista_posicoes p
              where p.rodizio_id = v_rodizio.id and p.estado = 'livre') then
    v_destino := v_rodizio;
  else
    select * into v_destino from public.pista_rodizios r
     where r.evento_id = v_fila.evento_id and r.categoria_id = v_fila.categoria_id
       and r.estado = 'planejado'
     order by r.numero limit 1 for update;
    if not found then
      raise exception 'Não há posição livre nem próximo rodízio planejado'
        using errcode = '23514';
    end if;
  end if;

  select coalesce(max(f.ordem), 0) + 1 into v_ordem
    from public.pista_fila f where f.rodizio_id = v_destino.id;
  update public.pista_fila set estado = 'rabo_da_gata' where id = v_fila.id;
  -- Requeue at the tail without taking a position from races already ahead.
  insert into public.pista_fila (
    evento_id, categoria_id, rodizio_id, dupla_id, numero_corrida,
    ordem, estado, posicao_boi, origem_fila_id, criado_por
  ) values (
    v_fila.evento_id, v_fila.categoria_id, v_destino.id, v_fila.dupla_id,
    v_fila.numero_corrida, v_ordem, 'aguardando', null,
    v_fila.id, auth.uid()
  ) returning id into v_nova_fila;

  insert into public.pista_ocorrencias (
    evento_id, categoria_id, rodizio_id, fila_id, dupla_id, numero_corrida,
    tipo, destino_rodizio_id, registrado_por
  ) values (
    v_fila.evento_id, v_fila.categoria_id, v_fila.rodizio_id, v_fila.id,
    v_fila.dupla_id, v_fila.numero_corrida, 'rabo_da_gata', v_destino.id, auth.uid()
  ) returning id into v_ocorrencia_id;
  perform public.pista_tentar_avancar(v_fila.rodizio_id);
  return v_ocorrencia_id;
end;
$$;

create function public.pista_liberar_retorno(
  p_ocorrencia_id uuid,
  p_destino text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ocorrencia public.pista_ocorrencias%rowtype;
  v_fila public.pista_fila%rowtype;
  v_atual public.pista_rodizios%rowtype;
  v_destino public.pista_rodizios%rowtype;
  v_posicao integer;
  v_ordem bigint;
  v_nova_fila uuid;
  v_liberacao_id uuid;
  v_rodizio_id uuid;
begin
  select rodizio_id into v_rodizio_id from public.pista_ocorrencias
   where id = p_ocorrencia_id and tipo = 'retorno';
  if v_rodizio_id is null then
    raise exception 'Retorno pendente não encontrado' using errcode = 'P0002';
  end if;
  perform 1 from public.pista_rodizios where id = v_rodizio_id for update;
  select * into v_ocorrencia from public.pista_ocorrencias
   where id = p_ocorrencia_id and tipo = 'retorno' for update;
  if not found then raise exception 'Retorno pendente não encontrado' using errcode = 'P0002'; end if;
  perform public.pista_exigir_funcao(v_ocorrencia.evento_id, array['organizador', 'locutor']::text[]);
  select * into v_fila from public.pista_fila where id = v_ocorrencia.fila_id for update;
  if v_fila.estado <> 'retorno_pendente' then
    raise exception 'Retorno já foi liberado ou não está pendente' using errcode = '23514';
  end if;
  if p_destino not in ('rodizio_atual', 'proximo_rodizio') then
    raise exception 'Destino deve ser escolhido explicitamente' using errcode = '22023';
  end if;

  select * into v_atual from public.pista_rodizios where id = v_fila.rodizio_id for update;
  if p_destino = 'rodizio_atual' then
    if v_atual.estado <> 'em_andamento' then
      raise exception 'O rodízio original não está ativo; escolha o próximo rodízio'
        using errcode = '23514';
    end if;
    select p.numero into v_posicao
      from public.pista_posicoes p
     where p.rodizio_id = v_atual.id
       and p.numero = v_ocorrencia.posicao_boi
       and p.estado = 'reservada'
       and p.fila_id = v_fila.id
     for update;
    if v_posicao is null then
      raise exception 'A posição reservada para este Retorno não está disponível'
        using errcode = '23514';
    end if;
    v_destino := v_atual;
  else
    update public.pista_posicoes
       set estado = 'livre', fila_id = null
     where rodizio_id = v_ocorrencia.rodizio_id
       and numero = v_ocorrencia.posicao_boi
       and fila_id = v_fila.id
       and estado = 'reservada';
    if not found then
      raise exception 'A posição reservada para este Retorno não está disponível'
        using errcode = '23514';
    end if;

    select * into v_destino from public.pista_rodizios r
     where r.evento_id = v_fila.evento_id and r.categoria_id = v_fila.categoria_id
       and r.estado = 'planejado'
     order by r.numero limit 1 for update;
    if not found then
      raise exception 'Não há próximo rodízio planejado' using errcode = '23514';
    end if;
  end if;

  select coalesce(max(f.ordem), 0) + 1 into v_ordem
    from public.pista_fila f where f.rodizio_id = v_destino.id;
  update public.pista_fila set estado = 'encaminhada' where id = v_fila.id;
  insert into public.pista_fila (
    evento_id, categoria_id, rodizio_id, dupla_id, numero_corrida,
    ordem, estado, posicao_boi, origem_fila_id, criado_por
  ) values (
    v_fila.evento_id, v_fila.categoria_id, v_destino.id, v_fila.dupla_id,
    v_fila.numero_corrida, v_ordem,
    case when v_destino.id = v_atual.id then 'reservada' else 'aguardando' end,
    case when v_destino.id = v_atual.id then v_posicao else null end,
    v_fila.id, auth.uid()
  ) returning id into v_nova_fila;

  if v_destino.id = v_atual.id then
    update public.pista_posicoes
       set fila_id = v_nova_fila
     where rodizio_id = v_atual.id
       and numero = v_posicao
       and fila_id = v_fila.id
       and estado = 'reservada';
    if not found then
      raise exception 'A posição reservada para este Retorno não está disponível'
        using errcode = '23514';
    end if;
  end if;

  insert into public.pista_ocorrencias (
    evento_id, categoria_id, rodizio_id, fila_id, dupla_id, numero_corrida,
    tipo, posicao_boi, destino, destino_rodizio_id, origem_ocorrencia_id, registrado_por
  ) values (
    v_fila.evento_id, v_fila.categoria_id, v_destino.id, v_nova_fila,
    v_fila.dupla_id, v_fila.numero_corrida, 'retorno_liberado', v_posicao,
    p_destino, v_destino.id,
    v_ocorrencia.id, auth.uid()
  ) returning id into v_liberacao_id;
  perform public.pista_tentar_avancar(v_fila.rodizio_id);
  perform public.pista_ativar_planejado(v_fila.evento_id, v_fila.categoria_id);
  return v_liberacao_id;
end;
$$;

create function public.pista_corrigir_resultado(
  p_corrida_id uuid,
  p_resultado text,
  p_pontuacao numeric
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_corrida public.pista_corridas%rowtype;
  v_correcao_id uuid;
  v_revisao integer;
begin
  select * into v_corrida from public.pista_corridas where id = p_corrida_id for update;
  if not found then raise exception 'Corrida não encontrada' using errcode = 'P0002'; end if;
  perform public.pista_exigir_funcao(v_corrida.evento_id, array['organizador', 'locutor']::text[]);
  if p_resultado not in ('valeu_boi', 'zero') or p_pontuacao is null
     or (p_resultado = 'zero' and p_pontuacao <> 0) then
    raise exception 'Resultado ou pontuação inválidos' using errcode = '22023';
  end if;
  select coalesce(max(c.revisao), 0) + 1 into v_revisao
    from public.pista_correcoes_corrida c
   where c.corrida_id = p_corrida_id;
  insert into public.pista_correcoes_corrida
    (corrida_id, revisao, resultado, pontuacao, corrigido_por)
  values (p_corrida_id, v_revisao, p_resultado, p_pontuacao, auth.uid())
  returning id into v_correcao_id;
  return v_correcao_id;
end;
$$;

create function public.pista_salvar_premiacao(
  p_evento_id uuid,
  p_categoria_id uuid,
  p_colocacao integer,
  p_valor numeric,
  p_termos text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_versao integer;
begin
  perform public.pista_exigir_funcao(p_evento_id, array['organizador']::text[]);
  if p_colocacao <= 0 or nullif(btrim(p_termos), '') is null then
    raise exception 'Colocação e termos são obrigatórios' using errcode = '22023';
  end if;

  perform 1 from public.categorias
   where id = p_categoria_id and evento_id = p_evento_id
   for update;
  if not found then
    raise exception 'Categoria não pertence ao evento' using errcode = '23514';
  end if;

  select coalesce(max(p.versao), 0) + 1 into v_versao
    from public.pista_premiacoes p
   where p.evento_id = p_evento_id
     and p.categoria_id = p_categoria_id
     and p.colocacao = p_colocacao;

  insert into public.pista_premiacoes
    (evento_id, categoria_id, colocacao, versao, valor, termos, criado_por)
  values (p_evento_id, p_categoria_id, p_colocacao, v_versao, p_valor, p_termos, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create function public.pista_registrar_empate(
  p_evento_id uuid,
  p_categoria_id uuid,
  p_colocacao integer,
  p_decisao text,
  p_termos text,
  p_participantes jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_empate_id uuid;
  v_participante jsonb;
  v_dupla_id uuid;
  v_valor numeric;
  v_count integer := 0;
begin
  perform public.pista_exigir_funcao(p_evento_id, array['organizador']::text[]);
  if p_colocacao <= 0
     or p_decisao not in ('continuar_disputa', 'racha')
     or nullif(btrim(p_termos), '') is null
     or jsonb_typeof(p_participantes) <> 'array' then
    raise exception 'Decisão de empate incompleta' using errcode = '22023';
  end if;
  insert into public.pista_empates
    (evento_id, categoria_id, colocacao, decisao, termos, registrado_por)
  values (p_evento_id, p_categoria_id, p_colocacao, p_decisao, p_termos, auth.uid())
  returning id into v_empate_id;

  for v_participante in select value from jsonb_array_elements(p_participantes)
  loop
    v_dupla_id := (v_participante->>'dupla_id')::uuid;
    v_valor := nullif(v_participante->>'valor_acordado', '')::numeric;
    if not exists (select 1 from public.duplas d
                    where d.id = v_dupla_id and d.evento_id = p_evento_id
                      and d.categoria_id = p_categoria_id) then
      raise exception 'Inscrição de empate deve pertencer ao evento e categoria'
        using errcode = '23514';
    end if;
    if (p_decisao = 'racha' and v_valor is null)
       or (p_decisao = 'continuar_disputa' and v_valor is not null) then
      raise exception 'Informe valores por inscrição apenas para racha'
        using errcode = '22023';
    end if;
    insert into public.pista_empate_inscricoes
      (empate_id, evento_id, categoria_id, dupla_id, valor_acordado)
    values (v_empate_id, p_evento_id, p_categoria_id, v_dupla_id, v_valor);
    v_count := v_count + 1;
  end loop;
  if v_count < 2 then
    raise exception 'Empate deve incluir ao menos duas inscrições' using errcode = '22023';
  end if;
  return v_empate_id;
end;
$$;

-- RLS is enabled on every table; authenticated users receive read-only access.
alter table public.pista_membros_evento enable row level security;
alter table public.pista_evento_config enable row level security;
alter table public.pista_rodizios enable row level security;
alter table public.pista_posicoes enable row level security;
alter table public.pista_fila enable row level security;
alter table public.pista_corridas enable row level security;
alter table public.pista_correcoes_corrida enable row level security;
alter table public.pista_ocorrencias enable row level security;
alter table public.pista_premiacoes enable row level security;
alter table public.pista_empates enable row level security;
alter table public.pista_empate_inscricoes enable row level security;

create policy pista_membros_select
  on public.pista_membros_evento for select to authenticated
  using (
    (usuario_id = auth.uid() and exists (
      select 1 from public.eventos e
       where e.id = pista_membros_evento.evento_id
         and e.parque_id = public.meu_parque_id()
    ))
    or public.pista_tem_funcao(evento_id, array['organizador']::text[])
  );

create policy pista_config_select
  on public.pista_evento_config for select to authenticated
  using (public.pista_tem_funcao(evento_id, array['organizador', 'escritorio', 'locutor']::text[]));

create policy pista_rodizios_select
  on public.pista_rodizios for select to authenticated
  using (public.pista_tem_funcao(evento_id, array['organizador', 'locutor']::text[]));
create policy pista_posicoes_select
  on public.pista_posicoes for select to authenticated
  using (exists (
    select 1 from public.pista_rodizios r
     where r.id = pista_posicoes.rodizio_id
       and public.pista_tem_funcao(r.evento_id, array['organizador', 'locutor']::text[])
  ));
create policy pista_fila_select
  on public.pista_fila for select to authenticated
  using (public.pista_tem_funcao(evento_id, array['organizador', 'locutor']::text[]));
create policy pista_corridas_select
  on public.pista_corridas for select to authenticated
  using (public.pista_tem_funcao(evento_id, array['organizador', 'locutor']::text[]));
create policy pista_correcoes_select
  on public.pista_correcoes_corrida for select to authenticated
  using (exists (select 1 from public.pista_corridas r
    where r.id = pista_correcoes_corrida.corrida_id
      and public.pista_tem_funcao(r.evento_id, array['organizador', 'locutor']::text[])));
create policy pista_ocorrencias_select
  on public.pista_ocorrencias for select to authenticated
  using (public.pista_tem_funcao(evento_id, array['organizador', 'locutor']::text[]));
create policy pista_premiacoes_select
  on public.pista_premiacoes for select to authenticated
  using (public.pista_tem_funcao(evento_id, array['organizador', 'escritorio']::text[]));
create policy pista_empates_select
  on public.pista_empates for select to authenticated
  using (public.pista_tem_funcao(evento_id, array['organizador', 'escritorio']::text[]));
create policy pista_empate_inscricoes_select
  on public.pista_empate_inscricoes for select to authenticated
  using (public.pista_tem_funcao(evento_id, array['organizador', 'escritorio']::text[]));

revoke all on public.pista_membros_evento, public.pista_evento_config,
  public.pista_rodizios, public.pista_posicoes, public.pista_fila,
  public.pista_corridas, public.pista_correcoes_corrida, public.pista_ocorrencias,
  public.pista_premiacoes, public.pista_empates, public.pista_empate_inscricoes
  from public, anon, authenticated;

grant select on public.pista_membros_evento, public.pista_evento_config,
  public.pista_rodizios, public.pista_posicoes, public.pista_fila,
  public.pista_corridas, public.pista_correcoes_corrida, public.pista_ocorrencias,
  public.pista_premiacoes, public.pista_empates, public.pista_empate_inscricoes
  to authenticated;
grant select on public.pista_resultados_vigentes, public.pista_parciais to authenticated;
grant select on public.pista_premiacoes_vigentes to authenticated;

revoke all on function public.pista_tem_funcao(uuid, text[]) from public, anon;
revoke all on function public.pista_exigir_funcao(uuid, text[]) from public, anon;
revoke all on function public.pista_ativar_planejado(uuid, uuid) from public, anon, authenticated;
revoke all on function public.pista_tentar_avancar(uuid) from public, anon, authenticated;
revoke all on function public.pista_configurar_evento(uuid, boolean) from public, anon;
revoke all on function public.pista_designar_membro(uuid, uuid, text) from public, anon;
revoke all on function public.pista_revogar_membro(uuid) from public, anon;
revoke all on function public.pista_planejar_rodizio(uuid, uuid, integer) from public, anon;
revoke all on function public.pista_iniciar_rodizio(uuid, uuid[]) from public, anon;
revoke all on function public.pista_chamar_proxima(uuid) from public, anon;
revoke all on function public.pista_iniciar_corrida(uuid, uuid) from public, anon;
revoke all on function public.pista_registrar_resultado(uuid, text, numeric) from public, anon;
revoke all on function public.pista_registrar_retorno(uuid) from public, anon;
revoke all on function public.pista_registrar_rabo_da_gata(uuid) from public, anon;
revoke all on function public.pista_liberar_retorno(uuid, text) from public, anon;
revoke all on function public.pista_corrigir_resultado(uuid, text, numeric) from public, anon;
revoke all on function public.pista_salvar_premiacao(uuid, uuid, integer, numeric, text) from public, anon;
revoke all on function public.pista_registrar_empate(uuid, uuid, integer, text, text, jsonb) from public, anon;

grant execute on function public.pista_tem_funcao(uuid, text[]) to authenticated;
grant execute on function public.pista_configurar_evento(uuid, boolean) to authenticated;
grant execute on function public.pista_designar_membro(uuid, uuid, text) to authenticated;
grant execute on function public.pista_revogar_membro(uuid) to authenticated;
grant execute on function public.pista_planejar_rodizio(uuid, uuid, integer) to authenticated;
grant execute on function public.pista_iniciar_rodizio(uuid, uuid[]) to authenticated;
grant execute on function public.pista_chamar_proxima(uuid) to authenticated;
grant execute on function public.pista_iniciar_corrida(uuid, uuid) to authenticated;
grant execute on function public.pista_registrar_resultado(uuid, text, numeric) to authenticated;
grant execute on function public.pista_registrar_retorno(uuid) to authenticated;
grant execute on function public.pista_registrar_rabo_da_gata(uuid) to authenticated;
grant execute on function public.pista_liberar_retorno(uuid, text) to authenticated;
grant execute on function public.pista_corrigir_resultado(uuid, text, numeric) to authenticated;
grant execute on function public.pista_salvar_premiacao(uuid, uuid, integer, numeric, text) to authenticated;
grant execute on function public.pista_registrar_empate(uuid, uuid, integer, text, text, jsonb) to authenticated;

-- Initial organizers must be inserted by a trusted server/service-role process.
-- There is no Connect-admin identity in the confirmed schema to bootstrap them here.
grant select, insert, update on public.pista_membros_evento to service_role;

commit;