begin;

create or replace function public.pista_ops_queue_item_details(p_item_fila_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_evento_id uuid;
  v_details jsonb;
begin
  select r.evento_id into v_evento_id
    from public.pista_ops_queue_items q
    join public.pista_ops_rounds r on r.id = q.rodada_id
   where q.id = p_item_fila_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'PISTA_QUEUE_ITEM_NOT_FOUND';
  end if;

  perform public.pista_ops_check_access(v_evento_id, array['organizador', 'escritorio', 'locutor']);

  select jsonb_build_object(
    'vaqueiro', c.nome,
    'cavalo', d.nome_cavalo,
    'equipe', d.nome_equipe
  ) into v_details
    from public.pista_ops_queue_items q
    join public.duplas d on d.id = q.dupla_id
    left join public.competidores c on c.id = coalesce(q.competidor_real_id, d.puxador_id)
   where q.id = p_item_fila_id;

  return v_details;
end;
$$;

revoke all on function public.pista_ops_queue_item_details(uuid) from public, anon;
grant execute on function public.pista_ops_queue_item_details(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
