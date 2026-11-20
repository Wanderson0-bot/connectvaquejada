begin;

create or replace function public.painel_criar_categoria(
  p_evento_id uuid,
  p_nome text,
  p_ordem integer,
  p_valor numeric
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_event public.eventos%rowtype;
  v_id uuid;
begin
  select * into v_event from public.eventos where id = p_evento_id;
  if not found then
    raise exception 'EVENT_NOT_FOUND' using errcode = '42501';
  end if;

  if v_event.status_operacional in ('pausado', 'concluido', 'cancelado') then
    raise exception 'EVENT_OPERATION_BLOCKED' using errcode = '42501';
  end if;

  if v_event.operacao_temporaria then
    perform public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio']);
  elsif v_event.parque_id is null or not public.usuario_tem_parque(v_event.parque_id) then
    raise exception 'EVENT_ACCESS_REQUIRED' using errcode = '42501';
  end if;

  if length(btrim(coalesce(p_nome, ''))) = 0
    or length(btrim(p_nome)) > 100
    or p_ordem is null or p_ordem < 0
    or p_valor is null or p_valor < 0 then
    raise exception 'CATEGORY_FIELDS_INVALID' using errcode = '22023';
  end if;

  insert into public.categorias(evento_id, nome, ordem, valor_inscricao, ativa)
  values (p_evento_id, btrim(p_nome), p_ordem, p_valor, true)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.painel_ocultar_categoria(p_categoria_id uuid)
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

  update public.categorias set ativa = false where id = p_categoria_id;
  return found;
end;
$$;

grant execute on function public.painel_criar_categoria(uuid, text, integer, numeric) to authenticated;
grant execute on function public.painel_ocultar_categoria(uuid) to authenticated;
revoke all on function public.painel_criar_categoria(uuid, text, integer, numeric) from public, anon;
revoke all on function public.painel_ocultar_categoria(uuid) from public, anon;

notify pgrst, 'reload schema';
commit;
