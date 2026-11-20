begin;

create or replace function public.pista_ops_active_round_event(p_evento_id uuid)
returns table(
  id uuid,
  categoria_id uuid,
  categoria_nome text,
  numero integer,
  estado text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
begin
  perform public.pista_ops_check_access(p_evento_id, array['organizador', 'escritorio', 'locutor']);

  return query
  select r.id, r.categoria_id, c.nome, r.numero, r.estado
    from public.pista_ops_rounds r
    join public.categorias c on c.id = r.categoria_id
   where r.evento_id = p_evento_id
     and r.estado in ('ativo', 'aguardando_proximo_rodizio')
   order by case r.estado when 'ativo' then 0 else 1 end, r.numero desc
   limit 1;
end;
$$;

revoke all on function public.pista_ops_active_round_event(uuid) from public, anon;
grant execute on function public.pista_ops_active_round_event(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
