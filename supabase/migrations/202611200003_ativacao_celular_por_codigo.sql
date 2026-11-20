begin;

alter table public.pista_ops_devices add column ativado_por_codigo boolean not null default false;

create function public.pista_ops_mobile_redeem(p_codigo text, p_nome text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, auth, pg_temp as $$
declare
  v_actor uuid := auth.uid();
  v_solicitacao public.pista_ops_device_codes%rowtype;
  v_dispositivo uuid;
  v_nome text := coalesce(nullif(btrim(p_nome),''),'Celular de operação');
begin
  if v_actor is null or not coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
    return jsonb_build_object('erro','sessao');
  end if;
  if p_codigo is null or p_codigo !~ '^[0-9A-Fa-f]{32}$'
    or length(v_nome)>80 then
    return jsonb_build_object('erro','codigo');
  end if;
  -- A sessão de dispositivo tem identidade própria e nunca recebe o JWT da conta.
  perform 1 from auth.users u where u.id=v_actor and u.is_anonymous for update;
  if not found or exists(select 1 from public.pista_ops_devices where usuario_auth_id=v_actor) then
    return jsonb_build_object('erro','sessao');
  end if;
  select c.* into v_solicitacao from public.pista_ops_device_codes c
   where c.codigo='sha256:'||encode(sha256(convert_to(upper(p_codigo),'UTF8')),'hex')
     and c.usado_em is null and c.expira_em>now() for update;
  if not found then return jsonb_build_object('erro','codigo'); end if;
  perform 1 from public.eventos e where e.id=v_solicitacao.evento_id and e.status_operacional='em_andamento'
    and ((e.operacao_temporaria and v_solicitacao.funcao in ('escritorio','locutor'))
      or (v_solicitacao.funcao='boi_tv' and exists (
        select 1 from public.pista_ops_settings s where s.evento_id=e.id and s.boi_tv
      ))) for share;
  if not found then return jsonb_build_object('erro','evento'); end if;
  perform 1 from public.pista_ops_members m
   where m.evento_id=v_solicitacao.evento_id and m.usuario_id=v_solicitacao.criado_por
     and m.ativo and m.funcao='organizador' for share;
  if not found then return jsonb_build_object('erro','permissao'); end if;
  update public.pista_ops_devices set estado='revogado',revogado_em=now(),
    atualizado_em=now(),revogado_por=v_solicitacao.criado_por
    where id=v_solicitacao.substitui_dispositivo_id and estado in ('ativo','bloqueado');
  insert into public.pista_ops_devices(
    evento_id,usuario_auth_id,identificador_navegador,funcao,concedido_por,nome,ativado_por_codigo,ultimo_acesso_em
  ) values (v_solicitacao.evento_id,v_actor,gen_random_uuid(),v_solicitacao.funcao,
    v_solicitacao.criado_por,v_nome,true,now()) returning id into v_dispositivo;
  update public.pista_ops_device_codes set usado_em=now() where id=v_solicitacao.id;
  return jsonb_build_object('id',v_dispositivo,'evento_id',v_solicitacao.evento_id,'funcao',v_solicitacao.funcao);
end;
$$;

create or replace function public.pista_ops_mobile_validar_estado()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
begin
  if tg_op='UPDATE' and (old.ativado_por_codigo or old.operador_conta_id is not null) and old.estado='revogado' and new.estado<>'revogado' then
    raise exception 'DEVICE_GRANT_REVOKED' using errcode='42501';
  end if;
  if (new.ativado_por_codigo or new.operador_conta_id is not null) and new.estado='ativo'
    and ((new.operador_conta_id is not null and not public.pista_ops_mobile_conta_autorizada(new.operador_conta_id,new.evento_id,new.funcao))
      or not exists(select 1 from public.pista_ops_members m where m.evento_id=new.evento_id
        and m.usuario_id=new.concedido_por and m.funcao='organizador' and m.ativo)) then
    raise exception 'DEVICE_GRANT_REVOKED' using errcode='42501';
  end if;
  return new;
end;
$$;

create or replace function public.pista_ops_mobile_revogar_sem_acesso()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
begin
  if tg_table_name='pista_ops_members' then
    update public.pista_ops_devices d set estado='revogado',revogado_em=now(),atualizado_em=now()
     where (d.ativado_por_codigo or d.operador_conta_id is not null) and d.evento_id=old.evento_id
       and old.usuario_id in (d.operador_conta_id,d.concedido_por) and d.estado in ('ativo','bloqueado')
       and ((d.operador_conta_id is not null and not public.pista_ops_mobile_conta_autorizada(d.operador_conta_id,d.evento_id,d.funcao))
         or not exists(select 1 from public.pista_ops_members m where m.evento_id=d.evento_id
           and m.usuario_id=d.concedido_por and m.ativo and m.funcao='organizador'));
  else
    update public.pista_ops_devices d set estado='revogado',revogado_em=now(),atualizado_em=now()
     where d.operador_conta_id=old.id and d.estado in ('ativo','bloqueado')
       and not public.pista_ops_mobile_conta_autorizada(d.operador_conta_id,d.evento_id,d.funcao);
  end if;
  return null;
end;
$$;

create or replace function public.pista_ops_mobile_touch(p_evento_id uuid, p_funcao text)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_id uuid;
begin
  select d.id into v_id from public.pista_ops_devices d
   join public.eventos e on e.id=d.evento_id and e.status_operacional='em_andamento'
   where d.usuario_auth_id=auth.uid() and d.evento_id=p_evento_id and d.funcao=p_funcao and d.estado='ativo'
     and (d.ativado_por_codigo or (d.operador_conta_id is not null
       and public.pista_ops_mobile_conta_autorizada(d.operador_conta_id,d.evento_id,d.funcao)))
     and exists(select 1 from public.pista_ops_members m where m.evento_id=d.evento_id
       and m.usuario_id=d.concedido_por and m.ativo and m.funcao='organizador')
     and (d.funcao<>'boi_tv' or exists(select 1 from public.pista_ops_settings s where s.evento_id=e.id and s.boi_tv));
  if v_id is null then return false; end if;
  update public.pista_ops_devices set ultimo_acesso_em=now()
   where id=v_id and estado='ativo' and ultimo_acesso_em<now()-interval '1 minute';
  return true;
end;
$$;

create or replace function public.pista_ops_mobile_sair()
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
begin
  update public.pista_ops_devices set estado='revogado',revogado_em=now(),atualizado_em=now()
    where usuario_auth_id=auth.uid() and (ativado_por_codigo or operador_conta_id is not null) and estado in ('ativo','bloqueado');
  return found;
end;
$$;

revoke all on function public.pista_ops_mobile_redeem(text,text) from public, anon, authenticated;
grant execute on function public.pista_ops_mobile_redeem(text,text) to authenticated;

notify pgrst, 'reload schema';

commit;
