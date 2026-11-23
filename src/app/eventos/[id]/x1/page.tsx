import { Voltar } from "@/components/Voltar";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { createBracket } from "./actions";
import { Confronto, type ConfrontoX1 } from "./Confronto";

type Entry = { id: string; senha: number; nome: string; equipe: string | null };
type State = { bracket: { melhor_de: number; estado: string } | null; inscricoes: Entry[]; confrontos: ConfrontoX1[] };
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
    return <main className="min-h-screen w-full bg-stone-50 px-4 py-10 text-stone-900 sm:px-8">
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
  const chave = state?.bracket;
  const ultimaFase = Math.max(0, ...(state?.confrontos ?? []).map(({ fase }) => fase));
  return <main className="min-h-screen w-full bg-stone-50 px-4 py-8 text-stone-900 sm:px-8">
    <Voltar href={user.is_anonymous ? `/eventos/${eventId}/pista-ops` : "/painel"} />
    <header className="mt-5"><p className="text-sm font-semibold uppercase tracking-widest text-emerald-800">{tropaDeElite ? "Categoria eliminatória" : "Formato mano a mano"}</p><h1 className="mt-1 text-3xl font-black">{tropaDeElite ? `${category?.nome ?? "Tropa de Elite"} · Eliminatória` : "X1 de Vaquejada"}</h1><p className="mt-2 text-stone-600">{tropaDeElite ? "Sem fase classificatória: cada confronto começa com um boi por competidor; empate leva à morte súbita." : "Chaveamento, resultado de cada boi e pedidos de revisão em um só lugar."}</p></header>
    {query.erro && <p role="alert" className="mt-5 rounded-lg bg-red-100 p-3 text-red-900">{errors[String(query.erro)] ?? "A operação não foi concluída. Confira sua função no evento e tente novamente."}</p>}
    {(error || categoriesError) && <p role="alert" className="mt-5 rounded-lg bg-red-100 p-3 text-red-900">Não foi possível abrir a operação X1. Confira se sua função no evento permite operar.</p>}
    <section className="mt-7 rounded-xl border bg-white p-5">
      <label htmlFor="categoria" className="block font-bold">Categoria</label>
      <form className="mt-2 flex flex-wrap items-center gap-2">
        <select id="categoria" name="categoria" defaultValue={categoryId} className="min-h-11 w-full rounded-lg border border-stone-300 bg-white px-3 sm:w-64">
          <option value="">{categories.some(({ nome }) => nome.toLowerCase() === "geral") ? "Selecione a categoria" : "Geral"}</option>
          {categories.map((item) => <option key={item.id} value={item.id}>{item.nome}</option>)}
        </select>
        <button className="min-h-11 rounded-lg bg-stone-800 px-5 py-2 font-bold text-white">Abrir</button>
      </form>
      {!categoryId && !categoriesError && <p className="mt-2 text-sm text-stone-600">Selecione uma categoria para consultar ou montar a chave.</p>}
    </section>
    {category && state && !error && <>
      {!chave ? <section className="mt-6 rounded-xl border bg-white p-5"><h2 className="text-xl font-bold">Montar chaveamento · {category.nome}</h2><p className="mt-1 text-sm text-stone-600">Selecione de 2 a 16 inscrições. A ordem selecionada define os primeiros confrontos; inscrições ímpares ficam no lado A.</p>
        {state.inscricoes.length < 2 ? <p className="mt-4 rounded-lg bg-amber-50 p-3 text-amber-900">São necessárias pelo menos duas inscrições pagas ou isentas.</p> : <form action={createBracket} className="mt-4"><input type="hidden" name="evento_id" value={eventId}/><input type="hidden" name="categoria_id" value={categoryId}/>{tropaDeElite ? <><input type="hidden" name="melhor_de" value="1"/><p className="rounded-lg bg-emerald-50 p-3 text-sm text-emerald-950">Formato fixo: um boi por competidor em cada confronto eliminatório. Empate segue para morte súbita.</p></> : <label className="block text-sm font-semibold">Formato<select name="melhor_de" className="ml-3 rounded-lg border px-3 py-2"><option value="3">Melhor de 3 bois</option><option value="5">Melhor de 5 bois</option></select></label>}<div className="mt-4 grid gap-2 sm:grid-cols-2">{state.inscricoes.map((entry) => <label key={entry.id} className="flex items-center gap-3 rounded-lg border p-3"><input type="checkbox" name="dupla_id" value={entry.id} className="size-5"/><span><b>Senha {entry.senha} · {entry.nome}</b>{entry.equipe && <small className="block text-stone-600">{entry.equipe}</small>}</span></label>)}</div><p className="mt-3 text-sm text-stone-600">Selecione 2 a 16 competidores. Se necessário, o sistema cria avanços automáticos para completar a chave.</p><button className="mt-5 rounded-lg bg-emerald-800 px-5 py-3 font-bold text-white">{tropaDeElite ? "Iniciar disputa eliminatória" : "Criar chave e iniciar X1"}</button></form>}</section>
      : <>
        <section aria-labelledby="chave-x1" className="mt-6 rounded-2xl border border-stone-200 bg-white p-4 sm:p-6">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="text-xs font-semibold uppercase tracking-wider text-emerald-800">Chaveamento</p>
              <h2 id="chave-x1" className="mt-1 text-xl font-bold sm:text-2xl">
                {category.nome} · {tropaDeElite ? "Um boi por competidor" : `Melhor de ${chave.melhor_de} bois`}
              </h2>
            </div>
            <span className={`rounded-full px-3 py-1 text-xs font-semibold ${chave.estado === "finalizada" ? "bg-stone-100 text-stone-800" : "bg-emerald-50 text-emerald-900"}`}>
              {chave.estado === "finalizada" ? "Competição encerrada" : chave.estado === "aberta" ? "Chave aberta" : "Em andamento"}
            </span>
          </div>
          <p className="mt-3 text-sm text-stone-700">Boi de TV: <strong>{boiTvEnabled ? "Habilitado" : "Desabilitado"}</strong></p>
        </section>
        <div className="mt-5 space-y-5">
          {state.confrontos.map((confronto) => <Confronto key={confronto.id} confronto={confronto}
            ultimaFase={ultimaFase} escopo={{ eventId, categoryId }} podeSolicitar={canRequestBoiTv} />)}
        </div>
      </>}

    </>}
  </main>;
}
