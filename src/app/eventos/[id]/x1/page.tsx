import { Voltar } from "@/components/Voltar";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { createBracket, decideReview, registerBull, requestReview } from "./actions";

type Entry = { id: string; senha: number; nome: string; equipe: string | null };
type Bull = { id: string; numero: number; lado: number; dupla_id: string; resultado: string; revisao: string | null; revisao_id: string | null; prazo: string | null; tipo_solicitacao: "a_favor" | "contra_terceiro" | null; reclamante_dupla_id: string | null; reclamante: string | null };
type Match = { id: string; fase: number; posicao: number; estado: string; lado_a: string | null; lado_b: string | null; vencedor: string | null; nome_a: string | null; nome_b: string | null; bois: Bull[] };
type State = { bracket: { melhor_de: number; estado: string } | null; inscricoes: Entry[]; confrontos: Match[] };
type Category = { id: string; nome: string; modelo_competicao: string };

const errors: Record<string,string> = {
  X1_CONFIG_INVALID: "Confira o modelo da categoria e selecione de dois a dezesseis competidores.",
  X1_ENTRIES_INVALID: "As inscrições precisam ser válidas e não repetidas.",
  X1_ENTRIES_MUST_BE_POWER_OF_TWO: "A quantidade de inscrições precisa ser 2, 4, 8 ou 16.",
  X1_RESULT_CONFLICT: "Outro aparelho já registrou este boi. Confira o placar atualizado antes de continuar.",
  X1_MATCH_NOT_FOUND: "Confronto não encontrado.",
  X1_REVIEW_EXPIRED: "O prazo de cinco minutos para pedir revisão terminou.",
  X1_REVIEW_TOO_LATE: "O confronto seguinte já começou; não é possível reabrir este resultado.",
  X1_REVIEW_PENDING: "Aguarde o julgamento da revisão pendente.",
  X1_REVIEW_DECISION_INVALID: "Informe o resultado e uma justificativa.",
  X1_REVIEW_CLOSED: "Esta revisão já foi julgada.",
  PISTA_TV_DISABLED: "O boi de TV não está habilitado nas configurações deste evento.",
  X1_REVIEW_TYPE_RESULT_MISMATCH: "Esse tipo de solicitação não corresponde ao julgamento deste boi.",
  operacao: "A operação falhou. Confira seu acesso ao evento e tente novamente.",
};

