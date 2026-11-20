begin;

create table public.x1_brackets (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references public.eventos(id) on delete restrict,
  categoria_id uuid not null references public.categorias(id) on delete restrict,
  melhor_de smallint not null check (melhor_de in (3,5)),
  estado text not null default 'aberta' check (estado in ('aberta','em_andamento','finalizada')),
  criado_por uuid not null references public.perfis(id),
  criado_em timestamptz not null default now(),
  unique(evento_id,categoria_id)
);
create table public.x1_matches (
  id uuid primary key default gen_random_uuid(),
  chave_id uuid not null references public.x1_brackets(id) on delete restrict,
  evento_id uuid not null references public.eventos(id) on delete restrict,
  categoria_id uuid not null references public.categorias(id) on delete restrict,
  fase integer not null check (fase > 0),
  posicao integer not null check (posicao > 0),
  lado_a uuid references public.duplas(id) on delete restrict,
  lado_b uuid references public.duplas(id) on delete restrict,
  vencedor_id uuid references public.duplas(id) on delete restrict,
  estado text not null default 'aguardando' check (estado in ('aguardando','em_andamento','revisao','morte_subita','finalizada')),
  criado_em timestamptz not null default now(),
  unique(chave_id,fase,posicao),
  check(lado_a is null or lado_b is null or lado_a <> lado_b)
);
create table public.x1_bois (
  id uuid primary key default gen_random_uuid(),
  confronto_id uuid not null references public.x1_matches(id) on delete restrict,
  numero integer not null check(numero > 0),
  lado smallint not null check(lado in (1,2)),
  dupla_id uuid not null references public.duplas(id) on delete restrict,
  resultado text not null check(resultado in ('valeu','zero')),
  registrado_por uuid not null references public.perfis(id),
  registrado_em timestamptz not null default now(),
  unique(confronto_id,numero)
);
create table public.x1_revisoes (
  id uuid primary key default gen_random_uuid(),
  boi_id uuid not null unique references public.x1_bois(id) on delete restrict,
  solicitante uuid not null references public.perfis(id),
  prazo timestamptz not null default (now()+interval '5 minutes'),
  estado text not null default 'aberta' check(estado in ('aberta','confirmada','alterada')),
  resultado_final text check(resultado_final in ('valeu','zero')),
  julgado_por uuid references public.perfis(id),
  julgado_em timestamptz,
  justificativa text,
  criado_em timestamptz not null default now()
);
create index x1_matches_event_idx on public.x1_matches(evento_id,categoria_id,fase,posicao);

create or replace function public.x1_estado(p_evento_id uuid,p_categoria_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_actor uuid; v_result jsonb;
begin
 v_actor:=public.pista_ops_check_access(p_evento_id,array['organizador','escritorio','locutor']);
 select jsonb_build_object(
   'bracket', (select to_jsonb(b) from public.x1_brackets b where b.evento_id=p_evento_id and b.categoria_id=p_categoria_id),
   'inscricoes', coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'senha',d.numero_senha,'nome',c.nome,'equipe',d.nome_equipe)
      order by d.numero_senha) from public.duplas d join public.competidores c on c.id=d.puxador_id
      where d.evento_id=p_evento_id and d.categoria_id=p_categoria_id and d.status_pagamento in ('pago','isento')), '[]'::jsonb),
   'confrontos', coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'fase',m.fase,'posicao',m.posicao,'estado',m.estado,
      'lado_a',m.lado_a,'lado_b',m.lado_b,'vencedor',m.vencedor_id,
      'nome_a',ca.nome,'nome_b',cb.nome,'bois',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'numero',b.numero,'lado',b.lado,'dupla_id',b.dupla_id,'resultado',coalesce(r.resultado_final,b.resultado),'revisao',r.estado,'revisao_id',r.id,'prazo',r.prazo) order by b.numero)
       from public.x1_bois b left join public.x1_revisoes r on r.boi_id=b.id where b.confronto_id=m.id),'[]'::jsonb)) order by m.fase,m.posicao)
      from public.x1_matches m left join public.duplas da on da.id=m.lado_a left join public.competidores ca on ca.id=da.puxador_id
       left join public.duplas db on db.id=m.lado_b left join public.competidores cb on cb.id=db.puxador_id
      where m.evento_id=p_evento_id and m.categoria_id=p_categoria_id),'[]'::jsonb)) into v_result;
 return v_result;
