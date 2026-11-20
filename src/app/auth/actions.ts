"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function autenticar(formData: FormData) {
  const campoEmail = formData.get("email");
  const senha = formData.get("senha");
  const email = typeof campoEmail === "string" ? campoEmail.trim() : "";
  if (!email || typeof senha !== "string" || !senha) {
    return { error: "Preencha o email e a senha." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password: senha });

  if (error?.code === "invalid_credentials") {
    return { error: "Email ou senha não reconhecidos neste ambiente." };
  }
  if (error?.code === "email_not_confirmed") {
    return { error: "Confirme seu email antes de entrar. Confira sua caixa de entrada." };
  }
  if (error?.status === 429) {
    return { error: "Muitas tentativas de acesso. Aguarde alguns minutos e tente novamente." };
  }
  if (error || !data.session) {
    return { error: "O serviço de autenticação não conseguiu iniciar a sessão. Tente novamente em instantes." };
  }
  return { error: null };
}

export async function sair() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}
