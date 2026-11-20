begin;

drop function if exists public.inscrever_competidor_evento(uuid, uuid, text, integer, text, text);

create function public.inscrever_competidor_evento(
  p_evento_id uuid,
  p_categoria_id uuid,
  p_nome text,
  p_numero_senha integer,
  p_nome_cavalo text,
  p_nome_equipe text,
  p_status_pagamento text,
  p_motivo_isencao text
)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  actor_parque_id uuid;
  event_parque_id uuid;
  new_competidor_id uuid;
  new_inscricao_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'INSCRICAO_AUTH_REQUIRED';
  end if;

  if p_evento_id is null
    or p_categoria_id is null
    or p_nome is null
    or length(btrim(p_nome)) = 0
    or length(btrim(p_nome)) > 120
    or p_numero_senha is null
    or p_numero_senha < 1
    or length(btrim(coalesce(p_nome_cavalo, ''))) > 120
    or length(btrim(coalesce(p_nome_equipe, ''))) > 120
    or p_status_pagamento is null
    or p_status_pagamento not in ('pendente', 'pago', 'isento')
    or (p_status_pagamento = 'isento' and (
      length(btrim(coalesce(p_motivo_isencao, ''))) = 0
      or length(btrim(p_motivo_isencao)) > 500
    )) then
    raise exception using errcode = '22023', message = 'INSCRICAO_INVALID_FIELDS';
  end if;

  actor_parque_id := public.meu_parque_id();
  select e.parque_id into event_parque_id
    from public.eventos e
   where e.id = p_evento_id;

  if event_parque_id is null or actor_parque_id is distinct from event_parque_id then
    raise exception using errcode = '42501', message = 'INSCRICAO_EVENT_ACCESS_DENIED';
  end if;

  if not exists (
    select 1 from public.categorias c
     where c.id = p_categoria_id and c.evento_id = p_evento_id
  ) then
    raise exception using errcode = '22023', message = 'INSCRICAO_CATEGORY_INVALID';
  end if;

  insert into public.competidores (parque_id, nome)
  values (actor_parque_id, btrim(p_nome))
  returning id into new_competidor_id;

  insert into public.duplas (
    evento_id, categoria_id, puxador_id, numero_senha, nome_cavalo, nome_equipe,
    status_pagamento, motivo_isencao
  ) values (
    p_evento_id,
    p_categoria_id,
    new_competidor_id,
    p_numero_senha,
    nullif(btrim(coalesce(p_nome_cavalo, '')), ''),
    nullif(btrim(coalesce(p_nome_equipe, '')), ''),
    p_status_pagamento,
    case when p_status_pagamento = 'isento' then btrim(p_motivo_isencao) else null end
  ) returning id into new_inscricao_id;

  return new_inscricao_id;
end;
$$;

revoke all on function public.inscrever_competidor_evento(uuid, uuid, text, integer, text, text, text, text)
  from public, anon;
grant execute on function public.inscrever_competidor_evento(uuid, uuid, text, integer, text, text, text, text)
  to authenticated;

notify pgrst, 'reload schema';

commit;
