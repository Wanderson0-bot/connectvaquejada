begin;

-- Only an active BOI TV device session is listed in the provider central.
create or replace function public.pista_ops_boi_tv_meus_eventos()
returns table(evento_id uuid,nome text,atendimentos_pendentes bigint,eh_operador boolean)
language sql stable security definer
set search_path=pg_catalog,public,auth,pg_temp as $$
  select e.id,e.nome,count(a.id) filter (where a.estado_atendimento<>'finalizada'),true
    from public.pista_ops_devices d
    join public.eventos e on e.id=d.evento_id and e.status_operacional='em_andamento'
    join public.pista_ops_settings s on s.evento_id=e.id and s.boi_tv
    left join public.pista_ops_boi_tv_atendimentos a on a.evento_id=e.id
   where d.usuario_auth_id=auth.uid() and d.funcao='boi_tv' and d.estado='ativo'
     and exists(select 1 from public.pista_ops_members m where m.evento_id=e.id
       and m.usuario_id=d.concedido_por and m.ativo and m.funcao='organizador')
   group by e.id,e.nome order by e.nome,e.id;
$$;

notify pgrst, 'reload schema';
commit;
