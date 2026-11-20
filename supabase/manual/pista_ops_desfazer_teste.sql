-- DESTRUCTIVE TEST-ONLY SCRIPT.
-- NEVER run this in production or against any shared/remote database.
-- It refuses to run unless current_database() is exactly connect_vaquejada_teste.
-- It drops only functions and tables created by 202611060001_pista_ops_mvp.sql.
-- No CASCADE is used; unexpected dependencies must stop the script for review.
\set ON_ERROR_STOP on

begin;

do $pista_ops_test_database_guard$
begin
  if current_database() <> 'connect_vaquejada_teste' then
    raise exception 'Refusing teardown: current database is %, expected connect_vaquejada_teste.', current_database();
  end if;
end;
$pista_ops_test_database_guard$;

-- Functions first: RPCs depend on the helper routines and the Pista Ops tables.
drop function if exists public.pista_ops_state(uuid, uuid);
drop function if exists public.pista_ops_registrar_empate(uuid, uuid, jsonb, text, text);
drop function if exists public.pista_ops_salvar_premiacao(uuid, uuid, jsonb);
drop function if exists public.pista_ops_corrigir_resultado(uuid, text, numeric, text);
drop function if exists public.pista_ops_substituir_dupla(uuid, uuid);
drop function if exists public.pista_ops_finalizar_rabo_da_gata(uuid);
drop function if exists public.pista_ops_rabo_da_gata(uuid, uuid);
drop function if exists public.pista_ops_liberar_retorno(uuid);
drop function if exists public.pista_ops_registrar_retorno(uuid);
drop function if exists public.pista_ops_registrar_resultado(uuid, text, numeric);
drop function if exists public.pista_ops_chamar_proxima(uuid, uuid);
drop function if exists public.pista_ops_iniciar_rodizio(uuid);
drop function if exists public.pista_ops_planejar_rodizio(uuid, uuid, integer);
drop function if exists public.pista_ops_configurar_substituicao(uuid, boolean);
drop function if exists public.pista_ops_configurar_membro(uuid, uuid, text, boolean);
drop function if exists public.pista_ops_lock_category(uuid, uuid);
drop function if exists public.pista_ops_check_access(uuid, text[]);

-- Child tables before parents; all are Pista Ops-owned objects.
drop table if exists public.pista_ops_result_corrections;
drop table if exists public.pista_ops_positions;
drop table if exists public.pista_ops_queue_items;
drop table if exists public.pista_ops_call_requests;
drop table if exists public.pista_ops_runs;
drop table if exists public.pista_ops_prize_versions;
drop table if exists public.pista_ops_ties;
drop table if exists public.pista_ops_settings;
drop table if exists public.pista_ops_first_organizer_audit;
drop table if exists public.pista_ops_members;
drop table if exists public.pista_ops_rounds;

commit;
