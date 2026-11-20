begin;

create or replace function public.painel_criar_categorias_padrao(p_evento_id uuid)
returns void
language sql
set search_path = pg_catalog, public
as $$
  insert into public.categorias(evento_id, nome, ordem, valor_inscricao, ativa)
  values
    (p_evento_id, 'Tropa de Elite', 1, 0, true),
    (p_evento_id, 'Profissional', 2, 0, true),
    (p_evento_id, 'Amador', 3, 0, true),
    (p_evento_id, 'Iniciante', 4, 0, true),
    (p_evento_id, 'Mirim', 5, 0, true),
    (p_evento_id, 'Feminino', 6, 0, true);
$$;

revoke all on function public.painel_criar_categorias_padrao(uuid) from public, anon, authenticated;

create or replace function public.painel_iniciar_operacao(p_nome text)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_id uuid;
  v_nome text := btrim(coalesce(p_nome, ''));
begin
  if v_actor is null or not exists(select 1 from public.perfis p where p.id = v_actor) then
    raise exception 'OPERATION_ADMIN_PROFILE_REQUIRED' using errcode = '42501';
  end if;
  if length(v_nome) = 0 or length(v_nome) > 120 then
    raise exception 'OPERATION_NAME_INVALID' using errcode = '22023';
  end if;

  insert into public.eventos(parque_id, nome, data, status, status_operacional, operacao_temporaria)
  values (null, v_nome, current_date, 'rascunho', 'em_andamento', true)
  returning id into v_id;

  insert into public.pista_ops_members(evento_id, usuario_id, funcao, ativo, criado_por)
  values (v_id, v_actor, 'organizador', true, v_actor);

  perform public.painel_criar_categorias_padrao(v_id);
  return v_id;
end;
$$;

create or replace function public.painel_criar_evento(p_parque_id uuid, p_nome text, p_data date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
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

  perform public.painel_criar_categorias_padrao(v_evento);
  return v_evento;
end;
$$;

notify pgrst, 'reload schema';

commit;
