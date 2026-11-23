begin;

create function public.connect_pode_supervisionar(p_evento_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select not coalesce((auth.jwt()->>'is_anonymous')::boolean, false)
    and not exists (select 1 from public.pista_ops_devices d where d.usuario_auth_id = auth.uid())
    and exists (
      select 1 from public.pista_ops_members m join public.eventos e on e.id = m.evento_id
      where m.evento_id = p_evento_id and m.usuario_id = auth.uid()
        and m.ativo and m.funcao = 'organizador'
        and (e.operacao_temporaria or public.usuario_tem_parque(e.parque_id))
    );
$$;

create function public.connect_eventos_supervisionados()
returns table (id uuid, nome text, data date, status text)
language sql stable security definer set search_path = pg_catalog, public, auth
as $$
  select e.id, e.nome::text, e.data, e.status_operacional
  from public.eventos e join public.pista_ops_members m on m.evento_id = e.id
  where m.usuario_id = auth.uid() and m.ativo and m.funcao = 'organizador'
    and public.connect_pode_supervisionar(e.id)
  order by e.data desc, e.nome, e.id;
$$;

create function public.connect_supervisao_sinal()
returns trigger language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  v_evento uuid;
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
begin
  v_evento := case tg_table_name
    when 'eventos' then (v_row->>'id')::uuid
    else (v_row->>'evento_id')::uuid
  end;
  if tg_table_name = 'pista_ops_queue_items' then
    select r.evento_id into v_evento from public.pista_ops_rounds r where r.id = (v_row->>'rodada_id')::uuid;
  end if;
  insert into public.connect_supervisao_realtime(evento_id, revisao)
  select e.id, pg_current_xact_id()::text from public.eventos e where e.id = v_evento
  on conflict (evento_id) do update set revisao = excluded.revisao
  where connect_supervisao_realtime.revisao <> excluded.revisao;
  return null;
end;
$$;

create table public.connect_supervisao_realtime (
  evento_id uuid primary key references public.eventos(id) on delete cascade,
  revisao text not null
);
alter table public.connect_supervisao_realtime enable row level security;
revoke all on public.connect_supervisao_realtime from public, anon, authenticated;
grant select on public.connect_supervisao_realtime to authenticated;
create policy connect_supervisao_realtime_organizacao on public.connect_supervisao_realtime
  for select to authenticated using (public.connect_pode_supervisionar(evento_id));

do $$
declare v_tabela text;
begin
  foreach v_tabela in array array[
    'eventos', 'categorias', 'duplas', 'pista_ops_members', 'pista_ops_devices',
    'pista_ops_rounds', 'pista_ops_runs', 'pista_ops_queue_items',
    'x1_brackets', 'x1_matches', 'pista_ops_boi_tv_atendimentos'
  ] loop
    execute format(
      'create constraint trigger connect_supervisao_sinal after insert or update or delete on public.%I
       deferrable initially deferred for each row execute function public.connect_supervisao_sinal()', v_tabela
    );
  end loop;
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime' and not puballtables)
    and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'connect_supervisao_realtime') then
    alter publication supabase_realtime add table public.connect_supervisao_realtime;
  end if;
end;
$$;

create function public.connect_supervisao_status(p_evento_id uuid, p_acao text)
returns void language plpgsql security definer set search_path = pg_catalog, public, auth
as $$
declare
  v_evento public.eventos%rowtype;
  v_novo text;
