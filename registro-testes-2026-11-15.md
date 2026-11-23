# Registro de execução — Connect Vaquejada

Data: 15/11/2026 (America/Sao_Paulo)

## Resultado

**Bateria não iniciada.** Nenhum evento, competidor, inscrição, categoria, rodízio, operação de pista, chamada de locução, resultado, atendimento BOI TV ou partida X1 foi criado ou alterado nesta tentativa.

## Bloqueios observados

- A ferramenta de interface informou que o host de acesso ao navegador estava indisponível (`Browsers: Error: The browser access host is unavailable`).
- A janela do Microsoft Edge identificada no inventário não pôde ser inspecionada: a chamada de acesso expirou (`Computer Use app approval timed out`).
- O workspace não contém o plano de teste referido nem os nomes definidos para os três eventos. A busca por arquivos e referências a plano/teste não localizou esse conteúdo.
- Sem a interface e os nomes do plano, não foi possível executar ou confirmar gravações. Portanto, não há evidência de operações salvas.

## Integridade do workspace

A inspeção inicial de `git status --short` já mostrava alterações e arquivos não rastreados em várias áreas do projeto antes desta execução. Não foram modificados esses itens. Este registro é o único arquivo criado nesta tentativa.

## Escopo pendente

Retomar a execução integral autorizada quando a interface puder ser aberta e o plano (incluindo os nomes dos três eventos) estiver disponível. Identificar todo dado criado com `TESTE`; preservar dados preexistentes; não executar exclusões em massa, mudar configurações globais, enviar comunicações externas ou efetuar cobranças.

## Retomada — 16/11/2026

**Bateria parcial; somente a primeira operação de teste foi criada.** O usuário esclareceu que o PDF não integra o plano e autorizou que os nomes fossem definidos para os testes. O usuário autenticou-se diretamente na interface.

### Estado observado

- A tela do Connect Vaquejada abriu em `http://localhost:3000/painel`.
- O painel exibe a operação preexistente `1ª Vaquejada Teste`, identificador `8ebecb8e-e134-41f3-8532-0c35a5566699`, com 1 inscrição, 0 dispositivos autorizados e categoria `Geral`. Não foi aberta nem alterada.
- A rota `/eventos` retorna 404; o painel `/painel` oferece o formulário “Iniciar nova operação”.
- A primeira operação de teste foi criada pela interface: `TESTE 20261116 - Vaquejada 1 - 100 competidores`, ID `eaf7121c-87f0-436f-bd2a-4d8c630d121a`. O painel mostrou “Operação iniciada. Ela já está disponível para inscrições e chamadas”, a operação ativa e 0 inscrições. O terminal da aplicação registrou `POST /painel 200`.
- A tela mantém visível a operação preexistente `1ª Vaquejada Teste`, sem alterações. A nova operação possui categoria `Geral`.
- Nenhuma outra operação ou dado de teste foi criado até o momento.
- A aplicação local respondeu à autenticação e carregou o painel; isso não confirma se o Supabase é ambiente exclusivo de homologação. O usuário autorizou prosseguir mesmo sem essa confirmação.

### Evidência e pendências

- Evidência visual: painel com a mensagem de operação iniciada, o identificador da primeira operação TESTE e a operação preexistente. Evidência de aplicação: resposta HTTP 200 para o envio do formulário.
- A tentativa de continuar para a segunda operação foi interrompida duas vezes pelo controle de interface, que detectou atividade de usuário no VS Code. Não foi enviada a segunda operação. A automação foi suspensa para não interferir na interação física do usuário.
- Permanecem pendentes: criar mais duas operações TESTE; cadastrar 100 competidores na primeira; executar e confirmar os fluxos de inscrições, categorias, rodízios, pista, escritório, locução, resultados, BOI TV e X1; registrar evidências e erros.
- Nenhuma inscrição, competidor, rodízio, operação de pista, chamada, resultado, atendimento BOI TV ou partida X1 foi criada nesta retomada.
- Continuar preservando todos os dados preexistentes e evitando exclusões em massa, alterações globais, comunicações externas e cobranças.

### Verificação do plano anexado

- O PDF anexado contém uma página digitalizada como imagem, sem texto selecionável. A leitura visual nos navegadores Brave e Edge exibiu uma página em branco; não foi possível recuperar os nomes dos três eventos.
- Não havia utilitário local de OCR disponível. O arquivo não foi enviado a serviços externos.
- Nenhum teste foi submetido; portanto, não há resultados de gravação a confirmar. A ausência dos nomes exatos do plano continua impedindo a criação segura dos eventos solicitados.

### Continuação dos testes operacionais — 16/11/2026

#### Operação de rodízio e bloqueios

- Pela interface, foi planejado e iniciado o `Rodízio #1` para a categoria Profissional do evento `TESTE 20261116 - Vaquejada 1 - 100 competidores` (ID `eaf7121c-87f0-436f-bd2a-4d8c630d121a`).
- A tela mostrou 28 inscrições na fila. Apesar da configuração ter sido iniciada com 1 boi, a fila exibiu duas corridas pendentes por inscrição (56 itens); não foi possível determinar se isso é esperado.
- Ao abrir a locução/pista e a rota X1 desse evento, ambas exibiram: “Não foi possível carregar o formato da competição. Verifique se a migration de Tropa de Elite foi aplicada.” Esses fluxos ficaram bloqueados. Nenhuma migration foi aplicada nem houve correção durante os testes.

