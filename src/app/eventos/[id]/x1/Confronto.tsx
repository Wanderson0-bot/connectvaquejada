import { decideReview, registerBull, requestReview } from "./actions";

type Boi = {
  id: string;
  numero: number;
  dupla_id: string;
  resultado: string;
  revisao: string | null;
  revisao_id: string | null;
  prazo: string | null;
  tipo_solicitacao: "a_favor" | "contra_terceiro" | null;
  reclamante: string | null;
};

export type ConfrontoX1 = {
  id: string;
  fase: number;
  posicao: number;
  estado: string;
  lado_a: string | null;
  lado_b: string | null;
  vencedor: string | null;
  nome_a: string | null;
  nome_b: string | null;
  bois: Boi[];
};

type Escopo = { eventId: string; categoryId: string };

const estados: Record<string, string> = {
  aguardando: "Aguardando", em_andamento: "Em andamento", revisao: "Em revisão",
  morte_subita: "Morte súbita", finalizada: "Finalizada",
};
const horarios = new Intl.DateTimeFormat("pt-BR", { timeStyle: "short", timeZone: "America/Sao_Paulo" });

function CamposEscopo({ eventId, categoryId }: Escopo) {
  return <>
    <input type="hidden" name="evento_id" value={eventId} />
    <input type="hidden" name="categoria_id" value={categoryId} />
  </>;
}

function RevisaoBoi({ boi, nome, adversario, podeSolicitar, escopo }: {
  boi: Boi; nome: string; adversario: string | null; podeSolicitar: boolean; escopo: Escopo;
}) {
  if (boi.revisao) return <div className="space-y-2">
    <span className="inline-flex rounded-full bg-amber-100 px-2.5 py-1 text-xs font-semibold text-amber-950">
      Revisão {boi.revisao}
    </span>
    <p className="text-xs text-stone-600">
      {boi.tipo_solicitacao === "a_favor" ? "Boi a favor" : "Boi contra/de terceiro"}
      {boi.reclamante && ` · Solicitante ${boi.reclamante}`}
      {boi.prazo && ` · Prazo ${horarios.format(new Date(boi.prazo))}`}
    </p>
    {boi.revisao_id && boi.revisao === "aberta" && <form action={decideReview} className="flex flex-wrap items-center gap-2">
      <CamposEscopo {...escopo} />
      <input type="hidden" name="revisao_id" value={boi.revisao_id} />
      <select name="resultado" aria-label={`Resultado da revisão do boi ${boi.numero}`} className="min-h-9 rounded-md border border-stone-300 px-2">
        <option value="valeu">Valeu</option><option value="zero">Zero</option>
      </select>
      <input name="justificativa" aria-label={`Justificativa da revisão do boi ${boi.numero}`} required minLength={3}
        placeholder="Justificativa" className="min-h-9 min-w-32 flex-1 rounded-md border border-stone-300 px-2" />
      <button className="min-h-9 rounded-md bg-amber-800 px-3 font-semibold text-white">Julgar</button>
    </form>}
  </div>;

  const aFavor = boi.resultado === "zero";
  const reclamante = aFavor ? boi.dupla_id : boi.resultado === "valeu" ? adversario : null;
  if (!podeSolicitar || !reclamante) return <span className="text-xs text-stone-500">—</span>;

  return <form action={requestReview}>
    <CamposEscopo {...escopo} />
    <input type="hidden" name="boi_id" value={boi.id} />
    <input type="hidden" name="tipo_solicitacao" value={aFavor ? "a_favor" : "contra_terceiro"} />
    <input type="hidden" name="reclamante_dupla_id" value={reclamante} />
    <button className="min-h-9 rounded-md border border-amber-700 px-3 py-1 text-left text-xs font-semibold text-amber-950 hover:bg-amber-50">
      {aFavor ? "Contestar meu zero · boi a favor" : `Contestar o valeu de ${nome} · boi contra/de terceiro`}
    </button>
  </form>;
}

