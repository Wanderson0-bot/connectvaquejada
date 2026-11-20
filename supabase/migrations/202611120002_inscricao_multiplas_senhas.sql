begin;

create or replace function public.inscrever_competidor_evento_multiplas_senhas(
  p_evento_id uuid,
  p_categoria_id uuid,
  p_nome text,
  p_numeros_senha integer[],
  p_nome_cavalo text,
  p_nome_equipe text,
  p_status_pagamento text,
  p_motivo_isencao text
)
returns setof uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_event public.eventos%rowtype;
  v_actor uuid;
  v_competidor uuid;
  v_numero integer;
  v_inscricao uuid;
begin
  if p_evento_id is null
    or p_categoria_id is null
    or length(btrim(coalesce(p_nome, ''))) not between 1 and 120
    or p_numeros_senha is null
    or cardinality(p_numeros_senha) not between 1 and 100
    or array_position(p_numeros_senha, null) is not null
    or exists (
      select 1
        from unnest(p_numeros_senha) as senha(numero)
       where senha.numero < 1
    )
    or (select count(distinct senha.numero) from unnest(p_numeros_senha) as senha(numero)) <> cardinality(p_numeros_senha)
    or length(btrim(coalesce(p_nome_cavalo, ''))) > 120
    or length(btrim(coalesce(p_nome_equipe, ''))) > 120
    or p_status_pagamento is null
    or p_status_pagamento not in ('pendente', 'pago', 'isento')
    or (p_status_pagamento = 'isento' and length(btrim(coalesce(p_motivo_isencao, ''))) not between 1 and 500)
  then
    raise exception 'INSCRICAO_INVALID_FIELDS' using errcode = '22023';
  end if;

  select * into v_event from public.eventos where id = p_evento_id;
  if not found
    or (v_event.operacao_temporaria and v_event.status_operacional <> 'em_andamento')
    or (not v_event.operacao_temporaria and v_event.status_operacional in ('pausado', 'concluido', 'cancelado'))
  then
    raise exception 'EVENT_OPERATION_BLOCKED' using errcode = '42501';
  end if;

  if v_event.operacao_temporaria then
    v_actor := public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio']);
    if not exists (
      select 1 from public.categorias c
       where c.id = p_categoria_id and c.evento_id = p_evento_id and c.ativa
    ) then
      raise exception 'INSCRICAO_CATEGORY_INVALID' using errcode = '22023';
    end if;
    insert into public.competidores(parque_id, evento_id, nome)
    values (null, p_evento_id, btrim(p_nome)) returning id into v_competidor;
  else
    v_actor := auth.uid();
    if v_actor is null or v_event.parque_id is null or not public.usuario_tem_parque(v_event.parque_id) then
      raise exception 'INSCRICAO_EVENT_ACCESS_DENIED' using errcode = '42501';
    end if;
    if not exists (
      select 1 from public.categorias c
       where c.id = p_categoria_id and c.evento_id = p_evento_id and c.ativa
    ) then
      raise exception 'INSCRICAO_CATEGORY_INVALID' using errcode = '22023';
    end if;
    insert into public.competidores(parque_id, nome)
    values (v_event.parque_id, btrim(p_nome)) returning id into v_competidor;
  end if;

  foreach v_numero in array p_numeros_senha loop
    insert into public.duplas(
      evento_id, categoria_id, puxador_id, numero_senha, nome_cavalo, nome_equipe,
      status_pagamento, motivo_isencao
    ) values (
      p_evento_id, p_categoria_id, v_competidor, v_numero,
      nullif(btrim(coalesce(p_nome_cavalo, '')), ''),
      nullif(btrim(coalesce(p_nome_equipe, '')), ''),
      p_status_pagamento,
      case when p_status_pagamento = 'isento' then btrim(p_motivo_isencao) else null end
    ) returning id into v_inscricao;
    return next v_inscricao;
  end loop;

  return;
end;
$$;

revoke all on function public.inscrever_competidor_evento_multiplas_senhas(uuid, uuid, text, integer[], text, text, text, text) from public, anon;
grant execute on function public.inscrever_competidor_evento_multiplas_senhas(uuid, uuid, text, integer[], text, text, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;
