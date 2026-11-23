"use client";

import { useSyncExternalStore, useTransition } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { RefreshOnInterval } from "./RefreshOnInterval";

function observarConexao(listener: () => void) {
  window.addEventListener("online", listener);
  window.addEventListener("offline", listener);
  return () => {
    window.removeEventListener("online", listener);
    window.removeEventListener("offline", listener);
  };
}

export function EstadoConexao() {
  const online = useSyncExternalStore(observarConexao, () => navigator.onLine, () => true);
  const pathname = usePathname();
  const relatorioOperacional = /^\/eventos\/[^/]+\/relatorio-operacional$/.test(pathname);
  const router = useRouter();
  const [atualizando, iniciarAtualizacao] = useTransition();
  const operando = pathname.startsWith("/eventos/") || pathname.startsWith("/boi-tv");
  const area = pathname.match(/^(\/eventos\/[^/]+)\/(duplas|pista-ops)(?:\/|$)/);
  const atualizarAutomaticamente = /^(\/eventos\/[^/]+)\/(duplas|pista-ops|x1)$/.test(pathname);
  if (relatorioOperacional) return null;
  if (area?.[2] === "pista-ops") {
    return online ? (
      <RefreshOnInterval enabled={atualizarAutomaticamente} everyMs={15000} />
    ) : (
      <aside role="status" className="border-b bg-amber-100 px-4 py-2 text-sm text-amber-950">
        Sem conexão. Aguarde a confirmação do servidor antes de repetir uma operação.
      </aside>
    );
  }
  if (!operando && online) return null;
  return (
    <aside className={online ? "flex flex-wrap items-center gap-2 border-b bg-stone-50 px-4 text-sm text-stone-700" : "flex flex-wrap items-center gap-2 border-b bg-amber-100 px-4 text-sm text-amber-950"}>
      <RefreshOnInterval enabled={atualizarAutomaticamente && online} everyMs={15000} />
      <span role="status" className="py-2">{online ? atualizando ? "Atualizando dados…" : "Conexão disponível" : "Sem conexão. Aguarde a confirmação do servidor antes de repetir uma operação."}</span>
      {operando && <button type="button" disabled={!online || atualizando} className="min-h-11 px-2 font-semibold underline disabled:opacity-50" onClick={() => iniciarAtualizacao(() => router.refresh())}>Atualizar dados</button>}
      {area && <Link href={`${area[1]}/historico?area=${area[2] === "duplas" ? "escritorio" : "locutor"}`} className="inline-flex min-h-11 items-center px-2 font-semibold underline">Histórico</Link>}
      {operando && <Link href="/ativar" className="ml-auto inline-flex min-h-11 items-center px-2 font-semibold underline">Sessão do aparelho</Link>}
    </aside>
  );
}
