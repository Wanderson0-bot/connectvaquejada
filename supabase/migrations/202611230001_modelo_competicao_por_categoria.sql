begin;

-- Preserve the existing column in environments where it has already been created.
alter table public.categorias
  add column if not exists modelo_competicao text generated always as (
    case when lower(btrim(nome)) = 'tropa de elite' then 'eliminatoria' else 'classificatoria' end
  ) stored;

create or replace function public.pista_ops_categorias(p_evento_id uuid)
returns table (id uuid, nome text, modelo_competicao text)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  perform public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio', 'locutor']);
  return query
    select c.id, c.nome::text, c.modelo_competicao
      from public.categorias c
     where c.evento_id = p_evento_id
     order by c.ordem, c.nome;
end;
$$;

revoke all on function public.pista_ops_categorias(uuid) from public, anon;
grant execute on function public.pista_ops_categorias(uuid) to authenticated;

create or replace function public.pista_ops_tropa_elite_round_guard()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if exists (
    select 1 from public.categorias c
     where c.id = new.categoria_id and c.evento_id = new.evento_id
       and c.modelo_competicao = 'eliminatoria'
  ) then
    raise exception using errcode = '22023', message = 'PISTA_TROPA_ELITE_USES_X1';
  end if;
  return new;
end;
$$;

create or replace trigger pista_tropa_elite_round_guard
  before insert on public.pista_rodizios
  for each row execute function public.pista_ops_tropa_elite_round_guard();

create or replace function public.x1_criar_chave(
  p_evento_id uuid,
  p_categoria_id uuid,
  p_melhor_de smallint,
  p_duplas uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_actor uuid;
  v_id uuid;
  v_n integer;
  v_power integer;
  v_rounds integer;
  v_i integer;
  v_round integer;
  v_pos integer;
  v_modelo text;
begin
  v_actor := public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio']);
  select c.modelo_competicao into v_modelo
    from public.categorias c
   where c.evento_id = p_evento_id and c.id = p_categoria_id;

  if v_modelo is null or p_melhor_de is null
    or (v_modelo = 'eliminatoria' and p_melhor_de <> 1)
    or (v_modelo = 'classificatoria' and p_melhor_de not in (3, 5))
    or coalesce(cardinality(p_duplas), 0) < 2
    or cardinality(p_duplas) > 16 then
    raise exception 'X1_CONFIG_INVALID';
  end if;

  select count(*) into v_n
    from unnest(p_duplas) x(id)
    join public.duplas d on d.id = x.id
   where d.evento_id = p_evento_id
     and d.categoria_id = p_categoria_id
     and d.status_pagamento in ('pago', 'isento');
  if v_n <> cardinality(p_duplas)
    or v_n <> (select count(distinct x) from unnest(p_duplas) x) then
    raise exception 'X1_ENTRIES_INVALID';
  end if;

  v_power := 1;
  v_rounds := 0;
  while v_power < v_n loop
    v_power := v_power * 2;
    v_rounds := v_rounds + 1;
  end loop;

  insert into public.x1_brackets(evento_id, categoria_id, melhor_de, criado_por)
  values (p_evento_id, p_categoria_id, p_melhor_de, v_actor)
  returning id into v_id;

  for v_round in 1..v_rounds loop
    for v_pos in 1..(v_power / (2 ^ v_round)::integer) loop
      insert into public.x1_matches(chave_id, evento_id, categoria_id, fase, posicao)
      values (v_id, p_evento_id, p_categoria_id, v_round, v_pos);
    end loop;
  end loop;

  for v_i in 1..v_n loop
    v_pos := (v_i + 1) / 2;
    if v_i % 2 = 1 then
      update public.x1_matches
         set lado_a = p_duplas[v_i]
       where chave_id = v_id and fase = 1 and posicao = v_pos;
    else
      update public.x1_matches
         set lado_b = p_duplas[v_i]
       where chave_id = v_id and fase = 1 and posicao = v_pos;
    end if;
  end loop;

  for v_round in 1..v_rounds loop
    for v_pos in 1..(v_power / (2 ^ v_round)::integer) loop
      update public.x1_matches
         set estado = 'em_andamento'
       where chave_id = v_id and fase = v_round and posicao = v_pos
         and lado_a is not null and lado_b is not null;
      update public.x1_matches
         set estado = 'finalizada', vencedor_id = coalesce(lado_a, lado_b)
       where chave_id = v_id and fase = v_round and posicao = v_pos
         and num_nonnulls(lado_a, lado_b) = 1;
      if v_round < v_rounds then
        select vencedor_id into v_actor
          from public.x1_matches
         where chave_id = v_id and fase = v_round and posicao = v_pos
           and estado = 'finalizada' and num_nonnulls(lado_a, lado_b) = 1;
        if found then
          if v_pos % 2 = 1 then
            update public.x1_matches
               set lado_a = v_actor
             where chave_id = v_id and fase = v_round + 1 and posicao = (v_pos + 1) / 2;
          else
            update public.x1_matches
               set lado_b = v_actor
             where chave_id = v_id and fase = v_round + 1 and posicao = (v_pos + 1) / 2;
          end if;
        end if;
      end if;
    end loop;
  end loop;

  update public.x1_matches
     set estado = 'em_andamento'
   where chave_id = v_id and estado = 'aguardando'
     and lado_a is not null and lado_b is not null;
  update public.x1_brackets
     set estado = 'finalizada'
   where id = v_id and exists (
     select 1 from public.x1_matches
      where chave_id = v_id and fase = v_rounds and estado = 'finalizada'
   );
  update public.x1_brackets set estado = 'em_andamento' where id = v_id;
  return v_id;
end;
$$;

notify pgrst, 'reload schema';

commit;
