-- Morte súbita é uma regra opcional por operação. Desativada, a segunda
-- corrida é liberada após o resultado da primeira, seja Zero ou Valeu Boi.
begin;

alter table public.pista_ops_settings
  add column if not exists morte_subita boolean not null default false;

create or replace function public.pista_ops_guardar_segunda_corrida_na_fila()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
declare v_morte_subita boolean;
begin
  if new.tipo<>'regular' or new.corrida_id is null then return new; end if;
  select coalesce(s.morte_subita,false) into v_morte_subita
    from public.pista_ops_runs r
    left join public.pista_ops_settings s on s.evento_id=r.evento_id
    where r.id=new.corrida_id and r.numero_corrida=2;
  if not found then return new; end if;
  if not exists(
    select 1 from public.pista_ops_runs second_run
    join public.pista_ops_runs first_run on first_run.dupla_id=second_run.dupla_id and first_run.numero_corrida=1
    where second_run.id=new.corrida_id and (
      (v_morte_subita and first_run.estado='valeu_boi')
      or (not v_morte_subita and first_run.estado in ('zero','valeu_boi'))
    )
  ) then return null; end if;
  return new;
end $$;

create or replace function public.pista_ops_atualizar_direito_segunda_corrida()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare
  second_run public.pista_ops_runs%rowtype;
  active_round_id uuid;
  v_morte_subita boolean;
begin
  if new.numero_corrida<>1 or new.estado not in ('zero','valeu_boi') or new.estado=old.estado then return new; end if;
  select coalesce(s.morte_subita,false) into v_morte_subita
    from public.pista_ops_settings s where s.evento_id=new.evento_id;
  v_morte_subita:=coalesce(v_morte_subita,false);

  select * into second_run from public.pista_ops_runs r
   where r.dupla_id=new.dupla_id and r.numero_corrida=2 for update;
  if not found then return new; end if;

  if new.estado='zero' and v_morte_subita then
    if old.estado='valeu_boi' and second_run.estado in ('em_curso','zero','valeu_boi') then
      raise exception using errcode='P0001',message='PISTA_SECOND_RUN_ALREADY_USED';
    end if;
    if second_run.estado='pendente' then
      update public.pista_ops_runs set estado='sem_direito',pontuacao=null,atualizado_em=now() where id=second_run.id;
      update public.pista_ops_queue_items set estado='encaminhada'
       where corrida_id=second_run.id and estado in ('na_fila','retorno_pendente','aguardando_proximo');
    end if;
    return new;
  end if;

  if second_run.estado='sem_direito' then
    update public.pista_ops_runs set estado='pendente',pontuacao=null,atualizado_em=now() where id=second_run.id;
  end if;

  -- Retorno da primeira corrida mantém a segunda pendente para o rodízio seguinte.
  if new.retornos_realizados>0 then return new; end if;

  select r.id into active_round_id from public.pista_ops_rounds r
   where r.evento_id=new.evento_id and r.categoria_id=new.categoria_id and r.estado='ativo'
   order by r.numero desc limit 1;
  if active_round_id is not null and second_run.estado in ('pendente','sem_direito') then
    update public.pista_ops_runs set rodada_atual_id=active_round_id,atualizado_em=now() where id=second_run.id;
    update public.pista_ops_queue_items set estado='na_fila'
      where rodada_id=active_round_id and corrida_id=second_run.id and estado in ('encaminhada','aguardando_proximo');
    if not found then
      insert into public.pista_ops_queue_items(rodada_id,dupla_id,corrida_id,tipo,estado,eh_retorno,competidor_real_id)
       values(active_round_id,second_run.dupla_id,second_run.id,'regular','na_fila',false,second_run.competidor_real_id)
       on conflict(rodada_id,corrida_id) where tipo='regular' do nothing;
    end if;
  end if;
  return new;
end $$;

create or replace function public.pista_ops_morte_subita_status(p_evento_id uuid)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_result boolean;
begin
  perform public.pista_ops_check_access(p_evento_id,array['organizador','escritorio','locutor']);
  select coalesce(s.morte_subita,false) into v_result from public.pista_ops_settings s where s.evento_id=p_evento_id;
  return coalesce(v_result,false);
end $$;

