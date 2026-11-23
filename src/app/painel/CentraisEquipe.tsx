"use client";

import Link from "next/link";
import { Search } from "lucide-react";
import { useId, useState } from "react";
import { statusEvento, type Evento } from "@/lib/supervisao/modelo";

export type CentralEvento = Pick<Evento, "id" | "nome" | "data" | "status"> & { local: string };

function normalizar(texto: string) {
  return texto.normalize("NFD").replace(/\p{M}/gu, "").toLocaleLowerCase("pt-BR").trim();
}

export function CentraisEquipe({ eventos, encerradas }: { eventos: CentralEvento[]; encerradas: boolean }) {
  const tituloId = useId();
  const [busca, setBusca] = useState("");
  const filtro = normalizar(busca);
  const cards = eventos
    .map((evento) => ({ ...evento, dataFormatada: evento.data.split("-").reverse().join("/") }))
    .filter((evento) => normalizar(evento.nome).includes(filtro)
      || evento.dataFormatada.includes(filtro) || evento.data.includes(filtro));

  return <section aria-labelledby={tituloId} className="mt-8">
    <header className="mb-4 flex flex-wrap items-end justify-between gap-3">
      <h2 id={tituloId} className="text-xl font-bold tracking-tight text-stone-900">
        {encerradas ? "Centrais da equipe" : "Outras operações supervisionadas"}
      </h2>
      <label className="grid w-full max-w-xs gap-1 text-sm font-semibold text-stone-700">
        Buscar por nome ou data
        <span className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-500" aria-hidden="true" />
          <input type="search" value={busca} onChange={(event) => setBusca(event.target.value)} placeholder="Ex.: 16/11/2026"
            className="min-h-11 w-full rounded-lg border border-stone-300 bg-white pl-9 pr-3 font-normal text-stone-900 focus:border-orange-700 focus:outline-none focus:ring-1 focus:ring-orange-700" />
        </span>
      </label>
    </header>
    {cards.length === 0 ? <p role="status" className="rounded-xl border border-stone-200 bg-white p-4 text-sm text-stone-600">
      Nenhuma vaquejada encontrada para essa busca.
    </p> : <ul className="grid gap-4 lg:grid-cols-2 2xl:grid-cols-3">
      {cards.map((evento) => <li key={evento.id} className="flex min-w-0 flex-col justify-between gap-4 rounded-xl border border-stone-200 bg-white p-4 sm:p-5">
        <div className="min-w-0">
          <h3 className="break-words text-base font-bold text-stone-950">{evento.nome}</h3>
          <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-2 text-sm text-stone-600">
            <time dateTime={evento.data} className="tabular-nums">{evento.dataFormatada}</time>
            <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${evento.status === "cancelado" ? "bg-red-50 text-red-800" : evento.status === "concluido" ? "bg-emerald-50 text-emerald-800" : "bg-amber-50 text-amber-900"}`}>
              {statusEvento[evento.status]}
            </span>
            <span>{evento.local}</span>
            <span title={evento.id} className="font-mono text-xs text-stone-600">ID #{evento.id.slice(0, 6)}</span>
          </div>
        </div>
        <div className="flex flex-wrap gap-2 border-t border-stone-100 pt-3">
          <Link href={`/eventos/${evento.id}/supervisao-equipe`} prefetch={false} className="operation-primary">
            {encerradas ? "Abrir Central da Equipe" : "Acompanhar operação"}
          </Link>
          <Link href={`/eventos/${evento.id}/relatorio-operacional`} prefetch={false} className="operation-secondary">Relatório Operacional</Link>
        </div>
      </li>)}
    </ul>}
  </section>;
}