end $$;

create or replace function public.x1_criar_chave(p_evento_id uuid,p_categoria_id uuid,p_melhor_de smallint,p_duplas uuid[])
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_actor uuid; v_id uuid; v_n integer; v_power integer; v_rounds integer; v_i integer; v_round integer; v_pos integer;
begin
 v_actor:=public.pista_ops_check_access(p_evento_id,array['organizador','escritorio']);
 if p_melhor_de not in (3,5) or coalesce(cardinality(p_duplas),0)<2 or cardinality(p_duplas)>16 then raise exception 'X1_CONFIG_INVALID'; end if;
 select count(*) into v_n from unnest(p_duplas) x(id) join public.duplas d on d.id=x.id
  where d.evento_id=p_evento_id and d.categoria_id=p_categoria_id and d.status_pagamento in ('pago','isento');
 if v_n<>cardinality(p_duplas) or v_n<> (select count(distinct x) from unnest(p_duplas) x) then raise exception 'X1_ENTRIES_INVALID'; end if;
 v_power:=1; v_rounds:=0; while v_power<v_n loop v_power:=v_power*2; v_rounds:=v_rounds+1; end loop;
 insert into public.x1_brackets(evento_id,categoria_id,melhor_de,criado_por) values(p_evento_id,p_categoria_id,p_melhor_de,v_actor) returning id into v_id;
 for v_round in 1..v_rounds loop
  for v_pos in 1..(v_power/(2^v_round)::integer) loop
   insert into public.x1_matches(chave_id,evento_id,categoria_id,fase,posicao) values(v_id,p_evento_id,p_categoria_id,v_round,v_pos);
  end loop;
 end loop;
 for v_i in 1..v_n loop
  v_pos:=(v_i+1)/2;
  if v_i%2=1 then update public.x1_matches set lado_a=p_duplas[v_i] where chave_id=v_id and fase=1 and posicao=v_pos;
  else update public.x1_matches set lado_b=p_duplas[v_i] where chave_id=v_id and fase=1 and posicao=v_pos; end if;
 end loop;
 -- Avanços automáticos cobrem chaves com número ímpar de inscritos (bye).
 for v_round in 1..v_rounds loop
  for v_pos in 1..(v_power/(2^v_round)::integer) loop
   update public.x1_matches set estado='em_andamento'
    where chave_id=v_id and fase=v_round and posicao=v_pos and lado_a is not null and lado_b is not null;
   update public.x1_matches set estado='finalizada',vencedor_id=coalesce(lado_a,lado_b)
    where chave_id=v_id and fase=v_round and posicao=v_pos and num_nonnulls(lado_a,lado_b)=1;
   if v_round<v_rounds then
    select vencedor_id into v_actor from public.x1_matches where chave_id=v_id and fase=v_round and posicao=v_pos and estado='finalizada' and num_nonnulls(lado_a,lado_b)=1;
    if found then
     if v_pos%2=1 then update public.x1_matches set lado_a=v_actor where chave_id=v_id and fase=v_round+1 and posicao=(v_pos+1)/2;
     else update public.x1_matches set lado_b=v_actor where chave_id=v_id and fase=v_round+1 and posicao=(v_pos+1)/2; end if;
    end if;
   end if;
  end loop;
 end loop;
 update public.x1_matches set estado='em_andamento' where chave_id=v_id and estado='aguardando' and lado_a is not null and lado_b is not null;
 update public.x1_brackets set estado='finalizada' where id=v_id and exists(select 1 from public.x1_matches where chave_id=v_id and fase=v_rounds and estado='finalizada');
 update public.x1_brackets set estado='em_andamento' where id=v_id;
 return v_id;
end $$;

