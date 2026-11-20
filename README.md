# Connect Vaquejada

Sistema para gestão de parques e operação de vaquejadas, com inscrições, rodízios, locução e atendimento BOI TV.

## Executar localmente

Configure `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY` no arquivo `.env.local`. Em seguida, execute:

```bash
npm install
npm run dev
```

Acesse [o servidor local](http://localhost:3000). Para preparar o primeiro evento, consulte o [roteiro do piloto no parque](./roteiro-piloto.md).

## Operação pelo Windows e pelo celular

### Auditoria e arquitetura

O aplicativo Windows usa Electron e executa o servidor Next.js em `127.0.0.1`. A versão web reutiliza as mesmas páginas, ações de servidor e migrações. As funções exclusivas do Electron são iniciar o servidor local, abrir a janela e encaminhar o link de ativação ao navegador. Inscrições, competidores, locução e resultados usam a camada compartilhada do Supabase.

As tabelas existentes incluem `eventos`, `categorias`, `competidores`, `duplas`, `pista_ops_members`, `pista_ops_runs`, `x1_bois`, `pista_ops_device_codes` e `pista_ops_devices`. As permissões operacionais reutilizam RLS e as funções do banco. A central BOI TV já usa atualizações por eventos de servidor, com atualização periódica em caso de indisponibilidade.

Antes desta mudança, a posse do código bastava para vincular um dispositivo e o banco armazenava o código em texto simples. Os novos convites exigem credenciais de uma conta com função autorizada no evento. O banco guarda apenas o hash do convite, consome-o em transação única e limita a dez tentativas por conta em dez minutos. A conta fica registrada para auditoria. A sessão no aparelho usa uma identidade separada, limitada a um evento e a uma função.

As migrações preservam vínculos existentes e as RPCs usadas pelo instalador anterior. Convites antigos de 12 caracteres precisam ser substituídos para uso pela nova página de ativação. Escritório e locução por dispositivo continuam disponíveis nas operações temporárias. Na central BOI TV, o vínculo autenticado exige uma conta de organizador no evento, pois o modelo existente não possui uma função de membro BOI TV.

### Publicar uma versão de homologação

1. Vincule o diretório a um projeto Vercel com o framework Next.js. Use as rotas nativas do App Router e mantenha o modo standalone reservado ao instalador.
2. Em um Supabase de homologação com o esquema anterior aplicado, aplique `202611200001_ativacao_celular_autenticada.sql` e `202611200002_autoria_e_concorrencia_celular.sql`, nessa ordem. Mantenha o login por email e senha e a opção de login anônimo do Supabase Auth para as sessões de aparelho.
3. Configure na Vercel a URL `NEXT_PUBLIC_SUPABASE_URL` e a chave pública `NEXT_PUBLIC_SUPABASE_ANON_KEY` do mesmo projeto Supabase usado no aplicativo Windows desse ambiente. O prazo é opcional em `DEVICE_ACTIVATION_TTL_MINUTES` e aceita de 1 a 60 minutos, com padrão de 10 minutos. A chave `service_role` não é necessária no aplicativo nem no build.
4. Gere a implantação de homologação com `vercel deploy`. Confirme pelo navegador do celular que a URL HTTPS permite abrir `/` e `/ativar` sem uma conta Vercel. Quando houver domínio definitivo, configure-o como Site URL no Supabase Auth. Autorize somente URLs de retorno efetivamente usadas por convites de conta ou recuperação de senha. O login por senha e a ativação do aparelho já implementados não usam um redirecionamento do Supabase.
5. Configure `DESKTOP_ACTIVATION_ORIGIN` no build Windows com a URL HTTPS verificada. Opcionalmente, configure `DEVICE_ACTIVATION_ORIGIN` na Vercel para usar um domínio canônico nos QR Codes gerados pela web.

[Implantação pela CLI da Vercel](https://vercel.com/docs/projects/deploy-from-cli) · [Variáveis de ambiente da Vercel](https://vercel.com/docs/environment-variables)

### Ativar, operar e revogar

1. No painel Windows ou web, abra **Dispositivos → Conectar celular**, selecione uma operação ativa e gere o convite da função.
2. Escaneie o QR Code no telefone e entre com a conta do operador. O código segue no fragmento do link e é enviado ao servidor somente no formulário de ativação. Mantenha a internet disponível durante operações de escrita.
3. A conta pode operar inscrições, locução ou BOI TV conforme o vínculo. Use **Atualizar dados** para conferir alterações de outro aparelho. A central BOI TV mantém as atualizações automáticas que já existiam.
4. Em **Dispositivos**, use **Bloquear** para suspender ou **Revogar** para encerrar o vínculo. A retirada da função do operador ou do organizador que concedeu o vínculo também encerra o acesso correspondente. O celular pode encerrar o próprio vínculo em **Sessão do aparelho**.

### Verificação

Execute `npm run build`, `npm run lint`, `node --test --experimental-strip-types src/lib/pista-ops/domain.test.mjs` e as suítes em `supabase/tests` num banco de teste. Para homologar a implantação, opere um evento fictício com um Windows e um celular, teste senha repetida, uma corrida X1 vista por dois operadores, bloqueio do telefone e retomada após desligar e religar a internet. Em X1, a interface atual envia o número do boi esperado para o servidor rejeitar um lançamento simultâneo na mesma posição.

## Formatos de competição

Eventos e operações temporárias podem usar o formato **Tradicional** ou **Tropa de Elite**. A categoria Tropa de Elite continua disponível independentemente do formato escolhido para o evento.

No formato Tropa de Elite, a disputa começa pelo chaveamento eliminatório, com um boi por competidor em cada confronto. Em caso de empate, a disputa vai para a morte súbita. Aplique as migrações do Supabase, incluindo `202611160005_formato_tropa_de_elite.sql`, antes de usar o formato.

## Compilação e implantação

Execute `npm run build` para compilar e `npm run start` para iniciar o servidor de produção. Consulte a [documentação de implantação do Next.js](https://nextjs.org/docs/app/getting-started/deploying).

## Aplicativo para Windows

Com o Supabase configurado no `.env.local`, execute `npm ci --prefix desktop` e depois `npm run desktop:build`. O instalador para Windows x64 é gerado em `release/`. O aplicativo abre o painel em uma janela própria e usa a internet para acessar o Supabase.

Para ativar dispositivos pelo QR Code gerado no aplicativo, defina `DESKTOP_ACTIVATION_ORIGIN` no `.env.local` com a URL HTTPS da versão web vinculada ao mesmo projeto Supabase antes de gerar o instalador.
