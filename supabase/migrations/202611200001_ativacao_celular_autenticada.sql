begin;

alter table public.pista_ops_devices
  add column operador_conta_id uuid references auth.users(id) on delete cascade,
  add column ultimo_acesso_em timestamptz;

create index pista_ops_devices_operador_idx
  on public.pista_ops_devices(operador_conta_id, evento_id) where operador_conta_id is not null;

create table public.pista_ops_mobile_attempts (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  janela timestamptz not null,
  tentativas integer not null
);
alter table public.pista_ops_mobile_attempts enable row level security;
revoke all on public.pista_ops_mobile_attempts from public, anon, authenticated;

create function public.pista_ops_mobile_conta_autorizada(p_conta uuid, p_evento uuid, p_funcao text)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth, pg_temp as $$
  select exists (
    select 1 from public.pista_ops_members m
    join public.perfis p on p.id=m.usuario_id
    join public.eventos e on e.id=m.evento_id
    where m.usuario_id=p_conta and m.evento_id=p_evento and m.ativo
      and (e.operacao_temporaria or p.parque_id=e.parque_id)
      and (m.funcao='organizador' or (p_funcao<>'boi_tv' and m.funcao=p_funcao))
  );
$$;

create function public.pista_ops_mobile_code_create(
  p_evento_id uuid, p_funcao text, p_substitui_id uuid default null, p_minutos integer default 10
) returns table(codigo text, expira_em timestamptz)
language plpgsql security definer set search_path = pg_catalog, public, auth, pg_temp as $$
declare
  v_actor uuid := auth.uid();
  v_codigo text;
  v_expira timestamptz;
begin
  if v_actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
    or not exists (
      select 1 from public.eventos e join public.pista_ops_members m on m.evento_id=e.id
       where e.id=p_evento_id and e.status_operacional='em_andamento'
         and m.usuario_id=v_actor and m.ativo and m.funcao='organizador'
         and ((p_funcao in ('escritorio','locutor') and e.operacao_temporaria)
           or (p_funcao='boi_tv' and exists (
             select 1 from public.pista_ops_settings s where s.evento_id=e.id and s.boi_tv
           )))
    ) then
    raise exception 'DEVICE_ADMIN_REQUIRED' using errcode='42501';
  end if;
  if p_minutos is null or p_minutos not between 1 and 60 then
    raise exception 'DEVICE_EXPIRATION_INVALID' using errcode='22023';
  end if;
  if p_substitui_id is not null and not exists (
    select 1 from public.pista_ops_devices d where d.id=p_substitui_id
     and d.evento_id=p_evento_id and d.funcao=p_funcao and d.estado in ('ativo','bloqueado')
  ) then
    raise exception 'DEVICE_REPLACE_TARGET_INVALID' using errcode='22023';
  end if;
  v_codigo := upper(replace(gen_random_uuid()::text,'-',''));
  v_expira := now()+make_interval(mins => p_minutos);
  insert into public.pista_ops_device_codes(evento_id,funcao,codigo,criado_por,substitui_dispositivo_id,expira_em)
  values (p_evento_id,p_funcao,'sha256:'||encode(sha256(convert_to(v_codigo,'UTF8')),'hex'),
    v_actor,p_substitui_id,v_expira);
  return query select v_codigo,v_expira;
end;
$$;

