-- A segunda corrida da inscrição só fica disponível depois que a primeira
-- termina com Valeu Boi. Zero encerra o direito à segunda corrida.

alter table public.pista_ops_runs
  drop constraint pista_ops_runs_estado_check;

alter table public.pista_ops_runs
  add constraint pista_ops_runs_estado_check
  check (estado in ('pendente', 'retorno_pendente', 'em_curso', 'zero', 'valeu_boi', 'sem_direito'));

-- Corrige inscrições já apuradas: uma segunda corrida ainda pendente após
-- Zero deixa de aparecer como corrida disponível.
update public.pista_ops_runs second_run
   set estado = 'sem_direito', pontuacao = null, atualizado_em = now()
  from public.pista_ops_runs first_run
 where second_run.dupla_id = first_run.dupla_id
   and second_run.numero_corrida = 2
   and first_run.numero_corrida = 1
   and first_run.estado = 'zero'
   and second_run.estado in ('pendente', 'retorno_pendente');

update public.pista_ops_queue_items q
   set estado = 'encaminhada'
  from public.pista_ops_runs second_run
  join public.pista_ops_runs first_run
    on first_run.dupla_id = second_run.dupla_id
   and first_run.numero_corrida = 1
 where q.corrida_id = second_run.id
   and second_run.numero_corrida = 2
   and first_run.estado is distinct from 'valeu_boi'
   and second_run.estado in ('pendente', 'retorno_pendente', 'sem_direito')
   and q.estado in ('na_fila', 'retorno_pendente', 'aguardando_proximo');

create or replace function public.pista_ops_guardar_segunda_corrida_na_fila()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.tipo = 'regular' and new.corrida_id is not null and exists (
    select 1
      from public.pista_ops_runs second_run
     where second_run.id = new.corrida_id
       and second_run.numero_corrida = 2
  ) and not exists (
    select 1
      from public.pista_ops_runs second_run
      join public.pista_ops_runs first_run
        on first_run.dupla_id = second_run.dupla_id
       and first_run.numero_corrida = 1
     where second_run.id = new.corrida_id
       and first_run.estado = 'valeu_boi'
  ) then
    return null;
  end if;

  return new;
end;
$$;

create trigger pista_ops_second_run_queue_guard
before insert on public.pista_ops_queue_items
for each row execute function public.pista_ops_guardar_segunda_corrida_na_fila();

create or replace function public.pista_ops_atualizar_direito_segunda_corrida()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  second_run public.pista_ops_runs%rowtype;
  active_round_id uuid;
begin
  if new.numero_corrida <> 1
    or new.estado not in ('zero', 'valeu_boi')
    or new.estado = old.estado then
    return new;
  end if;

  select * into second_run
    from public.pista_ops_runs r
   where r.dupla_id = new.dupla_id and r.numero_corrida = 2
   for update;
  if not found then return new; end if;

  if new.estado = 'zero' then
    if old.estado = 'valeu_boi' and second_run.estado in ('em_curso', 'zero', 'valeu_boi') then
      raise exception using errcode = 'P0001', message = 'PISTA_SECOND_RUN_ALREADY_USED';
    end if;

    if second_run.estado in ('pendente', 'retorno_pendente') then
      update public.pista_ops_runs
         set estado = 'sem_direito', pontuacao = null, atualizado_em = now()
       where id = second_run.id;

      update public.pista_ops_queue_items
         set estado = 'encaminhada'
       where corrida_id = second_run.id
         and estado in ('na_fila', 'retorno_pendente', 'aguardando_proximo');
    end if;

    return new;
  end if;

  if second_run.estado = 'sem_direito' then
    update public.pista_ops_runs
       set estado = 'pendente', pontuacao = null, atualizado_em = now()
     where id = second_run.id;
  end if;

  select r.id into active_round_id
    from public.pista_ops_rounds r
   where r.evento_id = new.evento_id
     and r.categoria_id = new.categoria_id
     and r.estado = 'ativo'
   order by r.numero desc
   limit 1;

  if active_round_id is not null and second_run.estado in ('pendente', 'sem_direito') then
    update public.pista_ops_runs
       set rodada_atual_id = active_round_id, atualizado_em = now()
     where id = second_run.id;

    update public.pista_ops_queue_items
       set estado = 'na_fila'
     where rodada_id = active_round_id and corrida_id = second_run.id and estado = 'encaminhada';

    if not found then
      insert into public.pista_ops_queue_items(
        rodada_id, dupla_id, corrida_id, tipo, estado, eh_retorno, competidor_real_id
      ) values (
        active_round_id, second_run.dupla_id, second_run.id, 'regular', 'na_fila', false,
        second_run.competidor_real_id
      ) on conflict (rodada_id, corrida_id) where tipo = 'regular' do nothing;
    end if;
  end if;

  return new;
end;
$$;

create trigger pista_ops_second_run_eligibility
after update of estado on public.pista_ops_runs
for each row execute function public.pista_ops_atualizar_direito_segunda_corrida();

revoke all on function public.pista_ops_guardar_segunda_corrida_na_fila() from public, anon, authenticated;
revoke all on function public.pista_ops_atualizar_direito_segunda_corrida() from public, anon, authenticated;
