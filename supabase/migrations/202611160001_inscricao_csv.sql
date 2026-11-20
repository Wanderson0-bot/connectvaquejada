begin;

create or replace function public.inscrever_competidores_evento_csv(
  p_evento_id uuid,
  p_inscricoes jsonb
)
returns integer
language plpgsql
security invoker
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_inscricao jsonb;
  v_importadas integer := 0;
begin
  if p_evento_id is null
    or p_inscricoes is null
    or jsonb_typeof(p_inscricoes) is distinct from 'array'
    or jsonb_array_length(p_inscricoes) not between 1 and 1000
  then
    raise exception 'CSV_IMPORT_INVALID_INPUT' using errcode = '22023';
  end if;

  for v_inscricao in select value from jsonb_array_elements(p_inscricoes)
  loop
    if jsonb_typeof(v_inscricao) is distinct from 'object'
      or jsonb_typeof(v_inscricao->'numero_senha') is distinct from 'number'
      or jsonb_typeof(v_inscricao->'nome') is distinct from 'string'
      or jsonb_typeof(v_inscricao->'categoria_id') is distinct from 'string'
      or jsonb_typeof(v_inscricao->'nome_equipe') is distinct from 'string'
      or jsonb_typeof(v_inscricao->'nome_cavalo') is distinct from 'string'
    then
      raise exception 'CSV_IMPORT_INVALID_ROW' using errcode = '22023';
    end if;

    perform 1
      from public.inscrever_competidor_evento_multiplas_senhas(
        p_evento_id,
        (v_inscricao->>'categoria_id')::uuid,
        v_inscricao->>'nome',
        array[(v_inscricao->>'numero_senha')::integer],
        nullif(v_inscricao->>'nome_cavalo', ''),
        nullif(v_inscricao->>'nome_equipe', ''),
        'pendente',
        null
      );

    v_importadas := v_importadas + 1;
  end loop;

  return v_importadas;
end;
$$;

revoke all on function public.inscrever_competidores_evento_csv(uuid, jsonb) from public, anon;
grant execute on function public.inscrever_competidores_evento_csv(uuid, jsonb) to authenticated;

notify pgrst, 'reload schema';

commit;
