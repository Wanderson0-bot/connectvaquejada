import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { ShieldCheck, Clock3, MonitorSmartphone } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { PainelShell } from "@/components/PainelShell";
import { gerarCodigo, gerenciarDispositivo } from "./actions";
import { DeviceQRCode } from "./DeviceQRCode";

type Props = { searchParams: Promise<{ evento?: string; convite?: string; erro?: string; atualizado?: string }> };
type Convite = { evento: string; codigo: string; expira: string; funcao: string; substituindo: boolean };
type Acesso = { id: string; ultimo_acesso_em: string | null };
type Evento = { id: string; nome: string; data: string };
type Device = { id: string; nome: string; funcao: string; estado: string; criado_em: string; identificador_navegador: string };

function formatarAcesso(data?: string | null) {
  return data ? new Date(data).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" }) : "Não registrado";
}

export default async function DispositivosPage({ searchParams }: Props) {
  const query = await searchParams;
  const configuredAddress = process.env.DEVICE_ACTIVATION_ORIGIN ?? "";
  const configuredOrigin = URL.canParse(configuredAddress) ? new URL(configuredAddress) : undefined;
  const activationOrigin = configuredOrigin && configuredOrigin.protocol === "https:"
    ? configuredOrigin.origin
    : undefined;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const { data } = await supabase.rpc("pista_ops_device_admin_events");
  const eventos = (data ?? []) as Evento[];
  const selected = eventos.find((item) => item.id === query.evento) ?? eventos[0];
  let convite: Convite | undefined;
  const rawInvite = (await cookies()).get("cv-mobile-invite")?.value;
  if (query.convite && rawInvite) {
    try {
      const item: Convite = JSON.parse(rawInvite);
      if (item.evento === selected?.id && /^[0-9A-F]{32}$/.test(item.codigo) && Number.isFinite(Date.parse(item.expira))) convite = item;
    } catch { /* Convite descartado. */ }
  }
  let devices: Device[] = [];
  let acessos: Acesso[] = [];
  if (selected) {
    const [{ data: deviceRows }, { data: accessRows }] = await Promise.all([
      supabase.rpc("pista_ops_devices_list", { p_evento_id: selected.id }),
      supabase.rpc("pista_ops_mobile_acessos", { p_evento_id: selected.id }),
    ]);
    acessos = (accessRows ?? []) as Acesso[];
    devices = (deviceRows ?? []) as Device[];
  }

  return <PainelShell active="dispositivos">
    <header className="dashboard-header"><div><h1 className="dashboard-title">Dispositivos autorizados</h1><p className="dashboard-description">Escolha uma operação ativa e libere Escritório ou Locução por QR code ou código temporário.</p></div></header>
    {query.erro && <p role="alert" className="mb-5 rounded-lg bg-red-50 p-4 text-sm text-red-800">Não foi possível concluir. Confirme sua permissão de organizador e os dados informados.</p>}
    {query.atualizado && <p role="status" className="mb-5 rounded-lg bg-emerald-50 p-4 text-sm text-emerald-900">O dispositivo foi atualizado.</p>}
    {!eventos.length ? <section className="rounded-2xl bg-white p-8 shadow"><p>Inicie uma operação no Painel para liberar dispositivos.</p></section> : <>
      <section className="mb-6 rounded-2xl bg-white p-6 shadow-lg shadow-orange-950/5">
        <h2 className="mb-4 flex items-center gap-2 text-xl font-semibold text-stone-900"><ShieldCheck className="size-5 text-orange-700" /> Conectar celular</h2>
        <form method="get" className="mb-4"><label htmlFor="evento-picker" className="mb-2 block text-sm font-medium text-stone-700">Operação ativa</label><div className="flex flex-wrap gap-2"><select id="evento-picker" name="evento" defaultValue={selected?.id} className="w-full rounded-lg border border-stone-300 p-3 sm:max-w-lg">{eventos.map((evento) => <option key={evento.id} value={evento.id}>{evento.nome}</option>)}</select><button className="rounded-lg border border-stone-300 px-4 py-2 font-medium">Selecionar</button></div></form>
        {selected && <div className="flex flex-wrap gap-3">
          {([['locutor','Liberar locução'],['escritorio','Liberar escritório'],['boi_tv','Liberar equipe BOI TV']] as const).map(([role,label]) => <form action={gerarCodigo} key={role}><input type="hidden" name="evento_id" value={selected!.id} /><input type="hidden" name="funcao" value={role} /><button className="rounded-lg bg-orange-700 px-5 py-3 font-semibold text-white hover:bg-orange-800">{label}</button></form>)}
        </div>}
        {convite?.codigo && <div className="mt-6 rounded-xl border border-orange-200 bg-orange-50 p-5" aria-live="polite"><p className="text-sm font-semibold text-orange-950">{convite.substituindo ? "Código para substituir dispositivo" : "Código de ativação"} · {convite.funcao === "locutor" ? "Locução" : convite.funcao === "boi_tv" ? "Equipe BOI TV" : "Escritório"}</p><div className="mt-4 flex flex-wrap items-center gap-5"><div className="rounded-xl bg-white p-2 shadow-sm"><DeviceQRCode code={convite.codigo} activationOrigin={activationOrigin} /></div><div className="min-w-56 flex-1"><p className="text-sm text-stone-700">Leia o QR code com a câmera do outro aparelho para abrir a ativação com o código preenchido. Se preferir, informe o código manualmente em <strong>/ativar</strong>.</p><p className="my-3 break-all font-mono text-base font-bold tracking-wide text-orange-900">{convite.codigo}</p><p className="text-sm text-stone-700">O código é de uso único. O operador precisa entrar com sua conta. O acesso anterior será revogado ao concluir a substituição.</p><p className="mt-2 flex items-center gap-2 text-xs text-stone-600"><Clock3 className="size-4" /> Expira {formatarAcesso(convite.expira)}</p></div></div></div>}
      </section>
      <section className="rounded-2xl bg-white p-6 shadow-lg shadow-orange-950/5"><h2 className="mb-4 flex items-center gap-2 text-xl font-semibold text-stone-900"><MonitorSmartphone className="size-5 text-orange-700" /> Dispositivos de {selected?.nome}</h2>
        {!selected ? <p className="text-stone-600">Selecione uma operação ativa acima.</p> : !devices.length ? <p className="text-stone-600">Ainda não há dispositivos autorizados nesta operação.</p> : <div className="grid gap-3">{devices.map((device) => <article key={device.id} className="flex flex-wrap items-center justify-between gap-4 rounded-xl border border-stone-200 p-4"><div><h3 className="font-semibold text-stone-900">{device.nome}</h3><p className="mt-1 text-sm text-stone-600">{device.funcao === "locutor" ? "Locução" : device.funcao === "boi_tv" ? "BOI TV" : "Escritório"} · {device.estado} · autorizado em {new Date(device.criado_em).toLocaleString("pt-BR")}</p><p className="mt-1 text-xs text-stone-500">Último acesso: {formatarAcesso(acessos.find((item) => item.id === device.id)?.ultimo_acesso_em)}</p></div><div className="flex flex-wrap gap-2">{device.estado !== "revogado" && <form action={gerarCodigo}><input type="hidden" name="evento_id" value={selected!.id} /><input type="hidden" name="funcao" value={device.funcao} /><input type="hidden" name="substitui_id" value={device.id} /><button className="rounded-md border border-orange-300 px-3 py-2 text-sm font-medium text-orange-900 hover:bg-orange-50">Substituir</button></form>}{(device.estado === "ativo" ? [["bloquear","Bloquear"],["revogar","Revogar"]] : device.estado === "bloqueado" ? [["reativar","Reativar"],["revogar","Revogar"]] : []).map(([action,label]) => <form action={gerenciarDispositivo} key={action}><input type="hidden" name="id" value={device.id} /><input type="hidden" name="acao" value={action} /><button className="rounded-md border border-stone-300 px-3 py-2 text-sm font-medium hover:bg-stone-50">{label}</button></form>)}</div></article>)}</div>}
      </section>
    </>}
  </PainelShell>;
}
