"use client";

import { useState, useSyncExternalStore, type FormEvent } from "react";
import { Smartphone, ShieldCheck } from "lucide-react";
import { sairDoAparelho } from "./actions";

function observarCodigo(listener: () => void) {
  window.addEventListener("hashchange", listener);
  return () => window.removeEventListener("hashchange", listener);
}

function lerCodigo() {
  const codigo = new URLSearchParams(window.location.hash.slice(1)).get("codigo") ?? "";
  return /^[0-9A-F]{32}$/i.test(codigo) ? codigo.toUpperCase() : "";
}

export function AtivarDispositivo({ estado, context }: { estado?: string; context: { nome: string; evento_nome: string } | null }) {
  const code = useSyncExternalStore(observarCodigo, lerCodigo, () => "");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  async function activate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError("");
    const fields = Object.fromEntries(new FormData(event.currentTarget));
    try {
      const response = await fetch("/api/dispositivos/ativar", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(fields) });
      const result = await response.json();
      if (!response.ok) {
        setError(typeof result?.error === "string" ? result.error : "Não foi possível ativar este dispositivo.");
        return;
      }
      window.location.replace(result.funcao === "escritorio" ? `/eventos/${result.evento_id}/duplas` : result.funcao === "boi_tv" ? `/boi-tv/${result.evento_id}` : `/eventos/${result.evento_id}/pista-ops`);
    } catch {
      setError("Não foi possível concluir a ativação. Confira a conexão e tente novamente.");
    }
    finally { setBusy(false); }
  }
  return <main className="flex min-h-screen items-center justify-center bg-[#f8f4f0] px-4 py-8">
    <section className="w-full max-w-md rounded-3xl bg-white p-7 shadow-2xl shadow-stone-900/10 sm:p-9">
      <div className="mb-5 grid size-12 place-items-center rounded-2xl bg-orange-100 text-orange-800"><Smartphone /></div>
      <h1 className="text-2xl font-bold text-stone-900">Autorizar dispositivo</h1>
      <p className="mt-2 text-sm leading-6 text-stone-600">Informe o código para abrir o evento na função definida pelo organizador.</p>
      {estado === "sessao" && <p role="status" className="mt-4 rounded-lg bg-amber-50 p-3 text-sm text-amber-900">O vínculo deste aparelho expirou ou foi encerrado. Peça um novo QR Code ao organizador.</p>}
      {estado === "saiu" && <p role="status" className="mt-4 text-sm text-stone-700">Sessão do aparelho encerrada.</p>}
      {estado === "erro-saida" && <p role="alert" className="mt-4 text-sm text-red-800">Não foi possível confirmar o encerramento da sessão. Tente novamente.</p>}
      {context && <form action={sairDoAparelho} className="mt-4 rounded-lg bg-stone-100 p-3">
        <p className="text-sm"><strong>{context.nome}</strong> · {context.evento_nome}</p>
        <button className="operation-secondary mt-2">Encerrar sessão do aparelho</button>
      </form>}
      <form onSubmit={activate} className="mt-6 grid gap-4">
        <label className="auth-field"><span className="auth-label">Código de ativação</span><input key={code} name="codigo" required autoComplete="one-time-code" minLength={32} maxLength={32} defaultValue={code} className="auth-input px-3! font-mono uppercase" /></label>
        <label className="auth-field"><span className="auth-label">Nome do aparelho (opcional)</span><input name="nome" maxLength={80} className="auth-input px-3!" placeholder="Tablet da locução" /></label>
        {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{error}</p>}
        <button disabled={busy} className="mt-1 inline-flex items-center justify-center gap-2 rounded-lg bg-orange-800 px-5 py-3 font-semibold text-white hover:bg-orange-900 disabled:opacity-50"><ShieldCheck className="size-5" />{busy ? "Autorizando…" : "Autorizar e abrir painel"}</button>
      </form>
    </section>
  </main>;
}
