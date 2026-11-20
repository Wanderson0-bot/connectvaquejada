\set ON_ERROR_STOP on
\set evento_id 'PREENCHER_UUID_DO_EVENTO'
\set user_id 'PREENCHER_UUID_DO_PERFIL'

begin;

select set_config('pista_ops.bootstrap.evento_id', :'evento_id', true);
select set_config('pista_ops.bootstrap.user_id', :'user_id', true);

do $pista_ops_bootstrap$
declare
  evento_id_text text := current_setting('pista_ops.bootstrap.evento_id', true);
  user_id_text text := current_setting('pista_ops.bootstrap.user_id', true);
  target_evento_id uuid;
  target_user_id uuid;
  evento_parque_id uuid;
  perfil_parque_id uuid;
begin
  if to_regclass('public.pista_ops_members') is null
    or to_regclass('public.pista_ops_first_organizer_audit') is null then
    raise exception 'Pista Ops ainda não está instalada: aplique e revise a migration antes do bootstrap.';
  end if;

  if evento_id_text is null or evento_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'Preencha a variável psql evento_id com um UUID válido antes de executar.';
  end if;
  if user_id_text is null or user_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'Preencha a variável psql user_id com o UUID de um perfil existente.';
  end if;

  target_evento_id := evento_id_text::uuid;
  target_user_id := user_id_text::uuid;

  select e.parque_id into evento_parque_id
    from public.eventos e
   where e.id = target_evento_id
   for update;
  if not found then
    raise exception 'Evento % não existe.', target_evento_id;
  end if;

  select p.parque_id into perfil_parque_id
    from public.perfis p
   where p.id = target_user_id
   for share;
  if not found then
    raise exception 'O usuário % não possui perfil.', target_user_id;
  end if;

  if perfil_parque_id is null or perfil_parque_id is distinct from evento_parque_id then
    raise exception 'O perfil % e o evento % não pertencem ao mesmo parque.',
      target_user_id, target_evento_id;
  end if;

  if exists (
    select 1
      from public.pista_ops_members m
     where m.evento_id = target_evento_id
       and m.funcao = 'organizador'
       and m.ativo
  ) or exists (
    select 1
      from public.pista_ops_first_organizer_audit a
     where a.evento_id = target_evento_id
  ) then
    raise exception 'O evento % já possui organizador ativo ou bootstrap anterior; novo bootstrap recusado.', target_evento_id;
  end if;

  insert into public.pista_ops_first_organizer_audit(
    evento_id, usuario_id, executado_por
  ) values (
    target_evento_id, target_user_id, session_user
  );

  insert into public.pista_ops_members(
    evento_id, usuario_id, funcao, ativo, criado_por
  ) values (
    target_evento_id, target_user_id, 'organizador', true, target_user_id
  );
end;
$pista_ops_bootstrap$;

commit;
