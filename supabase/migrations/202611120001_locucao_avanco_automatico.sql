begin;

alter table public.pista_ops_rounds
  add column chamada_automatica_pausada boolean not null default false;

create or replace function public.pista_ops_chamada_automatica_status(p_rodizio_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  target public.pista_ops_rounds%rowtype;
begin
  select * into target from public.pista_ops_rounds where id = p_rodizio_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'PISTA_ROUND_NOT_FOUND';
  end if;
  perform public.pista_ops_check_access(target.evento_id, array['organizador', 'locutor']);
  return target.chamada_automatica_pausada;
end;
$$;

create or replace function public.pista_ops_configurar_chamada_automatica(
  p_rodizio_id uuid,
  p_pausada boolean
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  target public.pista_ops_rounds%rowtype;
begin
  if p_pausada is null then
    raise exception using errcode = '22023', message = 'PISTA_AUTO_CALL_STATE_REQUIRED';
  end if;
  select * into target from public.pista_ops_rounds where id = p_rodizio_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'PISTA_ROUND_NOT_FOUND';
  end if;
  perform public.pista_ops_check_access(target.evento_id, array['organizador', 'locutor']);
  perform public.pista_ops_lock_category(target.evento_id, target.categoria_id);
  select * into target from public.pista_ops_rounds where id = p_rodizio_id for update;
  if target.estado <> 'ativo' then
    raise exception using errcode = 'P0001', message = 'PISTA_ROUND_NOT_ACTIVE';
  end if;
  update public.pista_ops_rounds
     set chamada_automatica_pausada = p_pausada
   where id = target.id;
  return p_pausada;
end;
$$;

create or replace function public.pista_ops_chamar_proxima_automatica(
  p_rodizio_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  target public.pista_ops_rounds%rowtype;
begin
  if p_request_id is null then
    raise exception using errcode = '22023', message = 'PISTA_REQUEST_ID_REQUIRED';
  end if;
  select * into target from public.pista_ops_rounds where id = p_rodizio_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'PISTA_ROUND_NOT_FOUND';
  end if;
  perform public.pista_ops_check_access(target.evento_id, array['organizador', 'locutor']);
  perform public.pista_ops_lock_category(target.evento_id, target.categoria_id);
  select * into target from public.pista_ops_rounds where id = p_rodizio_id for update;
  if target.estado <> 'ativo' then
    return jsonb_build_object('status', 'rodizio_inativo');
  end if;
  if target.chamada_automatica_pausada then
    return jsonb_build_object('status', 'pausada');
  end if;
  if exists (
    select 1 from public.pista_ops_queue_items q
     where q.rodada_id = target.id and q.estado = 'chamada'
  ) then
    return jsonb_build_object('status', 'ja_chamada');
  end if;
  return public.pista_ops_chamar_proxima(target.id, p_request_id);
end;
$$;

revoke all on function public.pista_ops_chamada_automatica_status(uuid) from public, anon;
revoke all on function public.pista_ops_configurar_chamada_automatica(uuid, boolean) from public, anon;
revoke all on function public.pista_ops_chamar_proxima_automatica(uuid, uuid) from public, anon;
grant execute on function public.pista_ops_chamada_automatica_status(uuid) to authenticated;
grant execute on function public.pista_ops_configurar_chamada_automatica(uuid, boolean) to authenticated;
grant execute on function public.pista_ops_chamar_proxima_automatica(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