create or replace function public.x1_registrar_boi(p_confronto_id uuid,p_resultado text)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_m public.x1_matches%rowtype; v_b uuid; v_actor uuid; v_n integer; v_lado smallint; v_dupla uuid; v_a integer; v_c integer; v_limite integer; v_winner uuid; v_next uuid; v_next_side text;
begin
 select * into v_m from public.x1_matches where id=p_confronto_id for update;
 if not found then raise exception 'X1_MATCH_NOT_FOUND'; end if;
 v_actor:=public.pista_ops_check_access(v_m.evento_id,array['organizador','locutor']);
 if p_resultado not in ('valeu','zero') or v_m.estado not in ('em_andamento','morte_subita') then raise exception 'X1_RESULT_INVALID'; end if;
 if exists(select 1 from public.x1_revisoes r join public.x1_bois b on b.id=r.boi_id where b.confronto_id=v_m.id and r.estado='aberta') then raise exception 'X1_REVIEW_PENDING'; end if;
 select count(*)+1 into v_n from public.x1_bois where confronto_id=v_m.id;
 v_lado:=case when v_n%2=1 then 1 else 2 end; v_dupla:=case when v_lado=1 then v_m.lado_a else v_m.lado_b end;
 insert into public.x1_bois(confronto_id,numero,lado,dupla_id,resultado,registrado_por) values(v_m.id,v_n,v_lado,v_dupla,p_resultado,v_actor) returning id into v_b;
 select count(*) filter(where coalesce(r.resultado_final,b.resultado)='valeu' and b.dupla_id=v_m.lado_a),
        count(*) filter(where coalesce(r.resultado_final,b.resultado)='valeu' and b.dupla_id=v_m.lado_b)
   into v_a,v_c from public.x1_bois b left join public.x1_revisoes r on r.boi_id=b.id where b.confronto_id=v_m.id;
 select melhor_de into v_limite from public.x1_brackets where id=v_m.chave_id;
 if v_n=v_limite*2 then
  if v_a>v_c then v_winner:=v_m.lado_a;
  elsif v_c>v_a then v_winner:=v_m.lado_b;
  else update public.x1_matches set estado='morte_subita' where id=v_m.id; end if;
 elsif v_n>v_limite*2 and v_n%2=0 and v_a<>v_c then
  v_winner:=case when v_a>v_c then v_m.lado_a else v_m.lado_b end;
 end if;
 if v_winner is not null then
  update public.x1_matches set estado='finalizada',vencedor_id=v_winner where id=v_m.id;
  select id into v_next from public.x1_matches where chave_id=v_m.chave_id and fase=v_m.fase+1 and posicao=(v_m.posicao+1)/2;
  if v_next is null then update public.x1_brackets set estado='finalizada' where id=v_m.chave_id;
  else
   v_next_side:=case when v_m.posicao%2=1 then 'lado_a' else 'lado_b' end;
   if v_next_side='lado_a' then update public.x1_matches set lado_a=v_winner where id=v_next; else update public.x1_matches set lado_b=v_winner where id=v_next; end if;
   update public.x1_matches set estado='em_andamento' where id=v_next and lado_a is not null and lado_b is not null;
  end if;
 end if;
 return v_b;
end $$;

