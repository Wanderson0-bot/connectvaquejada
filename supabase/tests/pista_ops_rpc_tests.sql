\set ON_ERROR_STOP on

-- Execute against a test database with the application migrations applied.
-- auth.uid() reads the simulated identity from request.jwt.claims.
-- This fixture assumes public.status_pagamento accepts the text value 'cancelado'.
-- This script never applies the migration; all fixture and RPC writes are rolled back.

begin;

-- Schema assumptions: parques(id, nome), perfis(id, parque_id),
-- eventos(id, parque_id, nome), categorias(id, evento_id, nome, ordem),
-- competidores(id, parque_id, nome), and duplas(id, evento_id, categoria_id,
-- numero_senha, puxador_id, status_pagamento, created_at).
-- auth.uid() must derive the UUID from current_setting('request.jwt.claims', true)::jsonb->>'sub'.

do $pista_ops_fixture_check$
begin
  if to_regclass('public.parques') is null
    or to_regclass('public.perfis') is null
    or to_regclass('public.eventos') is null
    or to_regclass('public.categorias') is null
    or to_regclass('public.competidores') is null
    or to_regclass('public.duplas') is null then
    raise exception 'TEST_SETUP_MISSING_BASE_TABLE: create the documented simulated base schema first';
  end if;
  if to_regprocedure('auth.uid()') is null then
    raise exception 'TEST_SETUP_MISSING_AUTH_UID: create the documented local auth.uid() first';
  end if;
  if to_regclass('public.pista_ops_members') is null
    or to_regclass('public.pista_ops_first_organizer_audit') is null
    or to_regclass('public.pista_ops_settings') is null
    or to_regclass('public.pista_ops_rounds') is null
    or to_regclass('public.pista_ops_runs') is null
    or to_regclass('public.pista_ops_queue_items') is null
    or to_regclass('public.pista_ops_call_requests') is null
    or to_regclass('public.pista_ops_positions') is null then
    raise exception 'TEST_SETUP_MIGRATION_MISSING: apply the migration separately to the disposable test database';
  end if;
  if to_regclass('public.pista_ops_boi_tv_reviews') is null
    or to_regclass('public.pista_ops_boi_tv_atendimentos') is null
    or to_regclass('public.pista_ops_devices') is null
    or to_regclass('public.x1_revisoes') is null then
    raise exception 'TEST_SETUP_BOI_TV_MISSING: apply the BOI TV and X1 migrations separately to the disposable test database';
  end if;
  if not exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'eventos'
       and column_name = 'formato_competicao'
  ) then
    raise exception 'TEST_SETUP_TROPA_ELITE_MISSING: apply the Tropa de Elite format migration separately';
  end if;
end;
$pista_ops_fixture_check$;

insert into public.parques(id, nome) values
  ('10000000-0000-4000-8000-000000000001', 'Parque ficticio A'),
  ('10000000-0000-4000-8000-000000000002', 'Parque ficticio B');

insert into public.eventos(id, parque_id, nome, data, status_operacional) values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Evento ficticio de teste', current_date, 'em_andamento'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'Outro evento ficticio', current_date, 'em_andamento');

