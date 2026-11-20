begin;

create or replace function public.painel_editar_categoria(
  p_evento_id uuid,
  p_categoria_id uuid,
  p_nome text,
  p_ordem integer,
  p_valor numeric
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_event public.eventos%rowtype;
begin
  select e.* into v_event
    from public.categorias c
    join public.eventos e on e.id = c.evento_id
   where c.id = p_categoria_id and c.evento_id = p_evento_id;
  if not found then
    raise exception 'CATEGORY_NOT_FOUND' using errcode = '42501';
  end if;

  if v_event.status_operacional in ('pausado', 'concluido', 'cancelado') then
    raise exception 'EVENT_OPERATION_BLOCKED' using errcode = '42501';
  end if;

  if v_event.operacao_temporaria then
    perform public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio']);
  elsif v_event.parque_id is null or not public.usuario_tem_parque(v_event.parque_id) then
    raise exception 'EVENT_ACCESS_REQUIRED' using errcode = '42501';
  end if;

  if length(btrim(coalesce(p_nome, ''))) not between 1 and 100
    or p_ordem is null or p_ordem < 0
    or p_valor is null or p_valor < 0 then
    raise exception 'CATEGORY_FIELDS_INVALID' using errcode = '22023';
  end if;

  update public.categorias
     set nome = btrim(p_nome), ordem = p_ordem, valor_inscricao = p_valor
   where id = p_categoria_id and evento_id = p_evento_id;
  return found;
end;
$$;

create or replace function public.painel_reativar_categoria(p_categoria_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_event public.eventos%rowtype;
begin
  select e.* into v_event
    from public.categorias c
    join public.eventos e on e.id = c.evento_id
   where c.id = p_categoria_id;
  if not found then
    raise exception 'CATEGORY_NOT_FOUND' using errcode = '42501';
  end if;

  if v_event.status_operacional in ('pausado', 'concluido', 'cancelado') then
    raise exception 'EVENT_OPERATION_BLOCKED' using errcode = '42501';
  end if;

  if v_event.operacao_temporaria then
    perform public.pista_ops_check_access(v_event.id, array['organizador', 'escritorio']);
  elsif v_event.parque_id is null or not public.usuario_tem_parque(v_event.parque_id) then
    raise exception 'EVENT_ACCESS_REQUIRED' using errcode = '42501';
  end if;

  update public.categorias set ativa = true where id = p_categoria_id;
  return found;
end;
$$;

create or replace function public.painel_excluir_categoria(
  p_evento_id uuid,
  p_categoria_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_event public.eventos%rowtype;
begin
  select e.* into v_event
    from public.categorias c
    join public.eventos e on e.id = c.evento_id
   where c.id = p_categoria_id and c.evento_id = p_evento_id;
  if not found then
    raise exception 'CATEGORY_NOT_FOUND' using errcode = '42501';
  end if;

  if v_event.status_operacional in ('pausado', 'concluido', 'cancelado') then
    raise exception 'EVENT_OPERATION_BLOCKED' using errcode = '42501';
  end if;

  if v_event.operacao_temporaria then
    perform public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio']);
  elsif v_event.parque_id is null or not public.usuario_tem_parque(v_event.parque_id) then
    raise exception 'EVENT_ACCESS_REQUIRED' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.duplas
     where evento_id = p_evento_id and categoria_id = p_categoria_id
  ) then
    raise exception 'CATEGORY_HAS_INSCRIPTIONS' using errcode = '23503';
  end if;

  begin
    delete from public.categorias
     where id = p_categoria_id and evento_id = p_evento_id;
  exception
    when foreign_key_violation then
      raise exception 'CATEGORY_IN_USE' using errcode = '23503';
  end;

  return found;
end;
$$;

revoke all on function public.painel_editar_categoria(uuid, uuid, text, integer, numeric) from public, anon;
revoke all on function public.painel_reativar_categoria(uuid) from public, anon;
revoke all on function public.painel_excluir_categoria(uuid, uuid) from public, anon;
grant execute on function public.painel_editar_categoria(uuid, uuid, text, integer, numeric) to authenticated;
grant execute on function public.painel_reativar_categoria(uuid) to authenticated;
grant execute on function public.painel_excluir_categoria(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
