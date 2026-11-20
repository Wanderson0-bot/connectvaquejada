begin;

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
  actor_park_id uuid;
  target_id uuid;
  target_park_id uuid;
  event_park_id uuid;
  temporary_event boolean;
begin
  actor_id := public.pista_ops_check_access(p_evento_id, array['organizador']);
  if p_funcao not in ('organizador', 'escritorio', 'locutor') then
    raise exception using errcode = '22023', message = 'PISTA_INVALID_ROLE';
  end if;

  select e.parque_id, e.operacao_temporaria
    into event_park_id, temporary_event
    from public.eventos e
   where e.id = p_evento_id
   for update;
  select p.parque_id into actor_park_id
    from public.perfis p
   where p.id = actor_id;
  select p.id, p.parque_id
    into target_id, target_park_id
    from public.perfis p
   where p.id = p_usuario_id;

  if not found
    or (temporary_event and (actor_park_id is null or target_park_id is distinct from actor_park_id))
    or (not temporary_event and target_park_id is distinct from event_park_id) then
    raise exception using errcode = '42501', message = 'PISTA_MEMBER_PARK_MISMATCH';
  end if;

  if p_ativo then
    select m.id into target_id
      from public.pista_ops_members m
     where m.evento_id = p_evento_id
       and m.usuario_id = p_usuario_id
       and m.funcao = p_funcao
       and m.ativo
     for update;
    if found then return target_id; end if;
    insert into public.pista_ops_members(evento_id, usuario_id, funcao, ativo, criado_por)
    values (p_evento_id, p_usuario_id, p_funcao, true, actor_id)
    returning id into target_id;
  else
    update public.pista_ops_members
       set ativo = false, revogado_em = now(), revogado_por = actor_id
     where evento_id = p_evento_id
       and usuario_id = p_usuario_id
       and funcao = p_funcao
       and ativo
    returning id into target_id;
    if not found then
      raise exception using errcode = 'P0001', message = 'PISTA_ACTIVE_MEMBER_NOT_FOUND';
    end if;
  end if;
  return target_id;
end;
$$;

notify pgrst, 'reload schema';
commit;
