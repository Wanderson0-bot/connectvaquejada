begin;

create or replace function public.painel_cancelar_inscricao(
  p_evento_id uuid,
  p_inscricao_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_event public.eventos%rowtype;
begin
  select * into v_event
    from public.eventos
   where id = p_evento_id;
  if not found
    or (v_event.operacao_temporaria and v_event.status_operacional <> 'em_andamento')
    or (not v_event.operacao_temporaria and v_event.status_operacional in ('pausado', 'concluido', 'cancelado'))
  then
    raise exception 'EVENT_OPERATION_BLOCKED' using errcode = '42501';
  end if;

  if v_event.operacao_temporaria then
    perform public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio']);
  elsif v_event.parque_id is null or not public.usuario_tem_parque(v_event.parque_id) then
    raise exception 'EVENT_ACCESS_REQUIRED' using errcode = '42501';
  end if;

  update public.duplas
     set status_pagamento = 'cancelado', motivo_isencao = null
   where id = p_inscricao_id
     and evento_id = p_evento_id
     and status_pagamento <> 'cancelado';

  if not found then
    raise exception 'INSCRIPTION_NOT_FOUND_OR_CANCELLED' using errcode = '22023';
  end if;

  return true;
end;
$$;

revoke all on function public.painel_cancelar_inscricao(uuid, uuid) from public, anon;
grant execute on function public.painel_cancelar_inscricao(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