create function public.pista_ops_mobile_activate(p_codigo text, p_sessao uuid, p_nome text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, auth, pg_temp as $$
declare
  v_actor uuid := auth.uid();
  v_solicitacao public.pista_ops_device_codes%rowtype;
  v_dispositivo uuid;
  v_tentativas integer;
begin
  if v_actor is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
    return jsonb_build_object('erro','conta');
  end if;
  -- Este retorno normal preserva o contador mesmo em tentativas recusadas.
  insert into public.pista_ops_mobile_attempts as a(usuario_id,janela,tentativas)
  values (v_actor,now(),1) on conflict (usuario_id) do update set
    tentativas=case when a.janela<=now()-interval '10 minutes' then 1 else least(a.tentativas+1,11) end,
    janela=case when a.janela<=now()-interval '10 minutes' then now() else a.janela end
  returning tentativas into v_tentativas;
  if v_tentativas>10 then return jsonb_build_object('erro','limite'); end if;
  if p_codigo is null or p_codigo !~ '^[0-9A-Fa-f]{32}$'
    or length(btrim(coalesce(p_nome,''))) not between 1 and 80 then
    return jsonb_build_object('erro','codigo');
  end if;
  -- A sessão de dispositivo tem identidade própria e nunca recebe o JWT da conta.
  perform 1 from auth.users u where u.id=p_sessao and u.is_anonymous for update;
  if not found or exists(select 1 from public.pista_ops_devices where usuario_auth_id=p_sessao) then
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
   where m.evento_id=v_solicitacao.evento_id and m.usuario_id in (v_actor,v_solicitacao.criado_por)
   order by m.id for share;
  perform 1 from public.perfis p where p.id=v_actor for share;
  if not public.pista_ops_mobile_conta_autorizada(v_actor,v_solicitacao.evento_id,v_solicitacao.funcao)
    or not exists(select 1 from public.pista_ops_members m where m.evento_id=v_solicitacao.evento_id
      and m.usuario_id=v_solicitacao.criado_por and m.ativo and m.funcao='organizador') then
    return jsonb_build_object('erro','permissao');
  end if;
  update public.pista_ops_devices set estado='revogado',revogado_em=now(),
    atualizado_em=now(),revogado_por=v_solicitacao.criado_por
    where id=v_solicitacao.substitui_dispositivo_id and estado in ('ativo','bloqueado');
  insert into public.pista_ops_devices(
    evento_id,usuario_auth_id,identificador_navegador,funcao,concedido_por,nome,operador_conta_id,ultimo_acesso_em
  ) values (v_solicitacao.evento_id,p_sessao,gen_random_uuid(),v_solicitacao.funcao,
    v_solicitacao.criado_por,btrim(p_nome),v_actor,now()) returning id into v_dispositivo;
  update public.pista_ops_device_codes set usado_em=now() where id=v_solicitacao.id;
  return jsonb_build_object('id',v_dispositivo,'evento_id',v_solicitacao.evento_id,'funcao',v_solicitacao.funcao);
end;
$$;

create function public.pista_ops_mobile_validar_estado()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
begin
  if tg_op='UPDATE' and old.operador_conta_id is not null and old.estado='revogado' and new.estado<>'revogado' then
    raise exception 'DEVICE_GRANT_REVOKED' using errcode='42501';
  end if;
  if new.operador_conta_id is not null and new.estado='ativo'
    and (not public.pista_ops_mobile_conta_autorizada(new.operador_conta_id,new.evento_id,new.funcao)
      or not exists(select 1 from public.pista_ops_members m where m.evento_id=new.evento_id
        and m.usuario_id=new.concedido_por and m.funcao='organizador' and m.ativo)) then
    raise exception 'DEVICE_GRANT_REVOKED' using errcode='42501';
  end if;
  return new;
end;
$$;

create trigger pista_ops_mobile_validar_estado before insert or update of estado on public.pista_ops_devices
for each row execute function public.pista_ops_mobile_validar_estado();

create function public.pista_ops_mobile_revogar_sem_acesso()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
begin
  if tg_table_name='pista_ops_members' then
    update public.pista_ops_devices d set estado='revogado',revogado_em=now(),atualizado_em=now()
     where d.operador_conta_id is not null and d.evento_id=old.evento_id
       and old.usuario_id in (d.operador_conta_id,d.concedido_por) and d.estado in ('ativo','bloqueado')
       and (not public.pista_ops_mobile_conta_autorizada(d.operador_conta_id,d.evento_id,d.funcao)
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

create trigger pista_ops_mobile_membro_revogado after update or delete on public.pista_ops_members
for each row execute function public.pista_ops_mobile_revogar_sem_acesso();
create trigger pista_ops_mobile_perfil_revogado after update of parque_id or delete on public.perfis
for each row execute function public.pista_ops_mobile_revogar_sem_acesso();

create function public.pista_ops_mobile_touch(p_evento_id uuid, p_funcao text)
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_id uuid;
begin
  select d.id into v_id from public.pista_ops_devices d
   join public.eventos e on e.id=d.evento_id and e.status_operacional='em_andamento'
   where d.usuario_auth_id=auth.uid() and d.evento_id=p_evento_id and d.funcao=p_funcao and d.estado='ativo'
     and d.operador_conta_id is not null
     and public.pista_ops_mobile_conta_autorizada(d.operador_conta_id,d.evento_id,d.funcao)
     and exists(select 1 from public.pista_ops_members m where m.evento_id=d.evento_id
       and m.usuario_id=d.concedido_por and m.ativo and m.funcao='organizador')
     and (d.funcao<>'boi_tv' or exists(select 1 from public.pista_ops_settings s where s.evento_id=e.id and s.boi_tv));
  if v_id is null then return false; end if;
  update public.pista_ops_devices set ultimo_acesso_em=now()
   where id=v_id and estado='ativo' and ultimo_acesso_em<now()-interval '1 minute';
  return true;
end;
$$;

create function public.pista_ops_mobile_acessos(p_evento_id uuid)
returns table(id uuid, ultimo_acesso_em timestamptz, operador_conta_id uuid)
language sql stable security definer set search_path=pg_catalog,public,auth,pg_temp as $$
  select d.id,d.ultimo_acesso_em,d.operador_conta_id from public.pista_ops_devices d
   where d.evento_id=p_evento_id and exists (
     select 1 from public.pista_ops_members m where m.evento_id=d.evento_id
       and m.usuario_id=auth.uid() and m.ativo and m.funcao='organizador'
   );
$$;

create function public.pista_ops_mobile_sair()
returns boolean language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
begin
  update public.pista_ops_devices set estado='revogado',revogado_em=now(),atualizado_em=now()
    where usuario_auth_id=auth.uid() and operador_conta_id is not null and estado in ('ativo','bloqueado');
  return found;
end;
$$;

revoke all on function public.pista_ops_mobile_conta_autorizada(uuid,uuid,text),
  public.pista_ops_mobile_code_create(uuid,text,uuid,integer), public.pista_ops_mobile_activate(text,uuid,text),
  public.pista_ops_mobile_validar_estado(),public.pista_ops_mobile_revogar_sem_acesso(),
  public.pista_ops_mobile_touch(uuid,text),public.pista_ops_mobile_acessos(uuid),
  public.pista_ops_mobile_sair() from public, anon, authenticated;
grant execute on function public.pista_ops_mobile_code_create(uuid,text,uuid,integer),
  public.pista_ops_mobile_activate(text,uuid,text),public.pista_ops_mobile_touch(uuid,text),
  public.pista_ops_mobile_acessos(uuid),public.pista_ops_mobile_sair() to authenticated;

notify pgrst, 'reload schema';
commit;
