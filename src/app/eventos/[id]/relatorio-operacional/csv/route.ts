import { carregarSupervisao } from "@/lib/supervisao/servidor";
import { gerarCsvOperacional } from "@/lib/supervisao/csv";

export async function GET(_request: Request, { params }: RouteContext<"/eventos/[id]/relatorio-operacional/csv">) {
  const { id } = await params;
  const dados = await carregarSupervisao(id, null, true);
  return new Response(gerarCsvOperacional(dados), {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="relatorio-operacional-${id}.csv"`,
      "Cache-Control": "private, no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
