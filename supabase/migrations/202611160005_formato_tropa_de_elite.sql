begin;

alter table public.eventos
  add column if not exists formato_competicao text not null default 'tradicional';

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.eventos'::regclass
       and conname = 'eventos_formato_competicao_ck'
  ) then
    alter table public.eventos
      add constraint eventos_formato_competicao_ck
      check (formato_competicao in ('tradicional', 'tropa_de_elite'));
  end if;
end;
$$;

create or replace function public.painel_iniciar_operacao_com_formato(
  p_nome text,
  p_formato_competicao text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_evento_id uuid;
begin
  if p_formato_competicao is null
    or p_formato_competicao not in ('tradicional', 'tropa_de_elite') then
    raise exception 'OPERATION_FORMAT_INVALID' using errcode = '22023';
  end if;

  v_evento_id := public.painel_iniciar_operacao(p_nome);
  update public.eventos
     set formato_competicao = p_formato_competicao
   where id = v_evento_id;
  return v_evento_id;
end;
$$;

create or replace function public.painel_criar_evento_com_formato(
  p_parque_id uuid,
  p_nome text,
  p_data date,
  p_formato_competicao text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_evento_id uuid;
begin
  if p_formato_competicao is null
    or p_formato_competicao not in ('tradicional', 'tropa_de_elite') then
    raise exception 'EVENT_FORMAT_INVALID' using errcode = '22023';
  end if;

  v_evento_id := public.painel_criar_evento(p_parque_id, p_nome, p_data);
  update public.eventos
     set formato_competicao = p_formato_competicao
   where id = v_evento_id;
  return v_evento_id;
end;
$$;

revoke all on function public.painel_iniciar_operacao_com_formato(text, text)
  from public, anon;
revoke all on function public.painel_criar_evento_com_formato(uuid, text, date, text)
  from public, anon;
grant execute on function public.painel_iniciar_operacao_com_formato(text, text)
  to authenticated;
grant execute on function public.painel_criar_evento_com_formato(uuid, text, date, text)
  to authenticated;

create or replace function public.pista_ops_tropa_elite_round_guard()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if exists (
    select 1
      from public.eventos e
     where e.id = new.evento_id
       and e.formato_competicao = 'tropa_de_elite'
  ) then
    raise exception using errcode = '22023', message = 'PISTA_TROPA_ELITE_USES_X1';
  end if;
  return new;
end;
$$;

revoke all on function public.pista_ops_tropa_elite_round_guard()
  from public, anon, authenticated;

drop trigger if exists pista_ops_tropa_elite_round_guard on public.pista_ops_rounds;
create trigger pista_ops_tropa_elite_round_guard
  before insert on public.pista_ops_rounds
  for each row execute function public.pista_ops_tropa_elite_round_guard();

alter table public.x1_brackets
  drop constraint if exists x1_brackets_melhor_de_check;
alter table public.x1_brackets
  add constraint x1_brackets_melhor_de_check
  check (melhor_de in (1, 3, 5));

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
  v_formato text;
begin
  v_actor := public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio']);
  select e.formato_competicao into v_formato
    from public.eventos e
   where e.id = p_evento_id;

  if p_melhor_de is null
    or (v_formato = 'tropa_de_elite' and p_melhor_de <> 1)
    or (v_formato <> 'tropa_de_elite' and p_melhor_de not in (3, 5))
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

revoke all on function public.x1_criar_chave(uuid, uuid, smallint, uuid[])
  from public, anon;
grant execute on function public.x1_criar_chave(uuid, uuid, smallint, uuid[])
  to authenticated;

notify pgrst, 'reload schema';

commit;
