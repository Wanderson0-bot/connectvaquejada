"use client";

import { useSyncExternalStore, useTransition } from "react";
import Link from "next/link";
import { History, RefreshCw, Smartphone, UserRound } from "lucide-react";
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

const sessao = {
  conta: { href: "/painel/dispositivos", texto: "Conta conectada", compacto: "Conta", acao: "Gerenciar dispositivos", icone: UserRound },
  aparelho: { href: "/ativar", texto: "Aparelho autorizado", compacto: "Aparelho", acao: "Gerenciar ou encerrar", icone: Smartphone },
  visitante: { href: "/ativar", texto: "Ativar aparelho", compacto: "Ativar", acao: "Abrir ativação", icone: Smartphone },
};
const controle = "inline-flex min-h-8 items-center justify-center gap-1.5 rounded-md px-2 text-xs font-semibold text-stone-700 hover:bg-stone-200 focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-orange-700 disabled:opacity-50";

export function EstadoConexao({ tipoSessao }: { tipoSessao: keyof typeof sessao }) {
  const online = useSyncExternalStore(observarConexao, () => navigator.onLine, () => true);
  const pathname = usePathname();
  const router = useRouter();
  const [atualizando, iniciarAtualizacao] = useTransition();
  const naAtivacao = pathname === "/ativar";
  const area = pathname.match(/^(\/eventos\/[^/]+)\/(duplas|pista-ops)(?:\/|$)/);
  const atualizarAutomaticamente = /^(\/eventos\/[^/]+)\/(duplas|pista-ops|x1)$/.test(pathname);
  const vinculo = sessao[tipoSessao];
  const IconeSessao = vinculo.icone;
  const status = online ? "Conexão disponível" : "Sem conexão. Aguarde a confirmação do servidor antes de repetir uma operação.";

  return (
    <aside aria-label="Conexão e sessão do aparelho" className={`print-hidden flex min-h-9 flex-wrap items-center gap-x-1 gap-y-0.5 border-b border-stone-200 px-2 py-0.5 sm:gap-x-2 sm:px-4 ${online ? "bg-stone-50" : "bg-amber-50"}`}>
      <RefreshOnInterval enabled={atualizarAutomaticamente && online} everyMs={15000} />
      <span role="status" title={status} className={`inline-flex items-center gap-1.5 whitespace-nowrap text-xs font-semibold ${online ? "text-emerald-900" : "text-amber-950"}`}>
        <span aria-hidden="true" className={`size-2 shrink-0 rounded-full ${online ? "bg-emerald-600" : "bg-amber-600"}`} />
        <span className="sr-only">{status}</span>
        <span aria-hidden="true" className="sm:hidden">{online ? "Online" : "Sem conexão"}</span>
        <span aria-hidden="true" className="hidden sm:inline">{online ? "Conexão disponível" : "Sem conexão"}</span>
      </span>
      <button type="button" disabled={!online || atualizando} aria-busy={atualizando}
        aria-label={atualizando ? "Atualizando dados" : "Atualizar dados"}
        title={atualizando ? "Atualizando dados" : "Atualizar dados"} className={controle}
        onClick={() => iniciarAtualizacao(() => router.refresh())}>
        <RefreshCw aria-hidden="true" className={`size-4 ${atualizando ? "motion-safe:animate-spin" : ""}`} />
        <span className="hidden sm:inline">{atualizando ? "Atualizando…" : "Atualizar dados"}</span>
      </button>
      {area && <Link href={`${area[1]}/historico?area=${area[2] === "duplas" ? "escritorio" : "locutor"}`}
        className={controle} aria-label="Histórico" title="Histórico">
        <History className="size-4" aria-hidden="true" /><span className="hidden sm:inline">Histórico</span>
      </Link>}
      <div className="ml-auto">
        {naAtivacao && tipoSessao !== "conta" ? (
          <span className="inline-flex min-h-8 items-center gap-1.5 px-2 text-xs font-semibold text-stone-700">
            <IconeSessao className="size-4" aria-hidden="true" />
            {tipoSessao === "aparelho" ? vinculo.texto : "Sem sessão"}
          </span>
        ) : <Link href={vinculo.href} prefetch={false}
          aria-label={`Sessão do aparelho. ${vinculo.texto}. ${vinculo.acao}`} title={`Sessão do aparelho · ${vinculo.acao}`}
          className={`${controle} border border-stone-300 bg-white`}>
          <IconeSessao className="size-4" aria-hidden="true" />
          <span className="sm:hidden">{vinculo.compacto}</span><span className="hidden sm:inline">{vinculo.texto}</span>
        </Link>}
      </div>
    </aside>
  );
}