export default async function X1Page({ params, searchParams }: PageProps<"/eventos/[id]/x1">) {
  const { id: eventId } = await params;
  const query = await searchParams;
  const categoryId = typeof query.categoria === "string" ? query.categoria : "";
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const { data: event, error: eventError } = await supabase.from("eventos").select("id,nome").eq("id", eventId).maybeSingle();
  if (eventError) {
    return <main className="mx-auto min-h-screen max-w-5xl bg-stone-50 px-4 py-10 text-stone-900 sm:px-8">
      <p role="alert" className="rounded-lg bg-amber-50 p-4 text-amber-950">Não foi possível carregar o evento.</p>
    </main>;
  }
  if (!event) notFound();
  const { data: categoryData, error: categoriesError } = await supabase.rpc("pista_ops_categorias", { p_evento_id: eventId });
  const categories = (categoryData ?? []) as Category[];
  const category = categories.find((item) => item.id === categoryId);
  const { data, error } = categoryId ? await supabase.rpc("x1_estado", { p_evento_id: eventId, p_categoria_id: categoryId }) : { data: null, error: null };
  const { data: boiTvEnabled } = categoryId ? await supabase.rpc("pista_ops_boi_tv_habilitado", { p_evento_id: eventId }) : { data: false };
  const { data: locucaoAccess } = boiTvEnabled
    ? await supabase.rpc("pista_ops_check_access", { p_evento_id: eventId, p_funcoes: ["locutor"] })
    : { data: null };
  const canRequestBoiTv = Boolean(locucaoAccess);
  const state = data as State | null;
  const tropaDeElite = state?.bracket ? state.bracket.melhor_de === 1 : category?.modelo_competicao === "eliminatoria";
  const canSetup = !state?.bracket;
  return <main className="mx-auto min-h-screen max-w-5xl bg-stone-50 px-4 py-8 text-stone-900 sm:px-8">
    <Voltar href={user.is_anonymous ? `/eventos/${eventId}/pista-ops` : "/painel"} />
    <header className="mt-5"><p className="text-sm font-semibold uppercase tracking-widest text-emerald-800">{tropaDeElite ? "Categoria eliminatória" : "Formato mano a mano"}</p><h1 className="mt-1 text-3xl font-black">{tropaDeElite ? `${category?.nome ?? "Tropa de Elite"} · Eliminatória` : "X1 de Vaquejada"}</h1><p className="mt-2 text-stone-600">{tropaDeElite ? "Sem fase classificatória: cada confronto começa com um boi por competidor; empate leva à morte súbita." : "Chaveamento, resultado de cada boi e pedidos de revisão em um só lugar."}</p></header>
    {query.erro && <p role="alert" className="mt-5 rounded-lg bg-red-100 p-3 text-red-900">{errors[String(query.erro)] ?? "A operação não foi concluída. Confira sua função no evento e tente novamente."}</p>}
    {(error || categoriesError) && <p role="alert" className="mt-5 rounded-lg bg-red-100 p-3 text-red-900">Não foi possível abrir a operação X1. Confira se sua função no evento permite operar.</p>}
    <section className="mt-7 rounded-xl border bg-white p-5">
      <label htmlFor="categoria" className="block font-bold">Categoria</label>
      <form className="mt-2 flex flex-wrap gap-2"><input type="hidden" name="id" value={eventId}/><select id="categoria" name="categoria" defaultValue={categoryId} className="min-h-11 rounded-lg border px-3"><option value="">Selecione a categoria</option>{categories?.map((item) => <option key={item.id} value={item.id}>{item.nome}</option>)}</select><button className="rounded-lg bg-stone-800 px-5 py-2 font-bold text-white">Abrir</button></form>
    </section>
    {category && state && !error && <>
      {canSetup ? <section className="mt-6 rounded-xl border bg-white p-5"><h2 className="text-xl font-bold">Montar chaveamento · {category.nome}</h2><p className="mt-1 text-sm text-stone-600">Selecione de 2 a 16 inscrições. A ordem selecionada define os primeiros confrontos; inscrições ímpares ficam no lado A.</p>
        {state.inscricoes.length < 2 ? <p className="mt-4 rounded-lg bg-amber-50 p-3 text-amber-900">São necessárias pelo menos duas inscrições pagas ou isentas.</p> : <form action={createBracket} className="mt-4"><input type="hidden" name="evento_id" value={eventId}/><input type="hidden" name="categoria_id" value={categoryId}/>{tropaDeElite ? <><input type="hidden" name="melhor_de" value="1"/><p className="rounded-lg bg-emerald-50 p-3 text-sm text-emerald-950">Formato fixo: um boi por competidor em cada confronto eliminatório. Empate segue para morte súbita.</p></> : <label className="block text-sm font-semibold">Formato<select name="melhor_de" className="ml-3 rounded-lg border px-3 py-2"><option value="3">Melhor de 3 bois</option><option value="5">Melhor de 5 bois</option></select></label>}<div className="mt-4 grid gap-2 sm:grid-cols-2">{state.inscricoes.map((entry) => <label key={entry.id} className="flex items-center gap-3 rounded-lg border p-3"><input type="checkbox" name="dupla_id" value={entry.id} className="size-5"/><span><b>Senha {entry.senha} · {entry.nome}</b>{entry.equipe && <small className="block text-stone-600">{entry.equipe}</small>}</span></label>)}</div><p className="mt-3 text-sm text-stone-600">Selecione 2 a 16 competidores. Se necessário, o sistema cria avanços automáticos para completar a chave.</p><button className="mt-5 rounded-lg bg-emerald-800 px-5 py-3 font-bold text-white">{tropaDeElite ? "Iniciar disputa eliminatória" : "Criar chave e iniciar X1"}</button></form>}</section>
      : <><section className="mt-6 rounded-xl bg-emerald-950 p-5 text-white"><p className="text-sm uppercase tracking-wider text-emerald-200">{tropaDeElite ? "Eliminatória ativa" : `Chave ativa · ${category.nome}`}</p><h2 className="mt-1 text-2xl font-bold">{tropaDeElite ? "Um boi por competidor" : `Melhor de ${state.bracket?.melhor_de} bois`}</h2><p className="mt-1">{state.bracket?.estado === "finalizada" ? "Competição encerrada" : tropaDeElite ? "O resultado do par decide o avanço; empate após os bois iniciais ativa a morte súbita." : "Boi válido soma um ponto. Empate após os bois regulares ativa a morte súbita."}</p><p className="mt-2 text-sm text-emerald-100">Boi de TV no evento: {boiTvEnabled ? "habilitado" : "desabilitado no painel administrativo"}.</p></section>
      <div className="mt-5 space-y-5">{state.confrontos.map((match) => <article key={match.id} className="rounded-xl border bg-white p-5"><div className="flex flex-wrap items-center justify-between gap-2"><h3 className="font-bold">{match.fase === 1 ? "Primeira fase" : match.fase === state.confrontos.reduce((max,m) => Math.max(max,m.fase),0) ? "Final" : `Fase ${match.fase}`} · confronto {match.posicao}</h3><span className="rounded-full bg-stone-100 px-3 py-1 text-sm">{match.estado.replaceAll("_"," ")}</span></div>
        <div className="mt-3 grid grid-cols-[1fr_auto_1fr] items-center gap-3 text-center"><div className="rounded-lg bg-stone-50 p-3 font-semibold">{match.nome_a ?? "A definir"}<small className="mt-1 block text-stone-500">{match.bois.filter((b)=>b.dupla_id===match.lado_a&&b.resultado==="valeu").length} válidos</small></div><b className="text-stone-400">×</b><div className="rounded-lg bg-stone-50 p-3 font-semibold">{match.nome_b ?? "A definir"}<small className="mt-1 block text-stone-500">{match.bois.filter((b)=>b.dupla_id===match.lado_b&&b.resultado==="valeu").length} válidos</small></div></div>
        {match.vencedor && <p className="mt-3 rounded-lg bg-emerald-100 p-3 font-bold text-emerald-950">Vencedor: {match.vencedor === match.lado_a ? match.nome_a : match.nome_b}</p>}
        {match.estado === "em_andamento" || match.estado === "morte_subita" || match.estado === "revisao" ? <form action={registerBull} className="mt-4 flex flex-wrap items-center gap-2"><input type="hidden" name="evento_id" value={eventId}/><input type="hidden" name="categoria_id" value={categoryId}/><input type="hidden" name="confronto_id" value={match.id}/><input type="hidden" name="numero_boi" value={match.bois.length+1}/><span className="mr-2 text-sm">Próximo boi: {match.bois.length+1} · {match.bois.length%2===0 ? match.nome_a : match.nome_b}{match.estado === "revisao" ? " · revisão em paralelo" : ""}</span><button name="resultado" value="valeu" className="rounded-lg bg-emerald-700 px-4 py-2 font-bold text-white">Valeu o boi</button><button name="resultado" value="zero" className="rounded-lg bg-stone-700 px-4 py-2 font-bold text-white">Zero</button></form> : null}
        {match.bois.length > 0 && <ol className="mt-4 divide-y rounded-lg border">{match.bois.map((bull) => {
          const nomeCompetidor = bull.dupla_id === match.lado_a ? match.nome_a : match.nome_b;
          const reclamanteId = bull.dupla_id === match.lado_a ? match.lado_b : match.lado_a;
          return <li key={bull.id} className="flex flex-wrap items-center justify-between gap-2 p-3 text-sm">
            <span>Boi {bull.numero} · {nomeCompetidor}: <b>{bull.resultado}</b>{bull.revisao && <span className="ml-2 text-amber-800">{bull.tipo_solicitacao === "a_favor" ? "Boi a favor" : "Boi contra/de terceiro"} · revisão {bull.revisao}{bull.reclamante && ` · solicitante ${bull.reclamante}`}{bull.prazo && ` · prazo ${new Date(bull.prazo).toLocaleTimeString("pt-BR")}`}</span>}</span>
            {bull.revisao_id && bull.revisao === "aberta" ? <form action={decideReview} className="flex flex-wrap gap-2"><input type="hidden" name="evento_id" value={eventId}/><input type="hidden" name="categoria_id" value={categoryId}/><input type="hidden" name="revisao_id" value={bull.revisao_id}/><select name="resultado" className="rounded border px-2"><option value="valeu">Valeu</option><option value="zero">Zero</option></select><input name="justificativa" required minLength={3} placeholder="Justificativa" className="min-w-36 rounded border px-2"/><button className="rounded bg-amber-700 px-3 py-1 font-bold text-white">Julgar</button></form> : null}
            {!bull.revisao && canRequestBoiTv && bull.resultado === "zero" && <form action={requestReview} className="flex flex-wrap items-center gap-2"><input type="hidden" name="evento_id" value={eventId}/><input type="hidden" name="categoria_id" value={categoryId}/><input type="hidden" name="boi_id" value={bull.id}/><input type="hidden" name="tipo_solicitacao" value="a_favor"/><input type="hidden" name="reclamante_dupla_id" value={bull.dupla_id}/><button className="rounded border border-amber-700 px-3 py-1 font-semibold text-amber-900">Contestar meu zero · boi a favor</button></form>}
            {!bull.revisao && canRequestBoiTv && bull.resultado === "valeu" && reclamanteId && <form action={requestReview} className="flex flex-wrap items-center gap-2"><input type="hidden" name="evento_id" value={eventId}/><input type="hidden" name="categoria_id" value={categoryId}/><input type="hidden" name="boi_id" value={bull.id}/><input type="hidden" name="tipo_solicitacao" value="contra_terceiro"/><input type="hidden" name="reclamante_dupla_id" value={reclamanteId}/><button className="rounded border border-amber-700 px-3 py-1 font-semibold text-amber-900">Contestar o valeu de {nomeCompetidor} · boi contra/de terceiro</button></form>}
          </li>;
        })}</ol>}
      </article>)}</div></>}
    </>}
  </main>;
}