create or replace function public.x1_solicitar_revisao(p_boi_id uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_event uuid; v_actor uuid; v_id uuid; v_b public.x1_bois%rowtype; v_m public.x1_matches%rowtype; v_next uuid;
begin
 select b.* into v_b from public.x1_bois b where b.id=p_boi_id;
 if not found then raise exception 'X1_RUN_NOT_FOUND'; end if;
 select evento_id into v_event from public.x1_matches where id=v_b.confronto_id;
 v_actor:=public.pista_ops_check_access(v_event,array['organizador','escritorio','locutor']);
 if v_b.registrado_em<now()-interval '5 minutes' then raise exception 'X1_REVIEW_EXPIRED'; end if;
 select * into v_m from public.x1_matches where id=v_b.confronto_id;
 if v_m.vencedor_id is not null then
  select id into v_next from public.x1_matches where chave_id=v_m.chave_id and fase=v_m.fase+1 and posicao=(v_m.posicao+1)/2;
  if v_next is not null and exists(select 1 from public.x1_bois where confronto_id=v_next) then raise exception 'X1_REVIEW_TOO_LATE'; end if;
 end if;
 insert into public.x1_revisoes(boi_id,solicitante) values(p_boi_id,v_actor) returning id into v_id;
 update public.x1_matches set estado='revisao' where id=v_b.confronto_id;
 return v_id;
end $$;

create or replace function public.x1_decidir_revisao(p_revisao_id uuid,p_resultado text,p_justificativa text)
returns void language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_event uuid; v_actor uuid; v_review public.x1_revisoes%rowtype; v_match uuid;
 v_m public.x1_matches%rowtype; v_limit integer; v_a integer; v_b integer; v_winner uuid; v_next uuid;
begin
 select m.evento_id,b.confronto_id into v_event,v_match from public.x1_revisoes r join public.x1_bois b on b.id=r.boi_id join public.x1_matches m on m.id=b.confronto_id where r.id=p_revisao_id;
 if not found then raise exception 'X1_REVIEW_NOT_FOUND'; end if;
 v_actor:=public.pista_ops_check_access(v_event,array['organizador','escritorio']);
 if p_resultado not in ('valeu','zero') or length(trim(coalesce(p_justificativa,'')))<3 then raise exception 'X1_REVIEW_DECISION_INVALID'; end if;
 select * into v_review from public.x1_revisoes where id=p_revisao_id for update;
 if v_review.estado<>'aberta' then raise exception 'X1_REVIEW_CLOSED'; end if;
 update public.x1_revisoes set estado=case when p_resultado=(select resultado from public.x1_bois where id=boi_id) then 'confirmada' else 'alterada' end,
  resultado_final=p_resultado,julgado_por=v_actor,julgado_em=now(),justificativa=trim(p_justificativa) where id=p_revisao_id;
 if exists(select 1 from public.x1_bois b join public.x1_revisoes r on r.boi_id=b.id where b.confronto_id=v_match and r.estado='aberta') then
  update public.x1_matches set estado='revisao' where id=v_match;
  return;
 end if;
 select * into v_m from public.x1_matches where id=v_match for update;
 select melhor_de into v_limit from public.x1_brackets where id=v_m.chave_id;
 select count(*) filter(where coalesce(r.resultado_final,b.resultado)='valeu' and b.dupla_id=v_m.lado_a),
        count(*) filter(where coalesce(r.resultado_final,b.resultado)='valeu' and b.dupla_id=v_m.lado_b)
   into v_a,v_b from public.x1_bois b left join public.x1_revisoes r on r.boi_id=b.id where b.confronto_id=v_match;
 if (select count(*) from public.x1_bois where confronto_id=v_match)>=v_limit*2 and v_a<>v_b then
  v_winner:=case when v_a>v_b then v_m.lado_a else v_m.lado_b end;
  update public.x1_matches set estado='finalizada',vencedor_id=v_winner where id=v_match;
  select id into v_next from public.x1_matches where chave_id=v_m.chave_id and fase=v_m.fase+1 and posicao=(v_m.posicao+1)/2;
  if v_next is null then update public.x1_brackets set estado='finalizada' where id=v_m.chave_id;
  elsif v_m.posicao%2=1 then update public.x1_matches set lado_a=v_winner where id=v_next;
  else update public.x1_matches set lado_b=v_winner where id=v_next; end if;
  if v_next is not null then update public.x1_matches set estado='em_andamento' where id=v_next and lado_a is not null and lado_b is not null; end if;
 elsif (select count(*) from public.x1_bois where confronto_id=v_match)>=v_limit*2 and v_a=v_b then
  update public.x1_matches set estado='morte_subita',vencedor_id=null where id=v_match;
 else update public.x1_matches set estado='em_andamento',vencedor_id=null where id=v_match; end if;
 if v_winner is null and v_m.vencedor_id is not null then
  select id into v_next from public.x1_matches where chave_id=v_m.chave_id and fase=v_m.fase+1 and posicao=(v_m.posicao+1)/2;
  if v_next is not null then
   if v_m.posicao%2=1 then update public.x1_matches set lado_a=null,estado='aguardando' where id=v_next;
   else update public.x1_matches set lado_b=null,estado='aguardando' where id=v_next; end if;
  end if;
 end if;
end $$;

revoke all on function public.x1_estado(uuid,uuid),public.x1_criar_chave(uuid,uuid,smallint,uuid[]),public.x1_registrar_boi(uuid,text),public.x1_solicitar_revisao(uuid),public.x1_decidir_revisao(uuid,text,text) from public,anon;
grant execute on function public.x1_estado(uuid,uuid),public.x1_criar_chave(uuid,uuid,smallint,uuid[]),public.x1_registrar_boi(uuid,text),public.x1_solicitar_revisao(uuid),public.x1_decidir_revisao(uuid,text,text) to authenticated;
commit;
