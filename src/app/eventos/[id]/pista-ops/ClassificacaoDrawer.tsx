"use client";

import { useEffect, useState } from "react";
import { Trophy, X } from "lucide-react";

export type ClassificacaoItem = {
  posicao: number;
  competidor_id: string;
  competidor_nome: string;
  pontuacao: number;
  corridas: number;
};

type Props = {
  categoria: string;
  rodizio: string;
  parcial: ClassificacaoItem[];
  geral: ClassificacaoItem[];
  erro: boolean;
};

export function ClassificacaoDrawer({ categoria, rodizio, parcial, geral, erro }: Props) {
  const [aberta, setAberta] = useState(false);
  const [escopo, setEscopo] = useState<"parcial" | "geral">("parcial");
  const classificacao = escopo === "parcial" ? parcial : geral;

  useEffect(() => {
    if (!aberta) return;
    function fecharComEscape(event: KeyboardEvent) {
      if (event.key === "Escape") setAberta(false);
    }
    document.addEventListener("keydown", fecharComEscape);
    return () => document.removeEventListener("keydown", fecharComEscape);
  }, [aberta]);

  return (
    <>
      <button
        type="button"
        onClick={() => setAberta(true)}
        aria-haspopup="dialog"
        style={{ backgroundColor: "#063B8C" }}
        className="inline-flex min-h-9 items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-semibold text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#063B8C]"
      >
        <Trophy aria-hidden="true" className="size-3.5" />
        Classificação
      </button>
      {aberta && (
        <div className="fixed inset-0 z-50">
          <button
            type="button"
            aria-label="Fechar classificação"
            onClick={() => setAberta(false)}
            className="absolute inset-0 bg-black/45"
          />
          <aside
            role="dialog"
            aria-modal="true"
            aria-labelledby="classificacao-titulo"
            className="absolute inset-y-0 right-0 flex w-full max-w-md flex-col bg-white shadow-2xl"
          >
            <header className="border-b border-stone-200 px-5 py-5">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-xs font-bold uppercase tracking-wider text-orange-800">
                    {categoria} · {rodizio}
                  </p>
                  <h2 id="classificacao-titulo" className="mt-1 text-xl font-bold text-stone-950">
                    Classificação
                  </h2>
                </div>
                <button
                  type="button"
                  aria-label="Fechar classificação"
                  onClick={() => setAberta(false)}
                  className="rounded-md p-2 text-stone-600 hover:bg-stone-100"
                >
                  <X aria-hidden="true" className="size-5" />
                </button>
              </div>
              <div className="mt-5 grid grid-cols-2 rounded-lg bg-stone-100 p-1" aria-label="Período da classificação">
                {(["parcial", "geral"] as const).map((value) => (
                  <button
                    key={value}
                    type="button"
                    aria-pressed={escopo === value}
                    onClick={() => setEscopo(value)}
                    className={`min-h-10 rounded-md px-3 text-sm font-semibold capitalize ${escopo === value ? "bg-white text-orange-900 shadow-sm" : "text-stone-600 hover:text-stone-900"}`}
                  >
                    {value}
                  </button>
                ))}
              </div>
              <p className="mt-2 text-xs text-stone-600">
                {escopo === "parcial"
                  ? `Pontos do ${rodizio} na categoria.`
                  : "Pontos acumulados em todos os rodízios desta categoria."}
              </p>
            </header>
            <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
              {erro ? (
                <p role="alert" className="rounded-lg bg-red-50 p-4 text-sm text-red-900">
                  Não foi possível carregar a classificação. Atualize a locução e tente novamente.
                </p>
              ) : classificacao.length === 0 ? (
                <p className="rounded-lg bg-stone-50 p-4 text-sm text-stone-600">
                  Ainda não há pontuações registradas neste período.
                </p>
              ) : (
                <ol className="divide-y divide-stone-200">
                  {classificacao.map((item) => (
                    <li key={item.competidor_id} className="flex items-center gap-3 py-3">
                      <span className="grid size-9 shrink-0 place-items-center rounded-full bg-orange-50 text-sm font-bold text-orange-900">
                        {item.posicao}
                      </span>
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-semibold text-stone-900">{item.competidor_nome}</p>
                        <p className="text-xs text-stone-500">{item.corridas} corridas pontuadas</p>
                      </div>
                      <strong className="whitespace-nowrap text-stone-900">
                        {Number(item.pontuacao).toLocaleString("pt-BR")} pts
                      </strong>
                    </li>
                  ))}
                </ol>
              )}
            </div>
          </aside>
        </div>
      )}
    </>
  );
}
