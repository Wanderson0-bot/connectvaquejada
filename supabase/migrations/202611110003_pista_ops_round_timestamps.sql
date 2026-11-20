alter table public.pista_ops_rounds
  add column if not exists terminado_em timestamptz;

create or replace function public.pista_ops_round_record_times()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.estado = 'ativo' and old.estado is distinct from 'ativo' then
    new.iniciado_em := coalesce(new.iniciado_em, now());
  end if;

  if old.estado = 'ativo'
    and new.estado in ('finalizado', 'aguardando_proximo_rodizio') then
    new.terminado_em := coalesce(new.terminado_em, now());
  end if;

  return new;
end;
$$;

drop trigger if exists pista_ops_round_record_times on public.pista_ops_rounds;
create trigger pista_ops_round_record_times
before update of estado on public.pista_ops_rounds
for each row execute function public.pista_ops_round_record_times();
revoke all on function public.pista_ops_round_record_times() from public, anon, authenticated;

create or replace function public.pista_ops_round_timestamps(
  p_evento_id uuid,
  p_categoria_id uuid
)
returns table(id uuid, iniciado_em timestamptz, terminado_em timestamptz)
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
begin
  perform public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio', 'locutor']);

  if not exists (
    select 1 from public.categorias c
    where c.id = p_categoria_id and c.evento_id = p_evento_id
  ) then
    raise exception using errcode = 'P0001', message = 'PISTA_CATEGORY_OUT_OF_EVENT';
  end if;

  return query
    select r.id, r.iniciado_em, r.terminado_em
    from public.pista_ops_rounds r
    where r.evento_id = p_evento_id and r.categoria_id = p_categoria_id
    order by r.numero desc;
end;
$$;

revoke all on function public.pista_ops_round_timestamps(uuid, uuid) from public, anon;
grant execute on function public.pista_ops_round_timestamps(uuid, uuid) to authenticated;
