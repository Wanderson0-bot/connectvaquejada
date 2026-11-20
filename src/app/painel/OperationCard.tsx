import Link from "next/link";
import { CalendarDays, ChevronDown, Clock3, HardDrive, Mic, Settings2, StopCircle, Tag, Ticket, Users } from "lucide-react";
import { ConfirmForm } from "@/components/ConfirmForm";
import { configurarMembroOperacao, encerrarOperacao } from "./operacoes/actions";
import { CopyEventIdButton } from "./CopyEventIdButton";

type Member = { id: string; usuario_id: string; funcao: string };
type Operation = {
  id: string;
  nome: string;
  data: string;
  formato_competicao: string;
  status_operacional: string;
  quantidade_inscricoes: number;
  quantidade_dispositivos: number;
  membros: Member[];
  membrosError: boolean;
  categorias: string[];
  iniciadoEm: string | null;
};

function startTime(value: string | null) {
  if (!value) return "Horário não disponível";
  return new Intl.DateTimeFormat("pt-BR", {
    hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo",
  }).format(new Date(value));
}

export function OperationCard({ operation }: { operation: Operation }) {
  const active = operation.status_operacional === "em_andamento";
  return <article className="operation-card">
    <div className="flex flex-col gap-4 p-5 sm:p-6 xl:flex-row xl:items-start xl:justify-between">
      <div className="min-w-0 flex-1">
        <span className={`inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-bold ${active ? "bg-emerald-50 text-emerald-800" : "bg-stone-100 text-stone-600"}`}>
          <span className={`size-2 rounded-full ${active ? "bg-emerald-600" : "bg-stone-400"}`} />
          {active ? "Ativa" : "Encerrada"}
        </span>
        <h3 className="mt-3 break-words text-2xl font-bold tracking-tight text-stone-950">{operation.nome}</h3>
        <p className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-stone-600">
          <CalendarDays className="size-4 shrink-0 text-stone-500" aria-hidden="true" />
          <span>{new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(`${operation.data}T00:00:00Z`))}</span>
          <span aria-hidden="true">·</span>
          <Clock3 className="size-4 shrink-0 text-stone-500" aria-hidden="true" />
          <span>Início às {startTime(operation.iniciadoEm)}</span>
        </p>
        <p className="mt-2 text-sm font-semibold text-stone-700">
          Formato: {operation.formato_competicao === "tropa_de_elite" ? "Tropa de Elite · eliminatória" : operation.formato_competicao === "tradicional" ? "Tradicional · classificatória" : "Não identificado"}
        </p>
      </div>

      <div className="w-full rounded-xl border border-stone-200 bg-stone-50 p-3 xl:max-w-64">
        <p className="text-[11px] font-bold uppercase tracking-wider text-stone-500">Identificador da vaquejada</p>
        <div className="mt-2 flex items-start gap-2">
          <code className="min-w-0 flex-1 break-all font-mono text-xs leading-5 text-stone-800">{operation.id}</code>
          <CopyEventIdButton value={operation.id} />
        </div>
      </div>
    </div>

    <div className="operation-metrics mx-5 grid grid-cols-1 divide-y divide-stone-200 rounded-xl px-3 sm:mx-6 sm:grid-cols-3 sm:divide-x sm:divide-y-0 sm:px-4">
      <div className="flex min-w-0 items-center gap-3 py-4 sm:pr-4">
        <span className="operation-icon"><Users className="size-4" aria-hidden="true" /></span>
        <div><p className="text-xs text-stone-500">Inscrições</p><p className="text-lg font-bold text-stone-900">{operation.quantidade_inscricoes}</p></div>
      </div>
      <div className="flex min-w-0 items-center gap-3 py-4 sm:px-4">
        <span className="operation-icon"><HardDrive className="size-4" aria-hidden="true" /></span>
        <div><p className="text-xs text-stone-500">Dispositivos autorizados</p><p className="text-lg font-bold text-stone-900">{operation.quantidade_dispositivos}</p></div>
      </div>
      <div className="flex min-w-0 items-center gap-3 py-4 sm:pl-4">
        <span className="operation-icon"><Tag className="size-4" aria-hidden="true" /></span>
        <div className="min-w-0"><p className="text-xs text-stone-500">Categoria</p><p className="break-words text-sm font-bold text-stone-900">{operation.categorias.length ? operation.categorias.join(", ") : "Não informada"}</p></div>
      </div>
    </div>

    <div className="p-5 sm:p-6">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Link href={`/painel/operacoes/${operation.id}`} className="operation-secondary"><Settings2 className="size-4" aria-hidden="true" /> Administrar</Link>
        <Link href={`/eventos/${operation.id}/duplas`} className="operation-secondary"><Ticket className="size-4" aria-hidden="true" /> Escritório</Link>
        <Link href={operation.formato_competicao === "tropa_de_elite" ? `/eventos/${operation.id}/x1` : operation.formato_competicao === "tradicional" ? `/eventos/${operation.id}/pista-ops` : `/eventos/${operation.id}`} className="operation-primary"><Mic className="size-4" aria-hidden="true" /> {operation.formato_competicao === "tropa_de_elite" ? "Eliminatória" : operation.formato_competicao === "tradicional" ? "Locução" : "Ver evento"}</Link>
      </div>

      <div className="mt-4 flex flex-col gap-3 rounded-xl border border-amber-200 bg-amber-50/70 p-3 sm:flex-row sm:items-center sm:justify-between sm:px-4">
        <p className="text-sm text-amber-950">Ação de atenção · encerra esta operação e bloqueia novos acessos.</p>
        <ConfirmForm action={encerrarOperacao} message="Encerrar esta operação? Novos cadastros, chamadas e acessos dos dispositivos serão bloqueados." className="shrink-0">
          <input type="hidden" name="operacao_id" value={operation.id} />
          <button className="inline-flex min-h-11 items-center justify-center gap-2 rounded-lg border border-amber-400 bg-white px-4 py-2 text-sm font-bold text-amber-950 transition hover:bg-amber-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-700">
            <StopCircle className="size-4" aria-hidden="true" /> Encerrar operação
          </button>
        </ConfirmForm>
      </div>

      <details className="group mt-5 overflow-hidden rounded-xl border border-stone-200 bg-stone-50/70">
        <summary className="flex cursor-pointer list-none items-center justify-between gap-4 p-4 marker:hidden focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-red-800 [&::-webkit-details-marker]:hidden">
          <span className="flex min-w-0 items-start gap-3">
            <Users className="mt-0.5 size-5 shrink-0 text-red-900" aria-hidden="true" />
            <span><span className="block font-bold text-stone-900">Membros e funções do evento</span><span className="mt-1 block text-sm font-normal text-stone-600">Consulte os usuários, permissões e funções ativas nesta vaquejada.</span></span>
          </span>
          <ChevronDown className="size-5 shrink-0 text-stone-500 transition-transform group-open:rotate-180" aria-hidden="true" />
        </summary>
        <div className="space-y-5 border-t border-stone-200 bg-white p-4 sm:p-5">
          {operation.membrosError ? <p role="alert" className="text-sm leading-relaxed text-red-700">Não foi possível carregar os membros desta operação.</p> : <>
            <p className="text-sm leading-relaxed text-stone-600">Informe o UUID de um perfil do mesmo parque para conceder ou revogar uma função.</p>
            <ConfirmForm action={configurarMembroOperacao} message="Aplicar a função informada? Revogações serão registradas no histórico." className="grid gap-4 md:grid-cols-2 md:items-end xl:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)_auto]">
              <input type="hidden" name="operacao_id" value={operation.id} />
              <label className="grid min-w-0 gap-2 text-sm font-medium">ID do perfil no mesmo parque
                <input name="usuario_id" required maxLength={36} inputMode="text" placeholder="UUID do perfil" className="h-11 w-full min-w-0 rounded-md border border-stone-300 px-3" />
              </label>
              <label className="grid min-w-0 gap-2 text-sm font-medium">Função
                <select name="funcao" required className="h-11 w-full min-w-0 rounded-md border border-stone-300 px-3"><option value="organizador">Organizador</option><option value="escritorio">Escritório</option><option value="locutor">Locutor</option></select>
              </label>
              <label className="grid min-w-0 gap-2 text-sm font-medium">Acesso
                <select name="ativo" className="h-11 w-full min-w-0 rounded-md border border-stone-300 px-3"><option value="true">Ativo</option><option value="false">Revogar</option></select>
              </label>
              <button className="inline-flex min-h-11 items-center justify-center rounded-md bg-red-950 px-5 py-2 text-sm font-semibold text-white hover:bg-red-900 md:col-span-2 md:justify-self-start xl:col-span-1 xl:justify-self-stretch">Aplicar função</button>
            </ConfirmForm>
            <ul className="divide-y divide-stone-200 border-y border-stone-200">
              {operation.membros.map((member) => <li key={member.id} className="flex flex-wrap items-start justify-between gap-x-6 gap-y-2 py-4 text-sm"><span className="min-w-0 break-all text-stone-700">{member.usuario_id}</span><span className="shrink-0 font-medium text-stone-900">{member.funcao}</span></li>)}
              {operation.membros.length === 0 && <li className="py-4 text-sm text-stone-600">Nenhum membro ativo.</li>}
            </ul>
          </>}
        </div>
      </details>
    </div>
  </article>;
}
