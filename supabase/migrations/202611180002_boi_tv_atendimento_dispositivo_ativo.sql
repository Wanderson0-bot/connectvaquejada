begin;

create or replace function public.pista_ops_boi_tv_pode_ver_evento(p_evento_id uuid)
returns boolean language sql stable security definer
set search_path=pg_catalog,public,auth,pg_temp as $$
  select exists (
    select 1 from public.pista_ops_devices d
     join public.pista_ops_settings s on s.evento_id=d.evento_id and s.boi_tv
     join public.eventos e on e.id=d.evento_id and e.status_operacional='em_andamento'
     where d.evento_id=p_evento_id and d.usuario_auth_id=auth.uid()
       and d.funcao='boi_tv' and d.estado='ativo'
       and exists(select 1 from public.pista_ops_members m where m.evento_id=d.evento_id
         and m.usuario_id=d.concedido_por and m.funcao='organizador' and m.ativo)
  ) or exists (
    select 1 from public.pista_ops_members m
    join public.eventos e on e.id=m.evento_id
    join public.pista_ops_settings s on s.evento_id=e.id and s.boi_tv
    join public.perfis p on p.id=auth.uid() and p.parque_id=e.parque_id
     where m.evento_id=p_evento_id and m.usuario_id=auth.uid() and m.ativo
       and m.funcao in ('organizador','escritorio','locutor')
  );
$$;

create or replace function public.pista_ops_boi_tv_atendimento_estado(p_evento_id uuid)
returns setof public.pista_ops_boi_tv_atendimentos language plpgsql stable security definer
set search_path = pg_catalog, public, auth, pg_temp as $$
begin
  if not public.pista_ops_boi_tv_pode_ver_evento(p_evento_id) then
    raise exception using errcode='42501',message='PISTA_TV_EVENT_ACCESS_REQUIRED';
  end if;
  return query select a.* from public.pista_ops_boi_tv_atendimentos a
   where a.evento_id=p_evento_id order by a.criada_em desc;
end;
$$;

drop function if exists public.pista_ops_boi_tv_atendimento_atualizar(uuid,text);

create or replace function public.pista_ops_boi_tv_atendimento_atualizar(
  p_atendimento_id uuid, p_estado text, p_observacao text default null
) returns uuid language plpgsql security definer
set search_path = pg_catalog, public, auth, pg_temp as $$
declare v_row public.pista_ops_boi_tv_atendimentos%rowtype; v_actor uuid; v_valid boolean;
begin
  select * into v_row from public.pista_ops_boi_tv_atendimentos where id=p_atendimento_id for update;
  if not found then raise exception using errcode='P0001',message='PISTA_TV_SERVICE_NOT_FOUND'; end if;
  select d.concedido_por into v_actor from public.pista_ops_devices d
    join public.eventos e on e.id=d.evento_id and e.status_operacional='em_andamento'
    join public.pista_ops_settings s on s.evento_id=d.evento_id and s.boi_tv
   where d.evento_id=v_row.evento_id and d.usuario_auth_id=auth.uid()
     and d.funcao='boi_tv' and d.estado='ativo'
     and exists(select 1 from public.pista_ops_members m where m.evento_id=d.evento_id
       and m.usuario_id=d.concedido_por and m.ativo and m.funcao='organizador');
  if v_actor is null then raise exception using errcode='42501',message='PISTA_TV_DEVICE_REQUIRED'; end if;
  v_valid := (v_row.estado_atendimento='nova' and p_estado='recebida')
    or (v_row.estado_atendimento='recebida' and p_estado='em_analise')
    or (v_row.estado_atendimento='em_analise' and p_estado='analise_concluida')
    or (v_row.estado_atendimento='analise_concluida' and p_estado='aguardando_decisao');
  if not coalesce(v_valid,false) then
    raise exception using errcode='P0001',message='PISTA_TV_SERVICE_TRANSITION_INVALID';
  end if;
  update public.pista_ops_boi_tv_atendimentos set
    estado_atendimento=p_estado,
    observacao_operacional=case when p_observacao is not null and p_estado in ('em_analise','analise_concluida')
      then left(btrim(p_observacao),2000) else observacao_operacional end,
    recebida_por=case when p_estado='recebida' then v_actor else recebida_por end,
    recebida_em=case when p_estado='recebida' then now() else recebida_em end,
    operador_id=case when p_estado in ('em_analise','analise_concluida','aguardando_decisao') then v_actor else operador_id end,
    analise_concluida_por=case when p_estado='analise_concluida' then v_actor else analise_concluida_por end,
    analise_concluida_em=case when p_estado='analise_concluida' then now() else analise_concluida_em end,
    atualizada_em=now()
  where id=p_atendimento_id;
  return p_atendimento_id;
end;
$$;

revoke all on function public.pista_ops_boi_tv_pode_ver_evento(uuid), public.pista_ops_boi_tv_atendimento_estado(uuid), public.pista_ops_boi_tv_atendimento_atualizar(uuid,text,text) from public, anon;

grant execute on function public.pista_ops_boi_tv_pode_ver_evento(uuid), public.pista_ops_boi_tv_atendimento_estado(uuid), public.pista_ops_boi_tv_atendimento_atualizar(uuid,text,text) to authenticated;

notify pgrst, 'reload schema';

commit;
