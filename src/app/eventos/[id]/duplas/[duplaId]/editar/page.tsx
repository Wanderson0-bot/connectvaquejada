import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { atualizarDupla } from "./actions";

type Props = {
  params: Promise<{ id: string; duplaId: string }>;
  searchParams: Promise<{ erro?: string }>;
};

export default async function EditarDuplaPage({ params, searchParams }: Props) {
  const { id, duplaId } = await params;
  const { erro } = await searchParams;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/");
  }

  const { data: evento, error: erroEvento } = await supabase
    .from("eventos")
    .select("id, nome, parque_id, status_operacional, operacao_temporaria")
    .eq("id", id)
    .maybeSingle();

  if (erroEvento || !evento) {
    notFound();
  }
  const { data: deviceContext } = await supabase.rpc("pista_ops_device_context", { p_evento_id: id });
  if (deviceContext && deviceContext.funcao !== "escritorio") redirect(`/eventos/${id}/pista-ops`);

  const { data: dupla, error: erroDupla } = await supabase
    .from("duplas")
    .select("id, categoria_id, numero_senha, puxador_id")
    .eq("id", duplaId)
    .eq("evento_id", id)
    .maybeSingle();

  if (erroDupla || !dupla) {
    notFound();
  }

  const { data: todasCategorias } = await supabase
    .from("categorias")
    .select("id, nome, ativa")
    .eq("evento_id", id)
    .order("ordem", { ascending: true });
  const categorias = (todasCategorias ?? []).filter((categoria) => categoria.ativa || categoria.id === dupla.categoria_id);

  let competidoresQuery = supabase.from("competidores").select("id, nome, cidade");
  competidoresQuery = evento.operacao_temporaria
    ? competidoresQuery.eq("evento_id", id)
    : competidoresQuery.eq("parque_id", evento.parque_id);
  const { data: competidores } = await competidoresQuery.order("nome", { ascending: true });

  const mensagemErro =
    erro === "campos"
      ? "Selecione a categoria e o puxador, e informe uma senha inteira maior que zero."
      : erro === "categoria"
        ? "Selecione uma categoria deste evento."
        : erro === "puxador"
          ? "Selecione um puxador cadastrado neste parque."
          : erro === "senha-repetida"
            ? "Esta senha já está em uso nesta categoria."
            : erro === "cadastro"
              ? "Não foi possível atualizar a dupla. Tente novamente."
              : null;

  const semDados = !categorias?.length || !competidores?.length;

  return (
    <main className="mx-auto min-h-screen max-w-xl p-8">
      <Link
        href={`/eventos/${id}/duplas`}
        className="text-sm text-gray-600 underline"
      >
        Voltar às duplas
      </Link>

      <h1 className="mt-6 text-2xl font-semibold">Editar dupla</h1>
      <p className="mt-1 text-sm text-gray-600">Evento: {evento.nome}</p>

      {mensagemErro && (
        <p role="alert" className="mt-5 rounded-md bg-red-50 p-3 text-sm text-red-700">
          {mensagemErro}
        </p>
      )}

      { ["pausado", "concluido", "cancelado"].includes(evento.status_operacional) ? (
        <p className="mt-6 rounded-lg border border-amber-200 bg-amber-50 p-5 text-amber-950">As inscrições deste evento estão bloqueadas.</p>
      ) : semDados ? (
        <p className="mt-6 rounded-lg border p-5 text-gray-600">
          É necessário haver ao menos uma categoria no evento e um competidor
          cadastrado no parque para editar esta dupla.
        </p>
      ) : (
        <form action={atualizarDupla} className="mt-6 space-y-4">
          <input type="hidden" name="evento_id" value={id} />
          <input type="hidden" name="dupla_id" value={dupla.id} />

          <label className="block space-y-2">
            <span className="text-sm font-medium">Categoria</span>
            <select
              name="categoria_id"
              defaultValue={dupla.categoria_id}
              required
              className="w-full rounded-md border px-3 py-2"
            >
              <option value="">Selecione</option>
              {categorias!.map((categoria) => (
                <option key={categoria.id} value={categoria.id}>
                  {categoria.nome}
                </option>
              ))}
            </select>
          </label>

          <label className="block space-y-2">
            <span className="text-sm font-medium">Puxador</span>
            <select
              name="puxador_id"
              defaultValue={dupla.puxador_id}
              required
              className="w-full rounded-md border px-3 py-2"
            >
              <option value="">Selecione</option>
              {competidores!.map((competidor) => (
                <option key={competidor.id} value={competidor.id}>
                  {competidor.nome}
                  {competidor.cidade ? ` - ${competidor.cidade}` : ""}
                </option>
              ))}
            </select>
          </label>

          <label className="block space-y-2">
            <span className="text-sm font-medium">Número da senha</span>
            <input
              name="numero_senha"
              type="number"
              min={1}
              step={1}
              defaultValue={dupla.numero_senha}
              required
              className="w-full rounded-md border px-3 py-2"
            />
          </label>

          <button
            type="submit"
            className="rounded-md bg-black px-4 py-2 font-medium text-white"
          >
            Salvar alterações
          </button>
        </form>
      )}
    </main>
  );
}
