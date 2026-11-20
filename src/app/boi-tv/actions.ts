"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const idPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function requireUser() {
  const supabase = await createClient();
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) redirect("/");
  return supabase;
}

export async function updateBoiTvAttendance(formData: FormData) {
  const eventId = String(formData.get("evento_id") ?? "");
  const attendanceId = String(formData.get("atendimento_id") ?? "");
  const status = String(formData.get("estado") ?? "");
  const observation = String(formData.get("observacao") ?? "").trim();
  if (!idPattern.test(eventId) || !idPattern.test(attendanceId)) redirect("/boi-tv");
  const supabase = await requireUser();
  const { error } = await supabase.rpc("pista_ops_boi_tv_atendimento_atualizar", {
    p_atendimento_id: attendanceId,
    p_estado: status,
    p_observacao: observation || null,
  });
  revalidatePath(`/boi-tv/${eventId}`);
  redirect(`/boi-tv/${eventId}?${error ? "erro=atendimento" : "atualizado=1"}`);
}
