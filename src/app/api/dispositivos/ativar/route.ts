import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

const messages: Record<string, [number, string]> = {
  codigo: [410, "Código de ativação inválido, expirado ou já utilizado. Peça outro ao organizador."],
  evento: [409, "O evento não está disponível para esta função."],
  permissao: [403, "Sua conta não tem esta função no evento. Fale com o organizador."],
  limite: [429, "Muitas tentativas de ativação. Aguarde alguns minutos."],
};

function falha(error: string, status: number) {
  return Response.json({ error }, { status, headers: { "Cache-Control": "no-store" } });
}

export async function POST(request: Request) {
  const url = new URL(request.url);
  const local = process.env.NODE_ENV !== "production" && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (url.protocol !== "https:" && !local) return falha("Abra a ativação pelo endereço HTTPS do sistema.", 403);
  if (request.headers.get("sec-fetch-site") === "cross-site") return falha("Abra a ativação pelo link do sistema.", 403);

  const dados = await request.json().catch(() => null);
  const codigo = typeof dados?.codigo === "string" ? dados.codigo.trim().toUpperCase() : "";
  const email = typeof dados?.email === "string" ? dados.email.trim() : "";
  const senha = typeof dados?.senha === "string" ? dados.senha : "";
  const nome = (typeof dados?.nome === "string" ? dados.nome.trim() : "") || "Celular de operação";
  if (!/^[0-9A-F]{32}$/.test(codigo) || !email || !senha || nome.length > 80) {
    return falha("Informe o código, o email e a senha do operador.", 400);
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
  const conta = createClient(supabaseUrl, supabaseKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data: login, error: loginError } = await conta.auth.signInWithPassword({ email, password: senha });
  if (loginError || !login.user || login.user.is_anonymous) {
    if (loginError?.status === 429) return falha("Muitas tentativas de acesso. Aguarde e tente novamente.", 429);
    if (loginError?.code === "email_not_confirmed") return falha("Confirme seu email antes de ativar.", 403);
    if (loginError?.code === "invalid_credentials") return falha("Email ou senha não reconhecidos.", 401);
    return falha("Não foi possível autenticar sua conta agora. Tente novamente.", 503);
  }

  // Os cookies ficam em memória até a transação confirmar o vínculo.
  const staged: Array<() => void> = [];
  const store = await cookies();
  const options = { httpOnly: true, secure: url.protocol === "https:", sameSite: "lax" as const, path: "/" };
  const dispositivo = createServerClient(supabaseUrl, supabaseKey, {
    cookieOptions: { name: "cv-device-auth", ...options },
    cookies: {
      getAll: () => [],
      setAll: (values) => {
        staged.push(...values.map(({ name, value, options }) => () => store.set(name, value, options)));
      },
    },
  });
  const { data: sessao, error: sessaoError } = await dispositivo.auth.signInAnonymously();
  if (sessaoError || !sessao.user || !sessao.session) {
    return falha("Não foi possível criar a sessão do dispositivo agora.", sessaoError?.status === 429 ? 429 : 503);
  }

  const { data, error } = await conta.rpc("pista_ops_mobile_activate", {
    p_codigo: codigo, p_sessao: sessao.user.id, p_nome: nome,
  });
  if (error) return falha("Não foi possível confirmar a ativação. Tente novamente.", 503);
  if (!data?.id) {
    const [status, message] = messages[data?.erro] ?? [403, "Não foi possível vincular este dispositivo."];
    return falha(message, status);
  }
  for (const cookie of store.getAll()) {
    if (cookie.name === "cv-device-auth" || cookie.name.startsWith("cv-device-auth.")) store.delete(cookie.name);
  }
  staged.forEach((write) => write());
  const sessionCookie = { ...options, maxAge: 60 * 60 * 24 * 30 };
  store.set("cv-device-event", data.evento_id, sessionCookie);
  store.set("cv-device-screen", data.funcao, sessionCookie);
  store.set("cv-mobile-device", "1", sessionCookie);
  return Response.json({ evento_id: data.evento_id, funcao: data.funcao }, { headers: { "Cache-Control": "no-store" } });
}