begin
  select * into v_evento from public.eventos e where e.id = p_evento_id for update;
  if not found or not public.connect_pode_supervisionar(p_evento_id) then
    raise exception 'CONNECT_ORGANIZADOR_REQUIRED' using errcode = '42501';
  end if;

  if not v_evento.operacao_temporaria then
    perform public.painel_atualizar_status_evento(p_evento_id, p_acao);
    return;
  end if;

  v_novo := case
    when p_acao = 'iniciar' and v_evento.status_operacional = 'agendado' and v_evento.data <= current_date then 'em_andamento'
    when p_acao = 'pausar' and v_evento.status_operacional = 'em_andamento' then 'pausado'
    when p_acao = 'retomar' and v_evento.status_operacional = 'pausado' then 'em_andamento'
    when p_acao = 'concluir' and v_evento.status_operacional in ('em_andamento','pausado') then 'concluido'
    when p_acao = 'anular' and v_evento.status_operacional in ('agendado','em_andamento','pausado') then 'cancelado'
  end;
  if v_novo is null then raise exception 'EVENT_ACTION_NOT_ALLOWED' using errcode = '22023'; end if;

  update public.eventos set status_operacional = v_novo where id = p_evento_id;
  if p_acao = 'anular' then
    update public.duplas set status_pagamento = 'cancelado'
      where evento_id = p_evento_id and status_pagamento is distinct from 'cancelado';
  end if;
  if v_novo in ('concluido','cancelado') then
    update public.pista_ops_device_codes set usado_em = now()
      where evento_id = p_evento_id and usado_em is null;
    update public.pista_ops_devices
       set estado = 'revogado', revogado_em = now(), revogado_por = auth.uid(), atualizado_em = now()
     where evento_id = p_evento_id and estado in ('ativo','bloqueado');
  end if;
end;
$$;

-- Preserve the individual scoring used in Locucao. List all entries that
-- contributed to the total when a competitor ran with more than one senha.
create function public.connect_classificacao(
  p_evento_id uuid, p_categoria_id uuid, p_rodizio_id uuid, p_historico boolean
)
returns jsonb language sql stable set search_path = pg_catalog, public
as $$
  with corridas as (
    select r.dupla_id, coalesce(r.competidor_real_id, d.puxador_id) as competidor_id, r.pontuacao
      from public.pista_ops_runs r join public.duplas d on d.id = r.dupla_id
     where r.evento_id = p_evento_id and r.categoria_id = p_categoria_id
       and r.estado in ('zero','valeu_boi') and d.status_pagamento is distinct from 'cancelado'
       and (p_rodizio_id is null or r.rodada_atual_id = p_rodizio_id)
    union all
    select v.dupla_id, r.competidor_id, v.pontuacao
      from public.pista_resultados_vigentes v join public.pista_corridas r on r.id = v.corrida_id
      join public.duplas d on d.id = v.dupla_id
     where p_historico and v.evento_id = p_evento_id and v.categoria_id = p_categoria_id
       and d.status_pagamento is distinct from 'cancelado'
       and not exists (
         select 1 from public.pista_ops_runs atual where atual.dupla_id = v.dupla_id
           and atual.numero_corrida = v.numero_corrida and atual.estado in ('zero','valeu_boi')
       )
  ), placar as (
    select r.competidor_id, sum(r.pontuacao) as pontos, dense_rank() over (order by sum(r.pontuacao) desc) as posicao
      from corridas r group by r.competidor_id
  ), inscricoes as (
    select r.competidor_id, jsonb_agg(jsonb_build_object(
      'senha', d.numero_senha, 'cavalo', d.nome_cavalo, 'equipe', d.nome_equipe
    ) order by d.numero_senha, d.id) as senhas
    from (select distinct competidor_id, dupla_id from corridas) r join public.duplas d on d.id = r.dupla_id
    group by r.competidor_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.competidor_id, 'posicao', p.posicao, 'vaqueiro', c.nome, 'pontos', p.pontos, 'inscricoes', i.senhas
  ) order by p.posicao, c.nome, p.competidor_id), '[]'::jsonb)
  from placar p join public.competidores c on c.id = p.competidor_id
    join inscricoes i on i.competidor_id = p.competidor_id;
$$;

create function public.connect_supervisao_dados(p_evento_id uuid, p_categoria_id uuid default null, p_relatorio boolean default false)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, auth
as $$
declare
  v_evento jsonb;
  v_rodizio uuid;
  v_categorias jsonb;
  v_chaves jsonb;
  v_revisoes jsonb;
  v_equipe jsonb;
  v_dispositivos jsonb;