export function Confronto({ confronto, ultimaFase, escopo, podeSolicitar }: {
  confronto: ConfrontoX1; ultimaFase: number; escopo: Escopo; podeSolicitar: boolean;
}) {
  const { bois, estado, fase, nome_a, nome_b, lado_a, lado_b, vencedor } = confronto;
  const nomeA = nome_a ?? "A definir";
  const nomeB = nome_b ?? "A definir";
  const nomeVencedor = vencedor === lado_a ? nomeA : nomeB;
  const nomeFase = fase === 1 ? "Primeira fase" : fase === ultimaFase ? "Final" : `Fase ${fase}`;
  const podeRegistrar = ["em_andamento", "morte_subita", "revisao"].includes(estado);
  const competidores = [{ id: lado_a, nome: nomeA, lado: "A" }, { id: lado_b, nome: nomeB, lado: "B" }];

  return <article className="overflow-hidden rounded-2xl border border-stone-200 bg-white">
    <div className="p-4 sm:p-6">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="font-bold">{nomeFase} · Confronto {confronto.posicao}</h3>
        <span className="rounded-full bg-stone-100 px-3 py-1 text-xs font-semibold text-stone-700">
          {estados[estado] ?? estado.replaceAll("_", " ")}
        </span>
      </header>
      <div className="mt-4 grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-stretch gap-2 sm:gap-4">
        {competidores.map(({ id, nome, lado }) => {
          const ganhou = vencedor !== null && vencedor === id;
          const pontos = bois.filter((boi) => boi.dupla_id === id && boi.resultado === "valeu").length;
          return <div key={lado} className={`min-w-0 rounded-xl border p-3 sm:p-4 ${lado === "B" ? "col-start-3 row-start-1" : ""} ${ganhou ? "border-emerald-300 bg-emerald-50" : "border-stone-200 bg-stone-50"}`}>
            <p className="break-words text-sm font-semibold sm:text-base">{nome}</p>
            <p className="mt-2 text-sm text-stone-700"><strong className="mr-1 text-3xl font-black tabular-nums text-stone-950">{pontos}</strong>{pontos === 1 ? "válido" : "válidos"}</p>
          </div>;
        })}
        <span className="col-start-2 row-start-1 self-center font-bold text-stone-500" aria-hidden="true">×</span>
      </div>
      {vencedor && <p className="mt-3 break-words text-sm font-bold text-emerald-900">Vencedor: {nomeVencedor}</p>}
      {podeRegistrar && <form action={registerBull} className="mt-4 flex flex-wrap items-center gap-2 border-t border-stone-200 pt-4">
        <CamposEscopo {...escopo} />
        <input type="hidden" name="confronto_id" value={confronto.id} />
        <input type="hidden" name="numero_boi" value={bois.length + 1} />
        <span className="mr-2 text-sm">Próximo boi {bois.length + 1} · {bois.length % 2 === 0 ? nomeA : nomeB}{estado === "revisao" ? " · revisão em paralelo" : ""}</span>
        <button name="resultado" value="valeu" className="min-h-10 rounded-lg bg-emerald-800 px-4 font-bold text-white">Valeu o boi</button>
        <button name="resultado" value="zero" className="min-h-10 rounded-lg bg-stone-700 px-4 font-bold text-white">Zero</button>
      </form>}
    </div>
    {bois.length > 0 && <div className="border-t border-stone-200">
      <h4 id={`historico-${confronto.id}`} className="px-4 pb-2 pt-4 text-sm font-bold sm:px-6">Histórico de bois</h4>
      <div role="region" aria-labelledby={`historico-${confronto.id}`} tabIndex={0}
        className="overflow-x-auto focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-emerald-700">
        <table className="w-full min-w-[32rem] text-left text-sm">
          <thead className="bg-stone-100 text-stone-700">
            <tr>{["Boi", "Vaqueiro", "Resultado", "Revisão BOI TV"].map((titulo) => (
              <th key={titulo} scope="col" className="px-3 py-2 first:pl-4 last:pr-4 sm:first:pl-6 sm:last:pr-6">{titulo}</th>
            ))}</tr>
          </thead>
          <tbody className="divide-y divide-stone-200">
            {bois.map((boi) => {
              const ladoA = boi.dupla_id === lado_a;
              const nome = ladoA ? nomeA : nomeB;
              return <tr key={boi.id} className="align-top">
                <th scope="row" className="py-3 pl-4 pr-3 font-semibold tabular-nums sm:pl-6">{boi.numero}</th>
                <td className="px-3 py-3 font-medium">{nome}</td>
                <td className="px-3 py-3"><span className={`whitespace-nowrap rounded-full px-2.5 py-1 text-xs font-semibold ${boi.resultado === "valeu" ? "bg-emerald-50 text-emerald-900" : "bg-stone-100 text-stone-800"}`}>
                  {boi.resultado === "valeu" ? "Valeu" : "Zero"}
                </span></td>
                <td className="py-3 pl-3 pr-4 sm:pr-6"><RevisaoBoi boi={boi} nome={nome} adversario={ladoA ? lado_b : lado_a} podeSolicitar={podeSolicitar} escopo={escopo} /></td>
              </tr>;
            })}
          </tbody>
        </table>
      </div>
    </div>}
  </article>;
}
