"use client";

import { useState } from "react";

type Corrida = { id: string; numero_senha: number; numero_corrida: number; estado: string; pontuacao: number | null };
type Rodizio = { id: string; numero: number; corridas: Corrida[] };
const filtros = ["Todas", "Lançadas", "Pendentes"] as const;
const situacoes: Record<string, string> = {
  retorno_pendente: "Retorno pendente",
  em_curso: "Em curso",
  valeu_boi: "Valeu Boi",
  zero: "Zero",
  sem_direito: "Sem direito à 2ª corrida",
};
const lancada = (corrida: Corrida) => corrida.estado === "valeu_boi" || corrida.estado === "zero";

export function CorridasPorSenha({ rodizios, rodizioInicial }: { rodizios: Rodizio[]; rodizioInicial?: string }) {
  const [selecao, setSelecao] = useState("");
  const [busca, setBusca] = useState("");
  const [filtro, setFiltro] = useState<(typeof filtros)[number]>("Todas");
  const rodizio = rodizios.find(({ id }) => id === selecao) ?? rodizios.find(({ id }) => id === rodizioInicial) ?? rodizios[0];
  const porSenha = new Map<number, Corrida[]>();
  for (const corrida of rodizio?.corridas ?? []) {
    const grupo = porSenha.get(corrida.numero_senha) ?? [];
    grupo.push(corrida);
    porSenha.set(corrida.numero_senha, grupo);
  }
  const senhaBuscada = busca.trim().replace(/^0+(?=\d)/, "");
  const grupos = [...porSenha.entries()]
    .filter(([senha, corridas]) => String(senha).includes(senhaBuscada) && (
      filtro === "Todas" || corridas.some((corrida) => filtro === "Lançadas"
        ? lancada(corrida)
        : !lancada(corrida) && corrida.estado !== "sem_direito")
    ))
    .sort(([a], [b]) => a - b);

  if (!rodizio) return <p className="text-sm text-stone-600">Nenhuma corrida foi registrada ainda.</p>;

  return <div className="space-y-4">
    <div className="flex flex-wrap items-end gap-3">
      <label className="grid gap-1 text-sm font-medium">Rodízio
        <select value={rodizio.id} onChange={(event) => setSelecao(event.target.value)} className="min-h-10 rounded-lg border border-stone-300 bg-white px-3">
          {rodizios.map(({ id, numero }) => <option key={id} value={id}>Rodízio #{numero}</option>)}
        </select>
      </label>
      <label className="grid gap-1 text-sm font-medium">Buscar por senha
        <input type="search" inputMode="numeric" value={busca} onChange={(event) => setBusca(event.target.value)}
          placeholder="Ex.: 7" className="min-h-10 w-40 max-w-full rounded-lg border border-stone-300 px-3" />
      </label>
      <div role="group" aria-label="Filtrar corridas" className="flex flex-wrap gap-1 rounded-lg bg-stone-100 p-1">
        {filtros.map((opcao) => <button key={opcao} type="button" aria-pressed={filtro === opcao} onClick={() => setFiltro(opcao)}
          className={`min-h-9 rounded-md px-3 text-sm font-semibold ${filtro === opcao ? "bg-stone-900 text-white" : "text-stone-700 hover:bg-stone-200"}`}>{opcao}</button>)}
      </div>
    </div>
    {grupos.length === 0 ? <p role="status" className="text-sm text-stone-600">{porSenha.size ? "Nenhuma senha corresponde aos filtros." : "Nenhuma corrida registrada neste rodízio."}</p> :
      <table className="w-full table-fixed border-collapse text-left text-sm">
        <thead className="bg-stone-100 text-stone-700"><tr>
          <th scope="col" className="w-[22%] p-2 sm:p-3">Senha</th>
          <th scope="col" className="p-2 sm:p-3">Corrida 1</th>
          <th scope="col" className="p-2 sm:p-3">Corrida 2</th>
        </tr></thead>
        <tbody className="divide-y divide-stone-200">{grupos.map(([senha, corridas]) => <tr key={senha} className="align-top">
          <th scope="row" className="p-2 font-semibold tabular-nums sm:p-3">{senha}</th>
          {[1, 2].map((numero) => {
            const corrida = corridas.find(({ numero_corrida }) => numero_corrida === numero);
            return <td key={numero} className="p-2 sm:p-3">
              <span className={corrida && lancada(corrida) ? "font-semibold text-stone-950" : "text-stone-600"}>
                {corrida ? situacoes[corrida.estado] ?? "Pendente" : "—"}
              </span>
              {corrida && lancada(corrida) && corrida.pontuacao !== null && (
                <span className="block tabular-nums text-stone-600">{corrida.pontuacao.toLocaleString("pt-BR")} pontos</span>
              )}
            </td>;
          })}
        </tr>)}</tbody>
      </table>}
  </div>;
}