insert into public.categorias(id, evento_id, nome, ordem) values
  ('30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'Categoria teste A', 1),
  ('30000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', 'Categoria teste B', 2),
  ('30000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000002', 'Categoria de outro evento', 1);

insert into auth.users(id, aud, role, email, raw_app_meta_data, raw_user_meta_data, is_anonymous)
select ('40000000-0000-4000-8000-00000000000' || numero)::uuid,
  'authenticated', 'authenticated', 'pista-fixture-' || numero || '@example.invalid', '{}', '{}', false
from generate_series(1, 6) as usuario(numero);

insert into public.perfis(id, parque_id, nome) values
  ('40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Organizador ficticio'),
  ('40000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'Escritorio ficticio'),
  ('40000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', 'Locutor ficticio'),
  ('40000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000002', 'Usuario de outro parque'),
  ('40000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001', 'Usuario sem acesso ao evento');
-- 40000000-0000-4000-8000-000000000006 intentionally has no public.perfis row.

insert into public.competidores(id, parque_id, nome) values
  ('50000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Competidor ficticio A'),
  ('50000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'Competidor ficticio B'),
  ('50000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', 'Competidor ficticio cancelado');

insert into public.duplas(id, evento_id, categoria_id, numero_senha, puxador_id, status_pagamento, created_at) values
  ('60000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 1, '50000000-0000-4000-8000-000000000001', 'pago', '2026-01-01 10:00:00+00'),
  ('60000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 2, '50000000-0000-4000-8000-000000000002', 'pago', '2026-01-01 10:01:00+00'),
  ('60000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 3, '50000000-0000-4000-8000-000000000003', 'cancelado', '2026-01-01 10:02:00+00');

insert into public.pista_ops_members(evento_id, usuario_id, funcao, ativo, criado_por) values
  ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', 'organizador', true, '40000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000002', 'escritorio', true, '40000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000003', 'locutor', true, '40000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000005', 'locutor', true, '40000000-0000-4000-8000-000000000001');

create temporary table pista_ops_test_temp_namespace (initialized boolean) on commit drop;

create function pg_temp.pista_ops_test_snapshot()
returns jsonb
language sql
as $snapshot$
  select jsonb_build_array(
    (select count(*) from public.pista_ops_rounds),
    (select count(*) from public.pista_ops_runs),
    (select count(*) from public.pista_ops_queue_items),
    (select count(*) from public.pista_ops_call_requests),
    (select count(*) from public.pista_ops_positions),
    (select count(*) from public.pista_ops_result_corrections),
    (select count(*) from public.pista_ops_prize_versions),
    (select count(*) from public.pista_ops_ties)
  );
$snapshot$;

create function pg_temp.pista_ops_test_expect_denied(
  test_name text,
  actor_id uuid,
  expected_message text
)
returns void
language plpgsql
as $denial$
declare
  before_data jsonb;
  after_data jsonb;
  actual_message text;
  actual_state text;
  was_denied boolean := false;
begin
  before_data := pg_temp.pista_ops_test_snapshot();
  perform set_config('request.jwt.claims', json_build_object('sub', actor_id)::text, true);
  begin
    perform public.pista_ops_planejar_rodizio(
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      5
    );
  exception when insufficient_privilege then
    get stacked diagnostics actual_message = message_text, actual_state = returned_sqlstate;
    was_denied := true;
  end;
  if not was_denied then
    raise exception 'TEST_DENIAL_FAILED [%]: unauthorized RPC unexpectedly succeeded', test_name;
  end if;
  if actual_state <> '42501' or actual_message is distinct from expected_message then
    raise exception 'TEST_DENIAL_FAILED [%]: expected 42501/%; got %/%',
      test_name, expected_message, actual_state, actual_message;
  end if;
  after_data := pg_temp.pista_ops_test_snapshot();
  if after_data is distinct from before_data then
    raise exception 'TEST_DENIAL_MUTATED_DATA [%]: before %, after %', test_name, before_data, after_data;
  end if;
  raise notice 'DENY %: PASS (%, no data changes)', test_name, actual_message;
end;
$denial$;

do $pista_ops_rpc_tests$
declare
  test_event_id constant uuid := '20000000-0000-4000-8000-000000000001';
  test_category_id constant uuid := '30000000-0000-4000-8000-000000000001';
  organizer_id constant uuid := '40000000-0000-4000-8000-000000000001';
  office_id constant uuid := '40000000-0000-4000-8000-000000000002';
  announcer_id constant uuid := '40000000-0000-4000-8000-000000000003';
  round_id uuid;
  first_call jsonb;
  repeated_call jsonb;
  call_item_id uuid;
  second_call jsonb;
  fourth_call jsonb;
  rabo_call jsonb;
  next_state jsonb;
  snapshot_before jsonb;
  snapshot_after jsonb;
  expected_message text;
  actual_message text;
  actual_state text;
  was_denied boolean;
  consumed_before bigint;
  consumed_after bigint;
  regular_runs bigint;
begin
  -- All three event roles can read the authorized event state.
  perform set_config('request.jwt.claims', json_build_object('sub', organizer_id)::text, true);
  perform public.pista_ops_state(test_event_id, null);
  raise notice 'ACCESS organizer state: PASS';

  perform set_config('request.jwt.claims', json_build_object('sub', office_id)::text, true);
  perform public.pista_ops_state(test_event_id, null);
  raise notice 'ACCESS office state: PASS';

  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  perform public.pista_ops_state(test_event_id, null);
  raise notice 'ACCESS announcer state: PASS';

  -- Negative authorization checks use a mutating RPC and compare all Pista row counts.
  perform pg_temp.pista_ops_test_expect_denied(
    'user without profile',
    '40000000-0000-4000-8000-000000000006',
    'PISTA_EVENT_PARK_MISMATCH'
  );
  perform pg_temp.pista_ops_test_expect_denied(
    'profile from another park',
    '40000000-0000-4000-8000-000000000004',
    'PISTA_EVENT_PARK_MISMATCH'
  );
  perform pg_temp.pista_ops_test_expect_denied(
    'member of another event only',
    '40000000-0000-4000-8000-000000000005',
    'PISTA_EVENT_ROLE_REQUIRED'
  );

  -- Office may plan; locutor may start. The repeated start must fail explicitly and not duplicate rows.
  perform set_config('request.jwt.claims', json_build_object('sub', office_id)::text, true);
  round_id := public.pista_ops_planejar_rodizio(test_event_id, test_category_id, 5);
  if round_id is null then raise exception 'TEST_PLAN_ROUND_FAILED'; end if;
  raise notice 'PLAN with office role: PASS';

  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  next_state := public.pista_ops_iniciar_rodizio(round_id);
  if next_state->>'status' is distinct from 'ativo' then
    raise exception 'TEST_START_ROUND_FAILED: got %', next_state;
  end if;
  -- In this scenario, zero on the first run must block the second run.
  update public.pista_ops_settings set morte_subita = true where evento_id = test_event_id;
  select count(*) into regular_runs from public.pista_ops_runs
  where evento_id = test_event_id and categoria_id = test_category_id;
  if regular_runs <> 4 then
    raise exception 'TEST_TWO_REGULAR_RUNS_FAILED: expected 4 non-canceled runs, got %', regular_runs;
  end if;
  if exists (
    select 1 from public.pista_ops_runs r
    join public.duplas d on d.id = r.dupla_id
    where d.status_pagamento = 'cancelado'
  ) then raise exception 'TEST_CANCELED_ENTRY_QUEUED'; end if;
  raise notice 'TWO REGULAR RUNS: PASS (two per each of two eligible entries; canceled excluded)';

  snapshot_before := pg_temp.pista_ops_test_snapshot();
  begin
    perform public.pista_ops_iniciar_rodizio(round_id);
  exception when sqlstate 'P0001' then
    get stacked diagnostics actual_message = message_text, actual_state = returned_sqlstate;
    was_denied := true;
  end;
  if coalesce(was_denied, false) is false or actual_state <> 'P0001'
    or actual_message is distinct from 'PISTA_ROUND_ALREADY_STARTED' then
    raise exception 'TEST_START_IDEMPOTENCY_FAILED: expected PISTA_ROUND_ALREADY_STARTED, got %/%', actual_state, actual_message;
  end if;
  snapshot_after := pg_temp.pista_ops_test_snapshot();
  if snapshot_after is distinct from snapshot_before then
    raise exception 'TEST_START_IDEMPOTENCY_MUTATED_DATA: before %, after %', snapshot_before, snapshot_after;
  end if;
  raise notice 'START ROUND repeated: PASS (explicit already-started error; no duplicate data)';

  -- A canceled subscription is rejected by Rabo da Gata and leaves Pista data unchanged.
  snapshot_before := pg_temp.pista_ops_test_snapshot();
  was_denied := false;
  actual_message := null;
  actual_state := null;
  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  begin
    perform public.pista_ops_rabo_da_gata(round_id, '60000000-0000-4000-8000-000000000003');
  exception when sqlstate 'P0001' then
    get stacked diagnostics actual_message = message_text, actual_state = returned_sqlstate;
    was_denied := true;
  end;
  if not was_denied or actual_message is distinct from 'PISTA_ENTRY_NOT_ELIGIBLE' then
    raise exception 'TEST_CANCELED_ENTRY_FAILED: expected PISTA_ENTRY_NOT_ELIGIBLE, got %/%', actual_state, actual_message;
  end if;
  snapshot_after := pg_temp.pista_ops_test_snapshot();
  if snapshot_after is distinct from snapshot_before then
    raise exception 'TEST_CANCELED_ENTRY_MUTATED_DATA: before %, after %', snapshot_before, snapshot_after;
  end if;
  raise notice 'CANCELED ENTRY rejected: PASS (no data changes)';

  -- Same request UUID must return the same queue item and position on replay.
  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  first_call := public.pista_ops_chamar_proxima(round_id, '70000000-0000-4000-8000-000000000001');
  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  repeated_call := public.pista_ops_chamar_proxima(round_id, '70000000-0000-4000-8000-000000000001');
  if repeated_call is distinct from first_call then
    raise exception 'TEST_CALL_IDEMPOTENCY_FAILED: first %, repeated %', first_call, repeated_call;
  end if;
  call_item_id := (first_call->>'item_id')::uuid;
  if (select count(*) from public.pista_ops_positions where rodada_id = round_id and estado = 'ocupada') <> 1 then
    raise exception 'TEST_CALL_IDEMPOTENCY_DUPLICATED_POSITION';
  end if;
  raise notice 'CALL NEXT repeated request: PASS (same result and one occupied position)';

  -- Valeu Boi without score must fail without mutation; with score it succeeds once.
  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  second_call := public.pista_ops_chamar_proxima(round_id, '70000000-0000-4000-8000-000000000002');
  snapshot_before := pg_temp.pista_ops_test_snapshot();
  was_denied := false;
  actual_message := null;
  actual_state := null;
  begin
    perform public.pista_ops_registrar_resultado((second_call->>'item_id')::uuid, 'valeu_boi', null);
  exception when invalid_parameter_value then
    get stacked diagnostics actual_message = message_text, actual_state = returned_sqlstate;
    was_denied := true;
  end;
  if not was_denied or actual_state <> '22023' or actual_message is distinct from 'PISTA_SCORE_REQUIRED' then
    raise exception 'TEST_VALEU_WITHOUT_SCORE_FAILED: expected PISTA_SCORE_REQUIRED, got %/%', actual_state, actual_message;
  end if;
  snapshot_after := pg_temp.pista_ops_test_snapshot();
  if snapshot_after is distinct from snapshot_before then
    raise exception 'TEST_VALEU_WITHOUT_SCORE_MUTATED_DATA: before %, after %', snapshot_before, snapshot_after;
  end if;
  raise notice 'VALEU BOI without score: PASS (explicit error; no mutation)';

  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  perform public.pista_ops_registrar_resultado((second_call->>'item_id')::uuid, 'valeu_boi', 12.5);
  if not exists (
    select 1 from public.pista_ops_runs where id = (
      select corrida_id from public.pista_ops_queue_items where id = (second_call->>'item_id')::uuid
    ) and estado = 'valeu_boi' and pontuacao = 12.5
  ) then raise exception 'TEST_VALEU_WITH_SCORE_FAILED'; end if;
  snapshot_before := pg_temp.pista_ops_test_snapshot();
  was_denied := false;
  actual_message := null;
  actual_state := null;
  begin
    perform public.pista_ops_registrar_resultado((second_call->>'item_id')::uuid, 'valeu_boi', 12.5);
  exception when sqlstate 'P0001' then
    get stacked diagnostics actual_message = message_text, actual_state = returned_sqlstate;
    was_denied := true;
  end;
  if not was_denied or actual_message is distinct from 'PISTA_RESULT_NOT_CALLABLE' then
    raise exception 'TEST_RESULT_IDEMPOTENCY_FAILED: expected PISTA_RESULT_NOT_CALLABLE, got %/%', actual_state, actual_message;
  end if;
  snapshot_after := pg_temp.pista_ops_test_snapshot();
  if snapshot_after is distinct from snapshot_before then
    raise exception 'TEST_RESULT_IDEMPOTENCY_MUTATED_DATA: before %, after %', snapshot_before, snapshot_after;
  end if;
  raise notice 'VALEU BOI with score and repeated result: PASS (single result; replay rejected without mutation)';

  -- Rabo da Gata is appended after regular queue items and does not reserve a position.
  snapshot_before := pg_temp.pista_ops_test_snapshot();
  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  rabo_call := public.pista_ops_rabo_da_gata(round_id, '60000000-0000-4000-8000-000000000001');
  if rabo_call->>'status' is distinct from 'encaminhado'
    or coalesce((rabo_call->>'reservou_posicao')::boolean, true) then
    raise exception 'TEST_RABO_STATUS_FAILED: got %', rabo_call;
  end if;
  if (select count(*) from public.pista_ops_positions where rodada_id = round_id and estado = 'ocupada') <> 1 then
    raise exception 'TEST_RABO_RESERVED_POSITION_BEFORE_CALL';
  end if;
  if (select count(*) from public.pista_ops_queue_items
       where rodada_id = round_id and tipo = 'rabo_da_gata' and estado = 'na_fila') <> 1 then
    raise exception 'TEST_RABO_NOT_AT_QUEUE_TAIL';
  end if;
  raise notice 'RABO DA GATA no reservation before call: PASS';

  -- Zero has score zero and consumes its occupied position exactly once.
  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  perform public.pista_ops_registrar_resultado((first_call->>'item_id')::uuid, 'zero', 0);
  if not exists (
    select 1 from public.pista_ops_runs where id = (
      select corrida_id from public.pista_ops_queue_items where id = (first_call->>'item_id')::uuid
    ) and estado = 'zero' and pontuacao = 0
  ) then raise exception 'TEST_ZERO_RESULT_FAILED'; end if;
  raise notice 'ZERO with score 0: PASS';

  -- Retorno interrupts the next regular call, releases its position, and consumes no bull.
  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  fourth_call := public.pista_ops_chamar_proxima(round_id, '70000000-0000-4000-8000-000000000004');
  select count(*) into consumed_before from public.pista_ops_positions
   where rodada_id = round_id and estado = 'consumida';
  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  next_state := public.pista_ops_registrar_retorno((fourth_call->>'item_id')::uuid);
  select count(*) into consumed_after from public.pista_ops_positions
   where rodada_id = round_id and estado = 'consumida';
  if next_state->>'status' is distinct from 'retorno_pendente'
    or coalesce((next_state->>'consumiu_boi')::boolean, true)
    or consumed_after <> consumed_before then
    raise exception 'TEST_RETURN_CONSUMPTION_FAILED: response %, consumed before %, after %', next_state, consumed_before, consumed_after;
  end if;
  raise notice 'RETURN interruption: PASS (position released; consumed bulls unchanged)';

  -- The Rabo call consumes no bull; finishing it frees its position.
  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  rabo_call := public.pista_ops_chamar_proxima(round_id, '70000000-0000-4000-8000-000000000005');
  if rabo_call->>'tipo' is distinct from 'rabo_da_gata' then
    raise exception 'TEST_RABO_QUEUE_ORDER_FAILED: expected Rabo after regular calls, got %', rabo_call;
  end if;
  select count(*) into consumed_before from public.pista_ops_positions
   where rodada_id = round_id and estado = 'consumida';
  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  perform public.pista_ops_finalizar_rabo_da_gata((rabo_call->>'item_id')::uuid);
  select count(*) into consumed_after from public.pista_ops_positions
   where rodada_id = round_id and estado = 'consumida';
  if consumed_after <> consumed_before then
    raise exception 'TEST_RABO_CONSUMPTION_FAILED: consumed before %, after %', consumed_before, consumed_after;
  end if;
  raise notice 'RABO DA GATA called after regular queue: PASS (no bull consumed)';

  -- With a return still pending and no later round planned, the call reports an explicit wait state.
  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  next_state := public.pista_ops_chamar_proxima(round_id, '70000000-0000-4000-8000-000000000006');
  if next_state->>'status' is distinct from 'aguardando_proximo_rodizio' then
    raise exception 'TEST_NO_NEXT_ROUND_STATE_FAILED: expected aguardando_proximo_rodizio, got %, queue %',
      next_state, (
        select jsonb_agg(jsonb_build_object(
          'item', q.id, 'entry', d.numero_senha, 'run', r.numero_corrida,
          'type', q.tipo, 'status', q.estado, 'return', q.eh_retorno
        ) order by q.ordem_fila)
        from public.pista_ops_queue_items q
        join public.duplas d on d.id = q.dupla_id
        left join public.pista_ops_runs r on r.id = q.corrida_id
        where q.rodada_id = round_id
      );
  end if;
  if not exists (
    select 1 from public.pista_ops_rounds where id = round_id and estado = 'aguardando_proximo_rodizio'
  ) then raise exception 'TEST_NO_NEXT_ROUND_NOT_PERSISTED'; end if;
  raise notice 'NO NEXT ROUND: PASS (explicit awaiting_proximo_rodizio; return preserved)';
end;
$pista_ops_rpc_tests$;

do $boi_tv_atendimento_tests$
declare
  v_event_id constant uuid := '20000000-0000-4000-8000-000000000002';
  v_category_id constant uuid := '30000000-0000-4000-8000-000000000003';
  organizer_id constant uuid := '40000000-0000-4000-8000-000000000001';
  office_id constant uuid := '40000000-0000-4000-8000-000000000002';
  announcer_id constant uuid := '40000000-0000-4000-8000-000000000005';
  provider_id constant uuid := '40000000-0000-4000-8000-000000000007';
  device_code text;
  device jsonb;
  entry_a constant uuid := '60000000-0000-4000-8000-000000000004';
  entry_b constant uuid := '60000000-0000-4000-8000-000000000005';
  round_id uuid;
  call_one jsonb;
  call_two jsonb;
  call_three jsonb;
  run_one uuid;
  run_two uuid;
  claimant_one uuid;
  claimant_two uuid;
  competitor_one uuid;
  review_one uuid;
  review_two uuid;
  attendance_one uuid;
  attendance_two uuid;
  x1_id uuid;
  x1_bull_one uuid;
  x1_match uuid;
  score numeric;
  state_text text;
  was_denied boolean;
begin
  insert into public.pista_ops_members(evento_id,usuario_id,funcao,ativo,criado_por) values
    (v_event_id,organizer_id,'organizador',true,organizer_id),
    (v_event_id,office_id,'escritorio',true,organizer_id),
    (v_event_id,announcer_id,'locutor',true,organizer_id)
  on conflict do nothing;
  insert into public.duplas(id,evento_id,categoria_id,numero_senha,puxador_id,status_pagamento,created_at,nome_cavalo,nome_equipe) values
    (entry_a,v_event_id,v_category_id,101,'50000000-0000-4000-8000-000000000001','pago',now(),'Cavalo teste A','Equipe teste A'),
    (entry_b,v_event_id,v_category_id,102,'50000000-0000-4000-8000-000000000002','pago',now(),'Cavalo teste B','Equipe teste B');

  perform set_config('request.jwt.claims',json_build_object('sub',organizer_id)::text,true);
  perform public.pista_ops_boi_tv_configurar(v_event_id,true);
  select codigo into strict device_code from public.pista_ops_device_code_create(v_event_id,'boi_tv');
  insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,is_anonymous)
  values(provider_id,'authenticated','authenticated','boi-tv-test@example.invalid','{}'::jsonb,'{}'::jsonb,true);
  perform set_config('request.jwt.claims',json_build_object('sub',provider_id,'is_anonymous',true)::text,true);
  device := public.pista_ops_device_activate(device_code,'80000000-0000-4000-8000-000000000001','Operador de teste');
  if device->>'evento_id' is distinct from v_event_id::text or device->>'funcao' is distinct from 'boi_tv' then
    raise exception 'TEST_BOI_TV_DEVICE_ACTIVATION_FAILED';
  end if;

  -- A review request does not consume or hold the next locution call.
  perform set_config('request.jwt.claims',json_build_object('sub',office_id)::text,true);
  round_id := public.pista_ops_planejar_rodizio(v_event_id,v_category_id,5);
  perform set_config('request.jwt.claims',json_build_object('sub',announcer_id)::text,true);
  perform public.pista_ops_iniciar_rodizio(round_id);
  call_one := public.pista_ops_chamar_proxima_automatica(round_id,'71000000-0000-4000-8000-000000000001');
  run_one := public.pista_ops_registrar_resultado((call_one->>'item_id')::uuid,'zero',0);
  select dupla_id into claimant_one from public.pista_ops_runs where id=run_one;
  select puxador_id into competitor_one from public.duplas where id=claimant_one;
  perform set_config('request.jwt.claims',json_build_object('sub',office_id)::text,true);
  begin
    perform public.pista_ops_boi_tv_solicitar_com_origem(run_one,'a_favor',claimant_one,'locucao');
    raise exception 'TEST_BOI_TV_OFFICE_REQUEST_ALLOWED';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claims',json_build_object('sub',organizer_id)::text,true);
  begin
    perform public.pista_ops_boi_tv_solicitar_com_origem(run_one,'a_favor',claimant_one,'locucao');
    raise exception 'TEST_BOI_TV_ORGANIZER_REQUEST_ALLOWED';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claims',json_build_object('sub',announcer_id)::text,true);
  review_one := public.pista_ops_boi_tv_solicitar_com_origem(run_one,'a_favor',claimant_one,'locucao');
  select id into attendance_one from public.pista_ops_boi_tv_atendimentos where revisao_pista_id=review_one;
  if attendance_one is null or (select dados_apresentacao->>'numero_boi' from public.pista_ops_boi_tv_atendimentos where id=attendance_one) <> '1'
    or (select dados_apresentacao->>'cavalo' from public.pista_ops_boi_tv_atendimentos where id=attendance_one) <> 'Cavalo teste A'
    or (select dados_apresentacao->>'equipe' from public.pista_ops_boi_tv_atendimentos where id=attendance_one) <> 'Equipe teste A'
    or (select origem from public.pista_ops_boi_tv_atendimentos where id=attendance_one) <> 'locucao' then
    raise exception 'TEST_BOI_TV_SNAPSHOT_FAILED';
  end if;
  perform set_config('request.jwt.claims',json_build_object('sub',announcer_id)::text,true);
  call_two := public.pista_ops_chamar_proxima_automatica(round_id,'71000000-0000-4000-8000-000000000002');
  if call_two->>'status' is distinct from 'chamada' then raise exception 'TEST_BOI_TV_QUEUE_ADVANCE_FAILED: %',call_two; end if;
  run_two := public.pista_ops_registrar_resultado((call_two->>'item_id')::uuid,'zero',0);
  select dupla_id into claimant_two from public.pista_ops_runs where id=run_two;
  review_two := public.pista_ops_boi_tv_solicitar_com_origem(run_two,'a_favor',claimant_two,'locucao');
  select id into attendance_two from public.pista_ops_boi_tv_atendimentos where revisao_pista_id=review_two;
  perform set_config('request.jwt.claims',json_build_object('sub',announcer_id)::text,true);
  call_three := public.pista_ops_chamar_proxima_automatica(round_id,'71000000-0000-4000-8000-000000000003');
  if call_three->>'status' is distinct from 'chamada' then raise exception 'TEST_BOI_TV_QUEUE_SECOND_ADVANCE_FAILED: %',call_three; end if;
  raise notice 'BOI TV queue: PASS (two pending reviews while later calls continue)';

  -- Duplicate open request is rejected.
  perform set_config('request.jwt.claims',json_build_object('sub',announcer_id)::text,true);
  was_denied := false;
  begin
    perform public.pista_ops_boi_tv_solicitar_com_origem(run_one,'a_favor',claimant_one,'locucao');
  exception when sqlstate 'P0001' then
    get stacked diagnostics state_text=message_text;
    was_denied := state_text='PISTA_TV_REVIEW_PENDING';
  end;
  if not was_denied or (select count(*) from public.pista_ops_boi_tv_atendimentos where revisao_pista_id in (review_one,review_two)) <> 2 then
    raise exception 'TEST_BOI_TV_DUPLICATE_PENDING_FAILED';
  end if;
  raise notice 'BOI TV duplicate pending request: PASS';

  -- Provider isolation and no official decision privilege.
  perform set_config('request.jwt.claims',json_build_object('sub',provider_id,'is_anonymous',true)::text,true);
  if not exists(select 1 from public.pista_ops_boi_tv_meus_eventos() where evento_id=v_event_id)
    or exists(select 1 from public.pista_ops_boi_tv_meus_eventos() where evento_id='20000000-0000-4000-8000-000000000001') then
    raise exception 'TEST_BOI_TV_EVENT_ISOLATION_FAILED';
  end if;
  if (select count(*) from public.pista_ops_boi_tv_atendimento_estado(v_event_id)) <> 2 then
    raise exception 'TEST_BOI_TV_OPERATOR_QUEUE_FAILED';
  end if;
  was_denied := false;
  begin
    perform public.pista_ops_boi_tv_atendimento_estado('20000000-0000-4000-8000-000000000001');
  exception when insufficient_privilege then was_denied := true;
  end;
  if not was_denied then raise exception 'TEST_BOI_TV_CROSS_EVENT_READ_ALLOWED'; end if;
  was_denied := false;
  begin
    perform public.pista_ops_boi_tv_decidir(review_one,'valeu_boi',12.5,'Sem permissao');
  exception when insufficient_privilege then was_denied := true;
  end;
  if not was_denied then raise exception 'TEST_BOI_TV_OPERATOR_OFFICIAL_DECISION_ALLOWED'; end if;
  raise notice 'BOI TV provider permission isolation: PASS';

  -- Operator progress cannot change official score or classification.
  perform public.pista_ops_boi_tv_atendimento_atualizar(attendance_one,'recebida');
  perform public.pista_ops_boi_tv_atendimento_atualizar(attendance_one,'em_analise');
  perform public.pista_ops_boi_tv_atendimento_atualizar(attendance_one,'analise_concluida');
  perform public.pista_ops_boi_tv_atendimento_atualizar(attendance_one,'aguardando_decisao');
  if (select estado from public.pista_ops_runs where id=run_one) <> 'zero'
    or (select count(*) from public.pista_ops_result_corrections where corrida_id=run_one) <> 0 then
    raise exception 'TEST_BOI_TV_SERVICE_CHANGED_OFFICIAL_RESULT';
  end if;
  raise notice 'BOI TV service states: PASS (official score unchanged)';

  -- Decide the older corrida by its stored ID while a later queue item is already called.
  perform set_config('request.jwt.claims',json_build_object('sub',organizer_id)::text,true);
  perform public.pista_ops_boi_tv_decidir(review_one,'valeu_boi',12.5,'Revisao confirmada');
  if (select estado from public.pista_ops_runs where id=run_one) <> 'valeu_boi'
    or (select pontuacao from public.pista_ops_runs where id=run_one) <> 12.5
    or (select estado from public.pista_ops_runs where id=run_two) <> 'zero'
    or (select estado from public.pista_ops_queue_items where id=(call_three->>'item_id')::uuid) <> 'chamada'
    or not exists(select 1 from public.pista_ops_result_corrections where corrida_id=run_one and resultado_anterior='zero' and resultado_novo='valeu_boi' and pontuacao_nova=12.5)
    or (select estado_atendimento from public.pista_ops_boi_tv_atendimentos where id=attendance_one) <> 'finalizada'
    or (select estado_atendimento from public.pista_ops_boi_tv_atendimentos where id=attendance_two) = 'finalizada' then
    raise exception 'TEST_BOI_TV_LATE_DECISION_TARGET_FAILED';
  end if;
  select pontuacao into score from public.pista_ops_classificacao(v_event_id,v_category_id,round_id,'parcial')
   where competidor_id=competitor_one;
  if score <> 12.5 then raise exception 'TEST_BOI_TV_CLASSIFICATION_REFRESH_FAILED: got %',score; end if;
  raise notice 'BOI TV late decision and ranking: PASS (original run only; correction history retained)';

  -- X1 review is sent to the same central, but the bracket keeps accepting bulls.
  perform public.x1_criar_chave(v_event_id,v_category_id,3::smallint,array[entry_a,entry_b]);
  select m.id into x1_match from public.x1_matches m where m.evento_id=v_event_id and m.categoria_id=v_category_id and m.fase=1 and m.posicao=1;
  perform set_config('request.jwt.claims',json_build_object('sub',announcer_id)::text,true);
  x1_bull_one := public.x1_registrar_boi_na_posicao(x1_match,'zero',1);
  begin
    perform public.x1_registrar_boi_na_posicao(x1_match,'valeu',1);
    raise exception 'TEST_X1_DUPLICATE_NOT_REJECTED';
  exception when raise_exception then
    if sqlerrm<>'X1_RESULT_CONFLICT' then raise; end if;
  end;
  perform set_config('request.jwt.claims',json_build_object('sub',office_id)::text,true);
  begin
    perform public.x1_solicitar_revisao_com_origem(x1_bull_one,'a_favor',entry_a,'x1');
    raise exception 'TEST_X1_OFFICE_REQUEST_ALLOWED';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claims',json_build_object('sub',announcer_id)::text,true);
  x1_id := public.x1_solicitar_revisao_com_origem(x1_bull_one,'a_favor',entry_a,'x1');
  perform set_config('request.jwt.claims',json_build_object('sub',announcer_id)::text,true);
  perform public.x1_registrar_boi(x1_match,'zero');
  if (select count(*) from public.x1_bois where confronto_id=x1_match) <> 2
    or (select estado from public.x1_matches where id=x1_match) <> 'revisao' then
    raise exception 'TEST_X1_PENDING_REVIEW_BLOCKED_NEXT_BULL';
  end if;
  perform set_config('request.jwt.claims',json_build_object('sub',organizer_id)::text,true);
  perform public.x1_decidir_revisao(x1_id,'valeu','Revisao do primeiro boi');
  if (select resultado from public.x1_bois where id=x1_bull_one) <> 'zero'
    or (select resultado_final from public.x1_revisoes where id=x1_id) <> 'valeu'
    or (select estado from public.x1_matches where id=x1_match) <> 'em_andamento'
    or not exists(select 1 from public.pista_ops_boi_tv_atendimentos where revisao_x1_id=x1_id and origem='x1' and dados_apresentacao->>'numero_boi'='1') then
    raise exception 'TEST_X1_REVIEW_PARALLEL_OR_HISTORY_FAILED';
  end if;
  raise notice 'X1 review: PASS (next bull accepted; original boi and revised decision retained)';
end;
$boi_tv_atendimento_tests$;

do $tropa_de_elite_tests$
declare
  event_id constant uuid := '20000000-0000-4000-8000-000000000001';
  category_id constant uuid := '30000000-0000-4000-8000-000000000002';
  organizer_id constant uuid := '40000000-0000-4000-8000-000000000001';
  announcer_id constant uuid := '40000000-0000-4000-8000-000000000003';
  entry_a constant uuid := '60000000-0000-4000-8000-000000000006';
  entry_b constant uuid := '60000000-0000-4000-8000-000000000007';
  match_id uuid;
  winner_id uuid;
  actual_message text;
begin
  update public.eventos
     set formato_competicao = 'tropa_de_elite'
   where id = event_id;

  insert into public.duplas(id, evento_id, categoria_id, numero_senha, puxador_id, status_pagamento, created_at)
  values
    (entry_a, event_id, category_id, 40, '50000000-0000-4000-8000-000000000001', 'pago', now()),
    (entry_b, event_id, category_id, 41, '50000000-0000-4000-8000-000000000002', 'pago', now());

  perform set_config('request.jwt.claims', json_build_object('sub', organizer_id)::text, true);
  begin
    perform public.x1_criar_chave(event_id, category_id, 3::smallint, array[entry_a, entry_b]);
    raise exception 'TEST_TROPA_ELITE_ALLOWED_MULTI_BOI_FORMAT';
  exception when raise_exception then
    get stacked diagnostics actual_message = message_text;
    if actual_message <> 'X1_CONFIG_INVALID' then raise; end if;
  end;

  perform public.x1_criar_chave(event_id, category_id, 1::smallint, array[entry_a, entry_b]);
  select id into match_id
    from public.x1_matches
   where evento_id = event_id and categoria_id = category_id and fase = 1 and posicao = 1;

  perform set_config('request.jwt.claims', json_build_object('sub', announcer_id)::text, true);
  perform public.x1_registrar_boi(match_id, 'valeu');
  perform public.x1_registrar_boi(match_id, 'zero');
  select vencedor_id into winner_id from public.x1_matches where id = match_id;
  if winner_id <> entry_a
    or (select estado from public.x1_matches where id = match_id) <> 'finalizada' then
    raise exception 'TEST_TROPA_ELITE_SINGLE_BULL_ADVANCE_FAILED';
  end if;

  begin
    insert into public.pista_ops_rounds(evento_id, categoria_id, numero, quantidade_bois, criado_por)
    values (event_id, category_id, 1, 1, organizer_id);
    raise exception 'TEST_TROPA_ELITE_ALLOWED_CLASSIFICATORY_ROUND';
  exception when sqlstate '22023' then
    get stacked diagnostics actual_message = message_text;
    if actual_message <> 'PISTA_TROPA_ELITE_USES_X1' then raise; end if;
  end;

  raise notice 'Tropa de Elite elimination: PASS (one bull per competitor; traditional rounds blocked)';
end;
$tropa_de_elite_tests$;

do $office_flow_tests$
declare
  organizer_id constant uuid := '40000000-0000-4000-8000-000000000001';
  registration_ids uuid[];
  event_id uuid;
  category_id uuid;
  error_message text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', organizer_id)::text, true);
  event_id := public.painel_iniciar_operacao_com_formato('Vaquejada ficticia de homologacao', 'tradicional');
  select id into strict category_id from public.categorias
  where evento_id = event_id and nome = 'Profissional' and ativa;

  select array_agg(inscricao) into registration_ids
  from public.inscrever_competidor_evento_multiplas_senhas(
    event_id, category_id, 'Vaqueiro ficticio', array[1, 2], 'Cavalo teste', 'Equipe teste', 'pendente', null
  ) as nova(inscricao);
  if cardinality(registration_ids) is distinct from 2 or (
    select count(*) from public.duplas where id = any(registration_ids) and status_pagamento = 'pendente'
  ) <> 2 then
    raise exception 'TEST_OFFICE_REGISTER_FAILED';
  end if;

  if public.painel_atualizar_pagamento(event_id, registration_ids[1], 'pago', null) is distinct from true
    or public.painel_atualizar_pagamento(event_id, registration_ids[2], 'isento', 'Cortesia de teste') is distinct from true then
    raise exception 'TEST_OFFICE_PAYMENT_FAILED';
  end if;
  if not exists (select 1 from public.duplas where id = registration_ids[1] and status_pagamento = 'pago')
    or not exists (select 1 from public.duplas where id = registration_ids[2] and status_pagamento = 'isento'
      and motivo_isencao = 'Cortesia de teste') then
    raise exception 'TEST_OFFICE_PAYMENT_NOT_PERSISTED';
  end if;

  if public.painel_encerrar_operacao(event_id) is distinct from true then
    raise exception 'TEST_OFFICE_CLOSE_FAILED';
  end if;
  if not exists (select 1 from public.eventos where id = event_id and status_operacional = 'concluido') then
    raise exception 'TEST_OFFICE_CLOSE_NOT_PERSISTED';
  end if;
  begin
    perform public.inscrever_competidor_evento_multiplas_senhas(
      event_id, category_id, 'Outro vaqueiro ficticio', array[3], null, null, 'pendente', null
    );
    raise exception 'TEST_OFFICE_REGISTER_ALLOWED_AFTER_CLOSE';
  exception when insufficient_privilege then
    get stacked diagnostics error_message = message_text;
    if error_message <> 'EVENT_OPERATION_BLOCKED' then raise; end if;
  end;
end;
$office_flow_tests$;

rollback;
