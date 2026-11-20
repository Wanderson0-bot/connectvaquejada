begin;

-- The limit applies to an individual run score, never to totals or rankings.
-- NOT VALID preserves historical rows while enforcing the rule on new writes.
alter table public.pista_ops_runs
  add constraint pista_ops_run_score_max_40_ck
  check (pontuacao is null or pontuacao <= 40) not valid;

alter table public.pista_ops_result_corrections
  add constraint pista_ops_correction_new_score_max_40_ck
  check (pontuacao_nova <= 40) not valid;

alter table public.pista_corridas
  add constraint pista_corridas_score_max_40_ck
  check (pontuacao <= 40) not valid;

alter table public.pista_correcoes_corrida
  add constraint pista_correcao_score_max_40_ck
  check (pontuacao <= 40) not valid;

commit;
