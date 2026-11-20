import { AtivarDispositivo } from "./AtivarDispositivo";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";

export default async function AtivarPage({ searchParams }: { searchParams: Promise<{ estado?: string }> }) {
  const { estado } = await searchParams;
  const store = await cookies();
  let context: { nome: string; evento_nome: string } | null = null;
  if (store.has("cv-mobile-device")) {
    const supabase = await createClient();
    const { data } = await supabase.rpc("pista_ops_device_my_context");
    context = data;
  }
  return <AtivarDispositivo estado={estado} context={context} />;
}
