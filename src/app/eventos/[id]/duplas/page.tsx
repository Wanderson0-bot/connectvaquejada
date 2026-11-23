import { Voltar } from "@/components/Voltar";
import Link from "next/link";
import Image from "next/image";
import { notFound, redirect } from "next/navigation";
import { MapPin } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { ListaInscricoes, type Inscricao } from "./ListaInscricoes";
import { FormularioInscricao } from "./nova/FormularioInscricao";
import { ImportarInscricoesCsv } from "./ImportarInscricoesCsv";
import { CategoriasEscritorio } from "./CategoriasEscritorio";
import styles from "./escritorio.module.css";

type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ erro?: string; sucesso?: string; categoria?: string }> };
export default async function DuplasPage({ params, searchParams }: Props) {
  const { id } = await params;
  const { erro, sucesso, categoria } = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/");
  const { data: evento } = await supabase.from("eventos").select("id,nome,data,parque_id,status_operacional,operacao_temporaria").eq("id",id).maybeSingle();
  if (!evento) notFound();
  const { data: deviceContext } = await supabase.rpc("pista_ops_device_context", { p_evento_id: id });
  if (deviceContext && deviceContext.funcao !== "escritorio") redirect(`/eventos/${id}/pista-ops`);
  const { data: parque } = evento.parque_id ? await supabase.from("parques").select("nome").eq("id",evento.parque_id).maybeSingle() : { data: null };
  let competitorQuery = supabase.from("competidores").select("id,nome");
  competitorQuery = evento.operacao_temporaria ? competitorQuery.eq("evento_id",id) : competitorQuery.eq("parque_id",evento.parque_id);
  const [{ data: categorias }, { data: duplas, error: erroDuplas }, { data: competidores }] = await Promise.all([
    supabase.from("categorias").select("id,nome,ordem,valor_inscricao,ativa,modelo_competicao").eq("evento_id",id).order("ordem",{ascending:true}),
    supabase.from("duplas").select("id,numero_senha,status_pagamento,motivo_isencao,categoria_id,puxador_id,nome_cavalo,nome_equipe").eq("evento_id",id).neq("status_pagamento","cancelado").order("numero_senha",{ascending:true}),
    competitorQuery,
  ]);
  const nomeCategoria = new Map((categorias ?? []).map((item) => [item.id,item.nome]));
  const nomeCompetidor = new Map((competidores ?? []).map((item) => [item.id,item.nome]));
  const inscricoes: Inscricao[] = (duplas ?? []).map((dupla) => ({ id:dupla.id, competidorId:dupla.puxador_id, numeroSenha:dupla.numero_senha, categoria:nomeCategoria.get(dupla.categoria_id) ?? "Categoria", competidor:nomeCompetidor.get(dupla.puxador_id) ?? "-", nomeCavalo:dupla.nome_cavalo ?? null, nomeEquipe:dupla.nome_equipe ?? null, statusPagamento:dupla.status_pagamento, motivoIsencao:dupla.motivo_isencao }));
  const bloqueado = ["pausado","concluido","cancelado"].includes(evento.status_operacional);
  const mensagemErro = erro === "campos" ? "Confira o nome, a senha e o status do pagamento. Para isenção, informe o motivo." : erro === "senha-repetida" ? "Este número de senha já está em uso nesta categoria." : erro === "status" ? "Selecione um status de pagamento válido." : erro === "motivo" ? "Informe o motivo da isenção." : erro === "pagamento" ? "Não foi possível atualizar o pagamento." : erro === "categoria" ? "Não foi possível salvar a categoria." : erro === "categoria-em-uso" ? "Esta categoria possui inscrições ou dados relacionados; ela não foi excluída." : erro === "inscricao-excluir" ? "Não foi possível excluir esta inscrição." : null;
  return <main className={styles.page}>
    <div className={styles.content}>
      {!user.is_anonymous && !deviceContext && <Voltar />}
      <header className={styles.header}>
        <Link href={`/eventos/${id}/duplas`} aria-label="Atualizar escritório" className={styles.brand}>
          <Image src="/logo-connect-vaquejada.png" alt="Connect Vaquejada" width={180} height={92} priority className={styles.logo} />
        </Link>
        <div className={styles.location}><MapPin aria-hidden="true" className={styles.locationIcon} /><span>{parque?.nome ?? evento.nome}</span></div>
      </header>

      {bloqueado && <p role="status" className={`${styles.notice} ${styles.noticePaused}`}>{evento.status_operacional === "pausado" ? "Vaquejada pausada. Inscrições e alterações de pagamento estão temporariamente bloqueadas." : evento.status_operacional === "cancelado" ? "Vaquejada anulada. As inscrições foram canceladas e removidas desta lista." : "Vaquejada concluída. As inscrições estão encerradas."}</p>}
      {mensagemErro && <p role="alert" className={`${styles.notice} ${styles.noticeError}`}>{mensagemErro}</p>}
      {sucesso === "inscricao" && <p role="status" className={`${styles.notice} ${styles.noticeSuccess}`}>Inscrição salva com sucesso.</p>}
      {sucesso === "pagamento" && <p role="status" className={`${styles.notice} ${styles.noticeSuccess}`}>Pagamento atualizado com sucesso.</p>}
      {sucesso === "inscricao-excluida" && <p role="status" className={`${styles.notice} ${styles.noticeSuccess}`}>Inscrição cancelada e removida da lista; o histórico foi preservado.</p>}
      {sucesso === "categoria" && <p role="status" className={`${styles.notice} ${styles.noticeSuccess}`}>Categoria adicionada à operação.</p>}
      {sucesso === "categoria-oculta" && <p role="status" className={`${styles.notice} ${styles.noticeSuccess}`}>Categoria ocultada para novas inscrições; o histórico foi preservado.</p>}
      {sucesso === "categoria-editada" && <p role="status" className={`${styles.notice} ${styles.noticeSuccess}`}>Categoria atualizada.</p>}
      {sucesso === "categoria-reativada" && <p role="status" className={`${styles.notice} ${styles.noticeSuccess}`}>Categoria reativada para novas inscrições.</p>}
      {sucesso === "categoria-excluida" && <p role="status" className={`${styles.notice} ${styles.noticeSuccess}`}>Categoria excluída.</p>}
      {!bloqueado && categoria === "novo" && <CategoriasEscritorio eventoId={id} categorias={categorias ?? []} aberto erro={erro?.startsWith("categoria") ? erro : undefined} sucesso={sucesso} />}

      {!bloqueado && (categorias?.some((item) => item.ativa)
        ? <>
            <FormularioInscricao eventoId={id} categorias={categorias.filter((item) => item.ativa)} permiteGerenciarCategorias />
            <ImportarInscricoesCsv eventoId={id} categorias={categorias.filter((item) => item.ativa).map(({ id: categoriaId, nome }) => ({ id: categoriaId, nome }))} />
          </>
        : <p className={`${styles.card} ${styles.notice}`}>Cadastre uma categoria para receber inscrições. <Link href={`/eventos/${id}/duplas?categoria=novo`} className="ml-2 font-semibold text-orange-800 underline">Gerenciar categorias</Link></p>)}

      {erroDuplas
        ? <p role="alert" className={`${styles.notice} ${styles.noticeError}`}>Não foi possível carregar a lista de inscrições.</p>
        : <ListaInscricoes eventoId={id} eventoNome={evento.nome} eventoData={evento.data} parqueNome={parque?.nome ?? evento.nome} inscricoes={inscricoes} somenteLeitura={bloqueado} />}
    </div>
  </main>;
}