create or replace function public.pista_ops_configurar_morte_subita(p_evento_id uuid,p_ativada boolean)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_actor uuid; v_categoria uuid; v_round uuid;
begin
  v_actor:=public.pista_ops_check_access(p_evento_id,array['organizador','locutor']);
  if p_ativada is null then raise exception using errcode='22023',message='PISTA_SUDDEN_DEATH_VALUE_REQUIRED'; end if;
  insert into public.pista_ops_settings(evento_id,atualizado_por,morte_subita)
   values(p_evento_id,v_actor,p_ativada)
   on conflict(evento_id) do update set morte_subita=excluded.morte_subita,atualizado_em=now(),atualizado_por=excluded.atualizado_por;

  if p_ativada then
    update public.pista_ops_runs second_run set estado='sem_direito',pontuacao=null,atualizado_em=now()
      from public.pista_ops_runs first_run
     where second_run.evento_id=p_evento_id and second_run.numero_corrida=2 and second_run.estado='pendente'
       and first_run.dupla_id=second_run.dupla_id and first_run.numero_corrida=1 and first_run.estado='zero';
    update public.pista_ops_queue_items q set estado='encaminhada'
      from public.pista_ops_runs second_run
     where q.corrida_id=second_run.id and second_run.evento_id=p_evento_id and second_run.numero_corrida=2
       and second_run.estado='sem_direito' and q.estado in ('na_fila','retorno_pendente','aguardando_proximo');
  else
    update public.pista_ops_runs second_run set estado='pendente',pontuacao=null,atualizado_em=now()
      from public.pista_ops_runs first_run
     where second_run.evento_id=p_evento_id and second_run.numero_corrida=2 and second_run.estado='sem_direito'
       and first_run.dupla_id=second_run.dupla_id and first_run.numero_corrida=1 and first_run.estado='zero';

    for v_categoria,v_round in
      select distinct first_run.categoria_id,r.id
        from public.pista_ops_runs first_run
        join public.pista_ops_runs second_run on second_run.dupla_id=first_run.dupla_id and second_run.numero_corrida=2 and second_run.estado='pendente'
        join public.pista_ops_rounds r on r.evento_id=first_run.evento_id and r.categoria_id=first_run.categoria_id and r.estado='ativo'
       where first_run.evento_id=p_evento_id and first_run.numero_corrida=1 and first_run.estado in ('zero','valeu_boi')
         and first_run.retornos_realizados=0
    loop
      insert into public.pista_ops_queue_items(rodada_id,dupla_id,corrida_id,tipo,estado,eh_retorno,competidor_real_id)
       select v_round,second_run.dupla_id,second_run.id,'regular','na_fila',false,second_run.competidor_real_id
         from public.pista_ops_runs second_run
         join public.pista_ops_runs first_run on first_run.dupla_id=second_run.dupla_id and first_run.numero_corrida=1
        where second_run.evento_id=p_evento_id and second_run.categoria_id=v_categoria and second_run.numero_corrida=2
          and second_run.estado='pendente' and first_run.estado in ('zero','valeu_boi') and first_run.retornos_realizados=0
       on conflict(rodada_id,corrida_id) where tipo='regular' do update set estado='na_fila';
      update public.pista_ops_runs second_run set rodada_atual_id=v_round,atualizado_em=now()
       from public.pista_ops_runs first_run
       where second_run.dupla_id=first_run.dupla_id and second_run.evento_id=p_evento_id
         and second_run.categoria_id=v_categoria and second_run.numero_corrida=2 and second_run.estado='pendente'
         and first_run.numero_corrida=1 and first_run.estado in ('zero','valeu_boi') and first_run.retornos_realizados=0;
    end loop;
  end if;
  return p_ativada;
end $$;

-- O padrão novo é desativado; regulariza apenas corridas ainda não realizadas
-- em operações ativas. Resultados de operações concluídas permanecem intactos.
update public.pista_ops_runs second_run set estado='pendente',pontuacao=null,atualizado_em=now()
  from public.pista_ops_runs first_run join public.eventos e on e.id=first_run.evento_id
 where second_run.dupla_id=first_run.dupla_id and second_run.numero_corrida=2 and first_run.numero_corrida=1
   and first_run.estado='zero' and second_run.estado='sem_direito' and e.status_operacional='em_andamento'
   and not coalesce((select s.morte_subita from public.pista_ops_settings s where s.evento_id=e.id),false);

update public.pista_ops_queue_items q set estado='na_fila'
  from public.pista_ops_runs second_run
  join public.pista_ops_runs first_run on first_run.dupla_id=second_run.dupla_id and first_run.numero_corrida=1
  join public.pista_ops_rounds r on r.estado='ativo'
 where q.corrida_id=second_run.id and second_run.numero_corrida=2 and second_run.estado='pendente'
   and first_run.estado in ('zero','valeu_boi') and first_run.retornos_realizados=0
   and q.estado='encaminhada' and r.id=q.rodada_id and r.evento_id=second_run.evento_id and r.categoria_id=second_run.categoria_id;

insert into public.pista_ops_queue_items(rodada_id,dupla_id,corrida_id,tipo,estado,eh_retorno,competidor_real_id)
 select r.id,second_run.dupla_id,second_run.id,'regular','na_fila',false,second_run.competidor_real_id
   from public.pista_ops_runs second_run
   join public.pista_ops_runs first_run on first_run.dupla_id=second_run.dupla_id and first_run.numero_corrida=1
   join public.pista_ops_rounds r on r.evento_id=second_run.evento_id and r.categoria_id=second_run.categoria_id and r.estado='ativo'
   join public.eventos e on e.id=second_run.evento_id and e.status_operacional='em_andamento'
  where second_run.numero_corrida=2 and second_run.estado='pendente' and first_run.estado in ('zero','valeu_boi')
    and first_run.retornos_realizados=0
 on conflict(rodada_id,corrida_id) where tipo='regular' do nothing;

update public.pista_ops_runs second_run set rodada_atual_id=r.id,atualizado_em=now()
  from public.pista_ops_runs first_run
  join public.pista_ops_rounds r on r.evento_id=first_run.evento_id and r.categoria_id=first_run.categoria_id and r.estado='ativo'
  join public.eventos e on e.id=first_run.evento_id and e.status_operacional='em_andamento'
 where second_run.dupla_id=first_run.dupla_id and second_run.numero_corrida=2 and second_run.estado='pendente'
   and first_run.numero_corrida=1 and first_run.estado in ('zero','valeu_boi') and first_run.retornos_realizados=0;

grant execute on function public.pista_ops_morte_subita_status(uuid),public.pista_ops_configurar_morte_subita(uuid,boolean) to authenticated;
revoke all on function public.pista_ops_morte_subita_status(uuid),public.pista_ops_configurar_morte_subita(uuid,boolean) from public,anon;
revoke all on function public.pista_ops_guardar_segunda_corrida_na_fila(),public.pista_ops_atualizar_direito_segunda_corrida() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