begin
  if not public.connect_pode_supervisionar(p_evento_id) then
    raise exception 'CONNECT_ORGANIZADOR_REQUIRED' using errcode = '42501';
  end if;

  select jsonb_build_object('id', e.id, 'nome', e.nome, 'data', e.data,
    'status', e.status_operacional, 'parque', p.nome)
    into v_evento from public.eventos e left join public.parques p on p.id = e.parque_id where e.id = p_evento_id;

  if not p_relatorio then
    select r.id into v_rodizio from public.pista_ops_rounds r
     where r.evento_id = p_evento_id and r.categoria_id = p_categoria_id and r.estado = 'ativo';

    select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'nome', p.nome, 'funcao', m.funcao) order by m.funcao, p.nome), '[]')
      into v_equipe from public.pista_ops_members m join public.perfis p on p.id = m.usuario_id
      where m.evento_id = p_evento_id and m.ativo;

    select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'nome', d.nome, 'funcao', d.funcao,
      'estado', d.estado, 'operador', p.nome, 'ultimo_acesso', d.ultimo_acesso_em) order by d.criado_em desc), '[]')
      into v_dispositivos from public.pista_ops_devices d left join public.perfis p on p.id = d.operador_conta_id
      where d.evento_id = p_evento_id and d.estado in ('ativo','bloqueado');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id, 'nome', c.nome, 'modelo', c.modelo_competicao,
    'geral', case when c.modelo_competicao = 'classificatoria' and (p_relatorio or c.id = p_categoria_id)
      then public.connect_classificacao(p_evento_id, c.id, null, p_relatorio) else '[]'::jsonb end,
    'parcial', case when c.id = p_categoria_id and v_rodizio is not null
      then public.connect_classificacao(p_evento_id, c.id, v_rodizio, false) else '[]'::jsonb end,
    'inscricoes', case when p_relatorio then (
      select jsonb_build_object('ativas', count(*) filter (where d.status_pagamento is distinct from 'cancelado'),
        'canceladas', count(*) filter (where d.status_pagamento = 'cancelado'))
      from public.duplas d where d.evento_id = p_evento_id and d.categoria_id = c.id
    ) end,
    'resultados', case when p_relatorio then (
      with ocorrencias as (
        select r.estado as tipo, true as concluida, 1::bigint as total
        from public.pista_ops_runs r where r.evento_id = p_evento_id and r.categoria_id = c.id
          and r.estado in ('valeu_boi', 'zero')
        union all
        select 'retorno', false, coalesce(sum(r.retornos_realizados), 0)
        from public.pista_ops_runs r where r.evento_id = p_evento_id and r.categoria_id = c.id
        union all
        select 'rabo_da_gata', true, count(*)
          from public.pista_ops_queue_items q join public.pista_ops_rounds rr on rr.id = q.rodada_id
           where rr.evento_id = p_evento_id and rr.categoria_id = c.id and q.tipo = 'rabo_da_gata' and q.estado = 'concluida'
        union all
        select v.resultado, true, 1
        from public.pista_resultados_vigentes v where v.evento_id = p_evento_id and v.categoria_id = c.id
          and not exists (
            select 1 from public.pista_ops_runs r where r.dupla_id = v.dupla_id and r.numero_corrida = v.numero_corrida
              and r.estado in ('zero','valeu_boi')
          )
        union all
        select o.tipo, false, 1
        from public.pista_ocorrencias o where o.evento_id = p_evento_id and o.categoria_id = c.id
          and o.tipo in ('retorno','rabo_da_gata') and not exists (
            select 1 from public.pista_ops_runs r where r.dupla_id = o.dupla_id and r.numero_corrida = o.numero_corrida
              and (r.retornos_realizados > 0 or r.estado in ('zero','valeu_boi'))
          )
      )
      select jsonb_build_object(
        'concluidas', coalesce(sum(total) filter (where concluida), 0),
        'valeu_boi', coalesce(sum(total) filter (where tipo = 'valeu_boi'), 0),
        'zero', coalesce(sum(total) filter (where tipo = 'zero'), 0),
        'retorno', coalesce(sum(total) filter (where tipo = 'retorno'), 0),
        'rabo_da_gata', coalesce(sum(total) filter (where tipo = 'rabo_da_gata'), 0)
      ) from ocorrencias
    ) end
  ) order by c.ordem, c.nome), '[]')
  into v_categorias from public.categorias c where c.evento_id = p_evento_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', b.id, 'categoria_id', b.categoria_id, 'categoria', c.nome,
    'modelo', case when b.melhor_de = 1 then 'Tropa de Elite' else 'X1' end, 'estado', b.estado,
    'campeao', case when b.estado = 'finalizada' then (
      select p.nome from public.x1_matches m join public.duplas d on d.id = m.vencedor_id
        join public.competidores p on p.id = d.puxador_id where m.chave_id = b.id
        and m.estado = 'finalizada' and m.fase = (select max(f.fase) from public.x1_matches f where f.chave_id = b.id)
        order by m.posicao limit 1
    ) end,
    'confrontos', case when not p_relatorio and (p_categoria_id is null or b.categoria_id = p_categoria_id) then (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', m.id, 'fase', m.fase, 'posicao', m.posicao, 'estado', m.estado,
        'lado_a', pa.nome, 'lado_b', pb.nome, 'vencedor', pv.nome
      ) order by m.fase, m.posicao), '[]') from public.x1_matches m
      left join public.duplas a on a.id = m.lado_a left join public.competidores pa on pa.id = a.puxador_id
      left join public.duplas ab on ab.id = m.lado_b left join public.competidores pb on pb.id = ab.puxador_id
      left join public.duplas v on v.id = m.vencedor_id left join public.competidores pv on pv.id = v.puxador_id
      where m.chave_id = b.id and m.evento_id = p_evento_id
    ) else '[]'::jsonb end
  ) order by c.ordem, c.nome), '[]')
  into v_chaves from public.x1_brackets b join public.categorias c on c.id = b.categoria_id where b.evento_id = p_evento_id;

  if p_relatorio then
    with revisoes as (
      select p.id, 'pista' as fluxo, p.categoria_id, p.origem, p.tipo_solicitacao as tipo,
        p.reclamante_dupla_id, p.resultado_inicial, p.pontuacao_inicial,
        p.resultado_alternativa as decisao, p.pontuacao_alternativa as pontuacao_final,
        p.solicitada_em as solicitada, p.solicitada_por as solicitante,
        p.julgada_em as julgada, p.julgada_por as juiz, p.justificativa,
        p.estado, d.numero_senha as senha
      from public.pista_ops_boi_tv_reviews p join public.pista_ops_runs r on r.id = p.corrida_id
      join public.duplas d on d.id = r.dupla_id where p.evento_id = p_evento_id
      union all
      select x.id, 'x1', m.categoria_id, x.origem, x.tipo_solicitacao, x.reclamante_dupla_id,
        b.resultado, null, x.resultado_final, null, x.criado_em, x.solicitante,
        x.julgado_em, x.julgado_por, x.justificativa, x.estado, d.numero_senha
      from public.x1_revisoes x join public.x1_bois b on b.id = x.boi_id
      join public.x1_matches m on m.id = b.confronto_id join public.duplas d on d.id = b.dupla_id
      where m.evento_id = p_evento_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id, 'categoria', c.nome, 'fluxo', r.fluxo, 'origem', r.origem, 'tipo', r.tipo,
      'senha', r.senha, 'reclamante', rec.numero_senha, 'estado', coalesce(a.estado_atendimento, r.estado),
      'resultado_inicial', r.resultado_inicial, 'pontuacao_inicial', r.pontuacao_inicial,
      'decisao', r.decisao, 'pontuacao_final', r.pontuacao_final, 'justificativa', r.justificativa,
      'solicitada', r.solicitada, 'solicitante', coalesce(ps.nome, r.solicitante::text),
      'recebida', a.recebida_em, 'recebida_por', coalesce(pr.nome, a.recebida_por::text),
      'analisada', a.analise_concluida_em, 'analista', coalesce(pa.nome, a.analise_concluida_por::text),
      'atualizada', a.atualizada_em, 'observacao', a.observacao_operacional, 'julgada', r.julgada,
      'juiz', coalesce(pj.nome, r.juiz::text)
    ) order by r.solicitada, r.id), '[]') into v_revisoes
    from revisoes r join public.categorias c on c.id = r.categoria_id
    left join public.duplas rec on rec.id = r.reclamante_dupla_id
    left join public.pista_ops_boi_tv_atendimentos a on a.evento_id = p_evento_id
      and (a.revisao_pista_id = r.id and r.fluxo = 'pista' or a.revisao_x1_id = r.id and r.fluxo = 'x1')
    left join public.perfis ps on ps.id = r.solicitante left join public.perfis pj on pj.id = r.juiz
    left join public.perfis pr on pr.id = a.recebida_por left join public.perfis pa on pa.id = a.analise_concluida_por;
  end if;

  return jsonb_build_object(
    'evento', v_evento, 'gerado_em', now(), 'categorias', v_categorias, 'chaves', v_chaves,
    'equipe', v_equipe, 'dispositivos', v_dispositivos, 'revisoes', v_revisoes,
    'rodizio', (select jsonb_build_object('id', r.id, 'numero', r.numero,
      'senha_atual', (select d.numero_senha from public.pista_ops_queue_items q join public.duplas d on d.id = q.dupla_id
        where q.rodada_id = r.id and q.estado = 'chamada' order by q.ordem_fila limit 1),
      'corridas', count(*) filter (where progresso.concluida and not progresso.pendente),
      'restantes', count(*) filter (where progresso.pendente))
      from public.pista_ops_rounds r
      left join lateral (
        select bool_or(q.estado = 'concluida') as concluida,
               bool_or(q.estado in ('na_fila','chamada','retorno_pendente','aguardando_proximo')) as pendente
        from public.pista_ops_queue_items q join public.duplas d on d.id = q.dupla_id
        where q.rodada_id = r.id and d.status_pagamento is distinct from 'cancelado' group by q.dupla_id
      ) progresso on true where r.id = v_rodizio group by r.id),
    'rodizios', case when p_relatorio then (select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id, 'categoria', c.nome, 'numero', r.numero, 'estado', r.estado,
      'inicio', r.iniciado_em, 'fim', r.terminado_em
    ) order by r.iniciado_em, r.id), '[]')
    from (
      select id, categoria_id, numero, estado, iniciado_em, terminado_em
      from public.pista_ops_rounds where evento_id = p_evento_id and iniciado_em is not null
      union all
      select id, categoria_id, numero, estado, iniciado_em, concluido_em
      from public.pista_rodizios where evento_id = p_evento_id and iniciado_em is not null
    ) r join public.categorias c on c.id = r.categoria_id) end,
    'boi_tv', (select jsonb_build_object(
      'nova', count(*) filter (where estado_atendimento = 'nova'),
      'recebida', count(*) filter (where estado_atendimento = 'recebida'),
      'em_analise', count(*) filter (where estado_atendimento = 'em_analise'),
      'analise_concluida', count(*) filter (where estado_atendimento = 'analise_concluida'),
      'aguardando_decisao', count(*) filter (where estado_atendimento = 'aguardando_decisao'),
      'finalizada', count(*) filter (where estado_atendimento = 'finalizada')
    ) from public.pista_ops_boi_tv_atendimentos where evento_id = p_evento_id)
  );
end;
$$;

revoke all on function public.connect_supervisao_sinal(), public.connect_classificacao(uuid,uuid,uuid,boolean)
  from public, anon, authenticated;
revoke all on function public.connect_pode_supervisionar(uuid), public.connect_supervisao_status(uuid,text),
  public.connect_supervisao_dados(uuid,uuid,boolean), public.connect_eventos_supervisionados() from public, anon;
grant execute on function public.connect_pode_supervisionar(uuid), public.connect_supervisao_status(uuid,text),
  public.connect_supervisao_dados(uuid,uuid,boolean), public.connect_eventos_supervisionados() to authenticated;

notify pgrst, 'reload schema';
commit;
