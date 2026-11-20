-- Parque, calendário do evento e controles de operação.
-- Revisar e aplicar no Supabase antes de usar as novas telas.

begin;

alter table public.parques add column if not exists localizacao text;
alter table public.eventos add column if not exists status_operacional text;
alter table public.categorias add column if not exists ativa boolean not null default true;

update public.eventos
   set status_operacional = case lower(status::text)
     when 'ativo' then 'em_andamento'
     when 'em_andamento' then 'em_andamento'
     when 'pausado' then 'pausado'
     when 'concluido' then 'concluido'
     when 'cancelado' then 'cancelado'
     else 'agendado'
   end
 where status_operacional is null;
alter table public.eventos alter column status_operacional set default 'agendado';
alter table public.eventos alter column status_operacional set not null;

do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='parques' and column_name='cidade') then
    if exists (select 1 from information_schema.columns where table_schema='public' and table_name='parques' and column_name='estado') then
      execute format($query$update public.parques set localizacao = nullif(concat_ws(%L, nullif(btrim(cidade::text), %L), nullif(btrim(estado::text), %L)), %L) where localizacao is null$query$, ', ', '', '', '');
    else
      execute 'update public.parques set localizacao = nullif(btrim(cidade::text), '''') where localizacao is null';
    end if;
  end if;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'eventos_status_operacional_ck') then
    alter table public.eventos add constraint eventos_status_operacional_ck
      check (status_operacional in ('agendado', 'em_andamento', 'pausado', 'concluido', 'cancelado'));
  end if;
end;
$$;

create table if not exists public.parque_membros (
  parque_id uuid not null references public.parques(id) on delete cascade,
  usuario_id uuid not null references public.perfis(id) on delete cascade,
  criado_em timestamptz not null default now(),
  primary key (parque_id, usuario_id)
);

insert into public.parque_membros(parque_id, usuario_id)
select parque_id, id from public.perfis where parque_id is not null
on conflict do nothing;

alter table public.parque_membros enable row level security;
revoke all on public.parque_membros from public, anon, authenticated;

create or replace function public.usuario_tem_parque(p_parque_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from public.parque_membros m
     where m.parque_id = p_parque_id and m.usuario_id = auth.uid()
  );
$$;

create or replace function public.painel_listar_parques()
returns table(id uuid, nome text, localizacao text, quantidade_eventos bigint, data_mais_proxima date)
language sql stable security definer set search_path = '' as $$
  select p.id, p.nome, p.localizacao,
         count(e.id)::bigint,
         coalesce(min(e.data) filter (where e.data >= current_date and e.status_operacional <> 'cancelado'),
                  max(e.data) filter (where e.status_operacional <> 'cancelado'))
    from public.parques p
    join public.parque_membros m on m.parque_id = p.id and m.usuario_id = auth.uid()
    left join public.eventos e on e.parque_id = p.id
   where auth.uid() is not null
   group by p.id, p.nome, p.localizacao
   order by p.nome;
$$;

create or replace function public.painel_criar_parque(p_nome text, p_localizacao text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_usuario uuid := auth.uid();
  v_parque uuid;
begin
  if v_usuario is null then raise exception 'AUTH_REQUIRED' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_nome, ''))) = 0 or length(btrim(p_nome)) > 120
     or length(btrim(coalesce(p_localizacao, ''))) = 0 or length(btrim(p_localizacao)) > 180 then
    raise exception 'PARK_FIELDS_REQUIRED' using errcode = '22023';
  end if;
  if not exists (select 1 from public.perfis where id = v_usuario) then
    raise exception 'PROFILE_REQUIRED' using errcode = '42501';
  end if;
  insert into public.parques(id, nome, localizacao)
  values (gen_random_uuid(), btrim(p_nome), btrim(p_localizacao))
  returning id into v_parque;
  insert into public.parque_membros(parque_id, usuario_id) values (v_parque, v_usuario);
  return v_parque;
end;
$$;

create or replace function public.painel_criar_evento(p_parque_id uuid, p_nome text, p_data date)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_evento uuid;
  v_usuario uuid := auth.uid();
begin
  if v_usuario is null or not public.usuario_tem_parque(p_parque_id) then
    raise exception 'PARK_ACCESS_REQUIRED' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_nome, ''))) = 0 or p_data is null then
    raise exception 'EVENT_FIELDS_REQUIRED' using errcode = '22023';
  end if;
  insert into public.eventos(parque_id, nome, data, status, status_operacional)
  values (p_parque_id, btrim(p_nome), p_data, 'rascunho', 'agendado')
  returning id into v_evento;
  insert into public.pista_ops_members(evento_id, usuario_id, funcao, ativo, criado_por)
  values (v_evento, v_usuario, 'organizador', true, v_usuario)
  on conflict (evento_id, usuario_id, funcao) where ativo do update set ativo = true;
  return v_evento;
end;
$$;

create or replace function public.painel_eventos_do_parque(p_parque_id uuid)
returns table(id uuid, nome text, data date, status_operacional text, quantidade_senhas bigint,
              quantidade_rodizios bigint, categorias text[])
language sql stable security definer set search_path = '' as $$
  select e.id, e.nome, e.data, e.status_operacional,
         (select count(*) from public.duplas d where d.evento_id = e.id and d.status_pagamento <> 'cancelado')::bigint,
         (select count(*) from public.pista_ops_rounds r where r.evento_id = e.id and r.estado = 'finalizado')::bigint,
         coalesce((select array_agg(c.nome order by c.ordem, c.nome)
                     from public.categorias c where c.evento_id = e.id and c.ativa), array[]::text[])
    from public.eventos e
   where e.parque_id = p_parque_id and public.usuario_tem_parque(e.parque_id)
   order by e.data desc, e.nome;
$$;

create or replace function public.painel_eventos_em_andamento()
returns table(id uuid, nome text, data date, parque_nome text, localizacao text,
              quantidade_senhas bigint, quantidade_rodizios bigint, categorias text[])
language sql stable security definer set search_path = '' as $$
  select e.id, e.nome, e.data, p.nome, p.localizacao,
         (select count(*) from public.duplas d where d.evento_id = e.id and d.status_pagamento <> 'cancelado')::bigint,
         (select count(*) from public.pista_ops_rounds r where r.evento_id = e.id and r.estado = 'finalizado')::bigint,
         coalesce((select array_agg(c.nome order by c.ordem, c.nome)
                     from public.categorias c where c.evento_id = e.id and c.ativa), array[]::text[])
    from public.eventos e join public.parques p on p.id = e.parque_id
   where e.status_operacional = 'em_andamento' and public.usuario_tem_parque(e.parque_id)
   order by e.data, e.nome;
$$;

create or replace function public.painel_detalhes_evento(p_evento_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_result jsonb;
begin
  select jsonb_build_object(
    'id', e.id, 'nome', e.nome, 'data', e.data, 'status_operacional', e.status_operacional,
    'parque_id', e.parque_id, 'parque_nome', p.nome, 'localizacao', p.localizacao,
    'quantidade_senhas', (select count(*) from public.duplas d where d.evento_id=e.id and d.status_pagamento <> 'cancelado'),
    'quantidade_rodizios', (select count(*) from public.pista_ops_rounds r where r.evento_id=e.id and r.estado='finalizado'),
    'categorias', coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome,'ordem',c.ordem,'valor_inscricao',c.valor_inscricao,'ativa',c.ativa) order by c.ordem,c.nome)
                              from public.categorias c where c.evento_id=e.id), '[]'::jsonb),
    'rodizio_ativo', (select jsonb_build_object('id',r.id,'numero',r.numero,'categoria_id',r.categoria_id,
                            'categoria_nome',c.nome,'fila_total',count(q.id),
                            'fila_pendente',count(q.id) filter (where q.estado in ('na_fila','retorno_pendente','aguardando_proximo')))
                        from public.pista_ops_rounds r join public.categorias c on c.id=r.categoria_id
                        left join public.pista_ops_queue_items q on q.rodada_id=r.id
                        where r.evento_id=e.id and r.estado in ('ativo','aguardando_proximo_rodizio') group by r.id,c.nome limit 1),
    'rodizios', coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'numero',r.numero,'estado',r.estado,
                            'categoria_nome',c.nome,'fila_total',coalesce(q.total,0),'fila_pendente',coalesce(q.pendente,0))
                            order by r.criado_em desc)
                        from public.pista_ops_rounds r join public.categorias c on c.id=r.categoria_id
                        left join lateral (select count(*) total,
                               count(*) filter (where qi.estado in ('na_fila','retorno_pendente','aguardando_proximo')) pendente
                                from public.pista_ops_queue_items qi where qi.rodada_id=r.id) q on true
                       where r.evento_id=e.id), '[]'::jsonb)
  ) into v_result
    from public.eventos e join public.parques p on p.id=e.parque_id
   where e.id=p_evento_id and public.usuario_tem_parque(e.parque_id);
  return v_result;
end;
$$;

create or replace function public.painel_atualizar_status_evento(p_evento_id uuid, p_acao text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_evento public.eventos%rowtype; v_novo text;
begin
  select * into v_evento from public.eventos where id=p_evento_id for update;
  if not found or not public.usuario_tem_parque(v_evento.parque_id) then
    raise exception 'EVENT_ACCESS_REQUIRED' using errcode = '42501';
  end if;
  if p_acao='iniciar' and v_evento.status_operacional='agendado' and v_evento.data <= current_date then v_novo := 'em_andamento';
  elsif p_acao='pausar' and v_evento.status_operacional='em_andamento' then v_novo := 'pausado';
  elsif p_acao='retomar' and v_evento.status_operacional='pausado' then v_novo := 'em_andamento';
  elsif p_acao='concluir' and v_evento.status_operacional in ('em_andamento','pausado') then v_novo := 'concluido';
  elsif p_acao='anular' and v_evento.status_operacional not in ('concluido','cancelado') then v_novo := 'cancelado';
  else raise exception 'EVENT_ACTION_NOT_ALLOWED' using errcode = '22023';
  end if;
  update public.eventos set status_operacional=v_novo where id=p_evento_id;
  if p_acao='anular' then
    update public.duplas set status_pagamento='cancelado' where evento_id=p_evento_id and status_pagamento <> 'cancelado';
  end if;
  return v_novo;
end;
$$;

create or replace function public.painel_criar_categoria(p_evento_id uuid,p_nome text,p_ordem integer,p_valor numeric)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_park uuid; v_status text;
begin
  select parque_id,status_operacional into v_park,v_status from public.eventos where id=p_evento_id;
  if not public.usuario_tem_parque(v_park) then
    raise exception 'EVENT_ACCESS_REQUIRED' using errcode='42501';
  end if;
  if v_status in ('pausado','concluido','cancelado') then raise exception 'EVENT_OPERATION_BLOCKED' using errcode='42501'; end if;
  if length(btrim(coalesce(p_nome,'')))=0 or p_ordem is null or p_ordem<0 or p_valor is null or p_valor<0 then
    raise exception 'CATEGORY_FIELDS_INVALID' using errcode='22023';
  end if;
  insert into public.categorias(evento_id,nome,ordem,valor_inscricao,ativa)
  values(p_evento_id,btrim(p_nome),p_ordem,p_valor,true) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.painel_ocultar_categoria(p_categoria_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_parque uuid; v_status text;
begin
  select e.parque_id,e.status_operacional into v_parque,v_status from public.categorias c join public.eventos e on e.id=c.evento_id where c.id=p_categoria_id;
  if not public.usuario_tem_parque(v_parque) then raise exception 'EVENT_ACCESS_REQUIRED' using errcode='42501'; end if;
  if v_status in ('pausado','concluido','cancelado') then raise exception 'EVENT_OPERATION_BLOCKED' using errcode='42501'; end if;
  update public.categorias set ativa=false where id=p_categoria_id;
  return found;
end;
$$;

create or replace function public.inscrever_competidor_evento(
  p_evento_id uuid,p_categoria_id uuid,p_nome text,p_numero_senha integer,
  p_nome_cavalo text,p_nome_equipe text,p_status_pagamento text,p_motivo_isencao text
)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_park uuid; v_competidor uuid; v_inscricao uuid; v_status text;
begin
  if auth.uid() is null then raise exception 'INSCRICAO_AUTH_REQUIRED' using errcode='42501'; end if;
  select parque_id,status_operacional into v_park,v_status from public.eventos where id=p_evento_id;
  if v_park is null or not public.usuario_tem_parque(v_park) then raise exception 'INSCRICAO_EVENT_ACCESS_DENIED' using errcode='42501'; end if;
  if v_status in ('pausado','concluido','cancelado') then raise exception 'EVENT_OPERATION_BLOCKED' using errcode='42501'; end if;
  if p_nome is null or length(btrim(p_nome))=0 or length(btrim(p_nome))>120 or p_numero_senha is null or p_numero_senha<1
     or length(btrim(coalesce(p_nome_cavalo,'')))>120 or length(btrim(coalesce(p_nome_equipe,'')))>120
     or p_status_pagamento is null or p_status_pagamento not in ('pendente','pago','isento')
     or (p_status_pagamento='isento' and (length(btrim(coalesce(p_motivo_isencao,'')))=0 or length(btrim(p_motivo_isencao))>500)) then
    raise exception 'INSCRICAO_INVALID_FIELDS' using errcode='22023';
  end if;
  if not exists(select 1 from public.categorias c where c.id=p_categoria_id and c.evento_id=p_evento_id and c.ativa) then
    raise exception 'INSCRICAO_CATEGORY_INVALID' using errcode='22023';
  end if;
  insert into public.competidores(parque_id,nome) values(v_park,btrim(p_nome)) returning id into v_competidor;
  insert into public.duplas(evento_id,categoria_id,puxador_id,numero_senha,nome_cavalo,nome_equipe,status_pagamento,motivo_isencao)
  values(p_evento_id,p_categoria_id,v_competidor,p_numero_senha,nullif(btrim(coalesce(p_nome_cavalo,'')),''),nullif(btrim(coalesce(p_nome_equipe,'')),''),p_status_pagamento,
         case when p_status_pagamento='isento' then btrim(p_motivo_isencao) else null end) returning id into v_inscricao;
  return v_inscricao;
end;
$$;

create or replace function public.painel_atualizar_pagamento(p_evento_id uuid,p_inscricao_id uuid,p_status text,p_motivo text)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_park uuid; v_status text;
begin
  select parque_id,status_operacional into v_park,v_status from public.eventos where id=p_evento_id;
  if v_park is null or not public.usuario_tem_parque(v_park) then raise exception 'EVENT_ACCESS_REQUIRED' using errcode='42501'; end if;
  if v_status in ('pausado','concluido','cancelado') then raise exception 'EVENT_OPERATION_BLOCKED' using errcode='42501'; end if;
  if p_status is null or p_status not in ('pendente','pago','isento') or (p_status='isento' and length(btrim(coalesce(p_motivo,'')))=0) then
    raise exception 'PAYMENT_FIELDS_INVALID' using errcode='22023';
  end if;
  update public.duplas set status_pagamento=p_status,motivo_isencao=case when p_status='isento' then btrim(p_motivo) else null end
   where id=p_inscricao_id and evento_id=p_evento_id and status_pagamento<>'cancelado';
  return found;
end;
$$;

create or replace function public.painel_editar_inscricao(p_evento_id uuid,p_inscricao_id uuid,p_categoria_id uuid,p_competidor_id uuid,p_numero_senha integer)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_park uuid; v_status text;
begin
  select parque_id,status_operacional into v_park,v_status from public.eventos where id=p_evento_id;
  if v_park is null or not public.usuario_tem_parque(v_park) then raise exception 'EVENT_ACCESS_REQUIRED' using errcode='42501'; end if;
  if v_status in ('pausado','concluido','cancelado') then raise exception 'EVENT_OPERATION_BLOCKED' using errcode='42501'; end if;
  if p_numero_senha is null or p_numero_senha<1 or not exists(select 1 from public.categorias where id=p_categoria_id and evento_id=p_evento_id)
     or not exists(select 1 from public.competidores where id=p_competidor_id and parque_id=v_park) then
    raise exception 'INSCRICAO_EDIT_INVALID' using errcode='22023';
  end if;
  update public.duplas set categoria_id=p_categoria_id,puxador_id=p_competidor_id,numero_senha=p_numero_senha
   where id=p_inscricao_id and evento_id=p_evento_id and status_pagamento<>'cancelado';
  return found;
end;
$$;

create or replace function public.pista_ops_check_access(p_evento_id uuid, p_funcoes text[])
returns uuid language plpgsql security definer set search_path = pg_catalog, public, auth, pg_temp as $$
declare actor_id uuid:=auth.uid(); event_park_id uuid; event_status text;
begin
  if actor_id is null then raise exception using errcode='42501',message='PISTA_AUTH_REQUIRED'; end if;
  select e.parque_id,e.status_operacional into event_park_id,event_status from public.eventos e where e.id=p_evento_id;
  if event_park_id is null or not public.usuario_tem_parque(event_park_id) then
    raise exception using errcode='42501',message='PISTA_EVENT_PARK_MISMATCH';
  end if;
  if event_status <> 'em_andamento' then
    raise exception using errcode='42501',message='EVENT_OPERATION_BLOCKED';
  end if;
  if not exists(select 1 from public.pista_ops_members m where m.evento_id=p_evento_id and m.usuario_id=actor_id and m.ativo and m.funcao=any(p_funcoes)) then
    raise exception using errcode='42501',message='PISTA_EVENT_ROLE_REQUIRED';
  end if;
  return actor_id;
end;
$$;

create or replace function public.pista_tem_funcao(p_evento_id uuid,p_funcoes text[])
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from public.eventos e
    join public.pista_membros_evento m on m.evento_id=e.id
    where e.id=p_evento_id and e.status_operacional='em_andamento'
      and public.usuario_tem_parque(e.parque_id)
      and m.usuario_id=auth.uid() and m.ativo and m.funcao=any(p_funcoes)
  );
$$;

do $$
begin
  if exists (select 1 from public.pista_ops_rounds where estado in ('ativo','aguardando_proximo_rodizio') group by evento_id having count(*)>1) then
    raise exception 'More than one active round exists in an event; resolve these rounds before applying the one-active-round rule.';
  end if;
end;
$$;

drop index if exists public.pista_ops_one_active_round_uq;
create unique index if not exists pista_ops_one_active_round_per_event_uq
  on public.pista_ops_rounds(evento_id) where estado in ('ativo','aguardando_proximo_rodizio');

create or replace function public.pista_ops_terminar_rodizio(p_evento_id uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_actor uuid; v_rodizio uuid;
begin
  v_actor:=public.pista_ops_check_access(p_evento_id,array['organizador','escritorio']);
  select id into v_rodizio from public.pista_ops_rounds where evento_id=p_evento_id and estado in ('ativo','aguardando_proximo_rodizio') for update;
  if v_rodizio is null then raise exception 'PISTA_NO_ACTIVE_ROUND' using errcode='P0001'; end if;
  update public.pista_ops_positions set estado='livre',item_fila_id=null where rodada_id=v_rodizio and estado='ocupada';
  update public.pista_ops_runs set estado=case when estado='em_curso' then 'pendente' else estado end,
    rodada_atual_id=null,atualizado_em=now()
    where rodada_atual_id=v_rodizio and estado in ('pendente','retorno_pendente','em_curso');
  update public.pista_ops_queue_items set estado='aguardando_proximo'
    where rodada_id=v_rodizio and estado in ('na_fila','chamada','retorno_pendente');
  update public.pista_ops_rounds set estado='finalizado' where id=v_rodizio;
  return v_rodizio;
end;
$$;

create or replace function public.pista_ops_novo_rodizio(p_evento_id uuid,p_categoria_id uuid,p_quantidade_bois integer)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_rodizio uuid; v_result jsonb;
begin
  v_rodizio:=public.pista_ops_planejar_rodizio(p_evento_id,p_categoria_id,p_quantidade_bois);
  v_result:=public.pista_ops_iniciar_rodizio(v_rodizio);
  return v_result;
end;
$$;

-- Leitura de cartões e cadastros pelo vínculo de parque.
drop policy if exists parque_membros_self_select on public.parque_membros;
create policy parque_membros_self_select on public.parque_membros for select to authenticated
  using (usuario_id=auth.uid());
drop policy if exists parques_membro_select on public.parques;
create policy parques_membro_select on public.parques for select to authenticated
  using (public.usuario_tem_parque(id));
drop policy if exists eventos_membro_select on public.eventos;
create policy eventos_membro_select on public.eventos for select to authenticated
  using (public.usuario_tem_parque(parque_id));
drop policy if exists categorias_membro_select on public.categorias;
create policy categorias_membro_select on public.categorias for select to authenticated
  using (exists(select 1 from public.eventos e where e.id=categorias.evento_id and public.usuario_tem_parque(e.parque_id)));
drop policy if exists duplas_membro_select on public.duplas;
create policy duplas_membro_select on public.duplas for select to authenticated
  using (exists(select 1 from public.eventos e where e.id=duplas.evento_id and public.usuario_tem_parque(e.parque_id)));
drop policy if exists competidores_membro_select on public.competidores;
create policy competidores_membro_select on public.competidores for select to authenticated
  using (public.usuario_tem_parque(parque_id));

grant execute on function public.usuario_tem_parque(uuid) to authenticated;
grant execute on function public.painel_listar_parques() to authenticated;
grant execute on function public.painel_criar_parque(text,text) to authenticated;
grant execute on function public.painel_criar_evento(uuid,text,date) to authenticated;
grant execute on function public.painel_eventos_do_parque(uuid) to authenticated;
grant execute on function public.painel_eventos_em_andamento() to authenticated;
grant execute on function public.painel_detalhes_evento(uuid) to authenticated;
grant execute on function public.painel_atualizar_status_evento(uuid,text) to authenticated;
grant execute on function public.painel_criar_categoria(uuid,text,integer,numeric) to authenticated;
grant execute on function public.painel_ocultar_categoria(uuid) to authenticated;
grant execute on function public.inscrever_competidor_evento(uuid,uuid,text,integer,text,text,text,text) to authenticated;
grant execute on function public.painel_atualizar_pagamento(uuid,uuid,text,text) to authenticated;
grant execute on function public.painel_editar_inscricao(uuid,uuid,uuid,uuid,integer) to authenticated;
grant execute on function public.pista_ops_check_access(uuid,text[]) to authenticated;
grant execute on function public.pista_tem_funcao(uuid,text[]) to authenticated;
grant execute on function public.pista_ops_terminar_rodizio(uuid) to authenticated;
grant execute on function public.pista_ops_novo_rodizio(uuid,uuid,integer) to authenticated;

revoke all on function public.usuario_tem_parque(uuid) from public,anon;
revoke all on function public.painel_listar_parques() from public,anon;
revoke all on function public.painel_criar_parque(text,text) from public,anon;
revoke all on function public.painel_criar_evento(uuid,text,date) from public,anon;
revoke all on function public.painel_eventos_do_parque(uuid) from public,anon;
revoke all on function public.painel_eventos_em_andamento() from public,anon;
revoke all on function public.painel_detalhes_evento(uuid) from public,anon;
revoke all on function public.painel_atualizar_status_evento(uuid,text) from public,anon;
revoke all on function public.painel_criar_categoria(uuid,text,integer,numeric) from public,anon;
revoke all on function public.painel_ocultar_categoria(uuid) from public,anon;
revoke all on function public.inscrever_competidor_evento(uuid,uuid,text,integer,text,text,text,text) from public,anon;
revoke all on function public.painel_atualizar_pagamento(uuid,uuid,text,text) from public,anon;
revoke all on function public.painel_editar_inscricao(uuid,uuid,uuid,uuid,integer) from public,anon;
revoke all on function public.pista_ops_check_access(uuid,text[]) from public,anon;
revoke all on function public.pista_tem_funcao(uuid,text[]) from public,anon;
revoke all on function public.pista_ops_terminar_rodizio(uuid) from public,anon;
revoke all on function public.pista_ops_novo_rodizio(uuid,uuid,integer) from public,anon;

notify pgrst, 'reload schema';

commit;