#### BOI TV

- A central `/boi-tv`, aberta pela interface autenticada, exibiu o evento TESTE 1 como autorizado e `0 solicitações pendentes`.
- Não foi autorizado nenhum dispositivo nesta continuação e nenhum atendimento foi criado ou alterado. A tentativa de abrir a fila específica do evento foi interrompida repetidamente por atividade do usuário no VS Code; por isso, os detalhes dessa fila não foram verificados.
- O teste ponta a ponta de BOI TV permanece pendente. A autorização existente para a equipe não foi ampliada para criar acesso persistente de dispositivo.

#### Estado e próximos passos

- Os testes de valores de locução, chamadas, resultados, fluxo completo de BOI TV e X1 permanecem inconclusivos ou bloqueados; não devem ser considerados aprovados.
- As operações nos eventos TESTE 2 e TESTE 3 continuam pendentes.
- Até esta continuação, não foi confirmada a criação de novas inscrições, resultados ou partidas X1. Nenhum dado preexistente foi alterado ou excluído, nenhuma cobrança ou comunicação externa foi feita e nenhuma configuração global foi modificada.
- Não aplicar a migration nem modificar o sistema no curso desta bateria. Retomar os fluxos pela interface quando possível e registrar confirmações de gravação antes de avaliar prontidão.

### Continuação — 17/11/2026

- A fila BOI TV do evento TESTE 1 foi aberta pela interface compartilhada. A tela exibiu “Central em tempo real” e “Nenhuma solicitação recebida para este evento”. Nenhum atendimento foi criado, alterado ou decidido.
- Foram abertas as rotas do painel e da locução/pista-ops para retomar os testes, mas a navegação expirou e não forneceu snapshot dessas páginas. Isso impede continuar os fluxos nesta tentativa, mas não confirma por si só uma falha funcional nessas rotas.
- Nenhum dispositivo foi autorizado e nenhum acesso persistente foi criado. Nenhuma operação foi submetida nos eventos TESTE 2 e 3 nesta continuação.
- Permanecem pendentes: testar valores/chamadas/resultados na locução, confirmar a geração das corridas no rodízio, testar BOI TV ponta a ponta e X1, e concluir os fluxos restantes nos eventos TESTE 2 e 3. O bloqueio conhecido de migration em locução/X1 também permanece sem correção.

### Continuação — 17/11/2026, 21:59

- A rota de locução do evento TESTE 1 abriu após recarregar e selecionar Profissional. A tela mostrou o rodízio #1 e ofereceu as ações de resultado.
- A interface confirmou “Próxima senha chamada” e exibiu a senha 07, Marcos Carvalho, Corrida 1, Boi 1. A chamada foi registrada como concluída pela interface; a persistência ainda precisa de verificação cruzada.
- O campo de pontuação recebeu o valor 7, mas não houve confirmação de envio/gravação. Esse valor não deve ser contabilizado como resultado salvo.
- Ao tentar avançar para o resultado, a página ficou sem resposta e as páginas compartilhadas deixaram de fornecer conteúdo; nenhuma ação de resultado foi confirmada. Nenhuma chamada ou resultado adicional foi submetido.
- Para continuar, é necessária uma página autenticada do Connect Vaquejada acessível e estável; a página precisa permanecer aberta sem interação manual enquanto os testes são operados.


## Homologação — 18/11/2026

- Projeto Supabase de teste `oukiejushzxjhsamtrke`. As 32 migrations anteriores já constavam no histórico. As migrations `202611180001` e `202611180002` corrigiram a central e a fila dos dispositivos BOI TV autorizados.
- A suíte SQL transacional passou. Ela cobre cadastro com várias senhas, pagamento manual, isenção, rodízio, pontuação, retorno, encerramento, ativação e isolamento do BOI TV, revisão no X1 e eliminação na Tropa de Elite. A execução encerrou com rollback.
- Concorrência pela API em uma operação fictícia `63d39f73-388e-4094-8336-e5cfcefca456`. Foram disparadas 120 requisições independentes para a mesma categoria. Todas retornaram HTTP 200 em 1.634 ms no total. Consulta posterior confirmou 120 inscrições, 120 competidores e 120 senhas distintas. O evento ficou concluído.
- Uma tentativa anterior, feita por sessões paralelas da CLI, gravou 40 inscrições antes de falhas na autenticação temporária da CLI. Esse cenário foi encerrado e seus dados não foram contados no resultado da API.
- O servidor local respondeu HTTP 200 no computador em `http://10.0.0.190:3000`. O celular não conseguiu abrir esse endereço e ainda não há URL HTTPS de homologação. O ensaio físico permanece pendente.


### Ensaio em celular

- Evento fictício `cbf00c7a-60aa-4fee-ad1f-4ff8516fd0aa`, com uma solicitação BOI TV e um confronto X1.
- O celular abriu a aplicação pelo endereço local e ativou o BOI TV com código de uso único. O banco confirmou o dispositivo ativo e registrou a transição da solicitação de `nova` para `recebida` após o comando no celular.
- O redirecionamento da sessão de dispositivo foi corrigido para abrir o BOI TV e seu canal de atualização no evento autorizado. A sessão de locução pode abrir o X1 do próprio evento.
