\set ON_ERROR_STOP on
begin;

do $teste$
declare
  organizador uuid := gen_random_uuid();
  operador uuid := gen_random_uuid();
  sem_acesso uuid := gen_random_uuid();
  sessao uuid := gen_random_uuid();
  outra_sessao uuid := gen_random_uuid();
  sessao_reuso uuid := gen_random_uuid();
  parque uuid := gen_random_uuid();
  evento uuid := gen_random_uuid();
  outro_evento uuid := gen_random_uuid();
  convite text;
  expirado text;
  resposta jsonb;
  dispositivo uuid;
  convite_celular text;
  celular uuid;
begin
  insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,is_anonymous)
  values
    (organizador,'authenticated','authenticated',organizador||'@example.invalid','{}','{}',false),
    (operador,'authenticated','authenticated',operador||'@example.invalid','{}','{}',false),
    (sem_acesso,'authenticated','authenticated',sem_acesso||'@example.invalid','{}','{}',false),
    (sessao,'authenticated','authenticated',null,'{}','{}',true),
    (outra_sessao,'authenticated','authenticated',null,'{}','{}',true),
    (sessao_reuso,'authenticated','authenticated',null,'{}','{}',true);
  insert into public.parques(id,nome) values(parque,'Parque de teste');
  insert into public.perfis(id,parque_id,nome) values
    (organizador,parque,'Organizador'),(operador,parque,'Operador'),(sem_acesso,parque,'Sem acesso');
  insert into public.eventos(id,nome,data,operacao_temporaria,status_operacional)
  values(evento,'Evento de teste',current_date,true,'em_andamento'),
        (outro_evento,'Outro evento de teste',current_date,true,'em_andamento');
  insert into public.pista_ops_members(evento_id,usuario_id,funcao,ativo,criado_por)
  values(evento,organizador,'organizador',true,organizador),
        (evento,operador,'escritorio',true,organizador);

  perform set_config('request.jwt.claims',json_build_object('sub',organizador)::text,true);
  select c.codigo into convite from public.pista_ops_mobile_code_create(evento,'escritorio') c;
  select c.codigo into expirado from public.pista_ops_mobile_code_create(evento,'escritorio') c;
  update public.pista_ops_device_codes set expira_em=now()-interval '1 second'
   where codigo='sha256:'||encode(sha256(convert_to(expirado,'UTF8')),'hex');
  if not exists (select 1 from public.pista_ops_device_codes where codigo='sha256:'||encode(sha256(convert_to(convite,'UTF8')),'hex'))
    or exists(select 1 from public.pista_ops_device_codes where codigo=convite) then
    raise exception 'O convite deve ser armazenado somente como hash';
  end if;

  perform set_config('request.jwt.claims',json_build_object('sub',sessao,'is_anonymous',true)::text,true);
  if (public.pista_ops_mobile_activate(convite,sessao,'Celular')->>'erro') is distinct from 'conta' then
    raise exception 'Sessão anônima não pode resgatar convite';
  end if;

  perform set_config('request.jwt.claims',json_build_object('sub',sem_acesso)::text,true);
  if (public.pista_ops_mobile_activate(convite,sessao,'Celular')->>'erro') is distinct from 'permissao' then
    raise exception 'Conta sem função resgatou convite';
  end if;
  for i in 1..10 loop
    resposta := public.pista_ops_mobile_activate(convite,sessao,'Celular');
  end loop;
  if (resposta->>'erro') is distinct from 'limite' then raise exception 'Limite não aplicado'; end if;

  perform set_config('request.jwt.claims',json_build_object('sub',operador)::text,true);
  if (public.pista_ops_mobile_activate(expirado,sessao,'Celular')->>'erro') is distinct from 'codigo' then
    raise exception 'Convite vencido aceito';
  end if;
  resposta := public.pista_ops_mobile_activate(convite,sessao,'Celular');
  dispositivo := (resposta->>'id')::uuid;
  if dispositivo is null then raise exception 'Ativação válida recusada: %',resposta; end if;
  if (public.pista_ops_mobile_activate(convite,outra_sessao,'Outro celular')->>'erro') is distinct from 'codigo' then
    raise exception 'Convite reutilizado';
  end if;

  perform set_config('request.jwt.claims',json_build_object('sub',sessao,'is_anonymous',true)::text,true);
  if not public.pista_ops_mobile_touch(evento,'escritorio')
    or public.pista_ops_mobile_touch(outro_evento,'escritorio')
    or public.pista_ops_mobile_touch(evento,'locutor') then
    raise exception 'Escopo do aparelho inválido';
  end if;
  if public.pista_ops_check_access(evento,array['escritorio']) is distinct from operador then
    raise exception 'Autoria do operador não registrada';
  end if;
  perform * from public.pista_ops_historico_operacional(evento,'escritorio');
  begin
    perform * from public.pista_ops_historico_operacional(outro_evento,'escritorio');
    raise exception 'Histórico acessível fora do evento';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.pista_ops_check_access(evento,array['organizador']);
    raise exception 'Aparelho recebeu permissão administrativa';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims',json_build_object('sub',organizador)::text,true);
  if not public.pista_ops_device_manage(dispositivo,'bloquear') then raise exception 'Bloqueio falhou'; end if;
  perform set_config('request.jwt.claims',json_build_object('sub',sessao,'is_anonymous',true)::text,true);
  if public.pista_ops_mobile_touch(evento,'escritorio') then raise exception 'Aparelho bloqueado ainda ativo'; end if;
  perform set_config('request.jwt.claims',json_build_object('sub',organizador)::text,true);
  if not public.pista_ops_device_manage(dispositivo,'reativar') then raise exception 'Reativação falhou'; end if;
  perform public.pista_ops_configurar_membro(evento,operador,'escritorio',false);
  if (select estado from public.pista_ops_devices where id=dispositivo) is distinct from 'revogado' then
    raise exception 'Revogação da função não encerrou o aparelho';
  end if;
  select c.codigo into convite_celular from public.pista_ops_mobile_code_create(evento,'locutor') c;
  if public.pista_ops_mobile_redeem(convite_celular,null)->>'erro' is distinct from 'sessao' then
    raise exception 'O resgate deve usar a sessão do próprio aparelho';
  end if;
  perform set_config('request.jwt.claims',json_build_object('sub',outra_sessao,'is_anonymous',true)::text,true);
  resposta := public.pista_ops_mobile_redeem(convite_celular,null);
  celular := (resposta->>'id')::uuid;
  if celular is null or not exists (
    select 1 from public.pista_ops_devices where id=celular and usuario_auth_id=outra_sessao
      and nome='Celular de operação' and operador_conta_id is null and ativado_por_codigo
  ) then raise exception 'Vínculo por código não foi salvo com o nome padrão'; end if;
  if not public.pista_ops_mobile_touch(evento,'locutor')
    or public.pista_ops_mobile_touch(evento,'escritorio')
    or public.pista_ops_mobile_touch(outro_evento,'locutor') then
    raise exception 'Escopo inválido para aparelho vinculado por código';
  end if;
  if not public.pista_ops_mobile_sair() or public.pista_ops_mobile_touch(evento,'locutor') then
    raise exception 'Sessão vinculada por código continuou ativa após sair';
  end if;
  perform set_config('request.jwt.claims',json_build_object('sub',sessao_reuso,'is_anonymous',true)::text,true);
  if public.pista_ops_mobile_redeem(convite_celular,'Outro celular')->>'erro' is distinct from 'codigo' then
    raise exception 'Código usado foi aceito novamente';
  end if;
  raise notice 'Ativação, escopo, bloqueio e revogação verificados.';
end;
$teste$;

rollback;
