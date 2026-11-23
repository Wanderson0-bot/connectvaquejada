# Roteiro do piloto no parque

Use uma categoria do formato tradicional e inscrições fictícias. Escale uma pessoa para cada posto que será usado no dia: organização, escritório, locução, julgamento e BOI TV. Use os aparelhos e a rede do parque e registre o evento, a versão implantada, o horário e quem conferiu cada etapa.

## Preparação do ambiente

- [ ] Publicar em HTTPS com um projeto Supabase de homologação. Configurar `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY` para esse projeto.
- [ ] Confirmar o histórico de migrations e rodar `supabase/tests/pista_ops_rpc_tests.sql` em homologação. Conferir que a equipe e os dispositivos têm acesso ao evento e à função previstos.
- [ ] Rodar `npm run lint`, `npm run build` e `node --test --experimental-strip-types src/lib/pista-ops/domain.test.mjs` na versão candidata.
- [ ] Restaurar um backup em um ambiente isolado e conferir pelo menos as inscrições e os resultados registrados. Anotar o tempo de recuperação.
- [ ] Separar uma lista atualizada de senhas e fichas de pista em papel. Definir quem autoriza a entrada e a saída da contingência.

## Ensaio da inscrição ao resultado

| Etapa | Conferência |
|---|---|
| Escritório | Criar inscrições manualmente e por CSV. Incluir várias senhas, uma isenção e um cancelamento. Conferir lista, recibo e total recebido. |
| Rodízio de um boi | Começar com duas inscrições. Conferir até quatro corridas planejadas e uma posição de boi. Após consumir a posição, verificar que uma chamada que exige outra posição só segue quando houver disponibilidade. |
| Locução e julgamento | Chamar em ordem de senha, lançar resultados, conferir em quais casos a segunda corrida é liberada e testar retorno e Rabo da Gata. Recarregar a tela e conferir os registros gravados. |
| Correção e BOI TV | Corrigir um resultado e conferir a autoria e a classificação. Em um aparelho autorizado, receber e decidir uma revisão e verificar o efeito na origem da solicitação. |
| X1 ou Tropa de Elite | Se o evento usar o formato, ensaiar em uma operação própria, incluindo empate e morte súbita. |
| Fechamento | Encerrar o rodízio e o evento de teste. Conferir a classificação por categoria e conciliar pagamentos, isenções, cancelamentos e eventuais estornos com o caixa. |

## Queda de internet

1. Durante uma chamada e, separadamente, durante um lançamento de resultado, interromper a conexão do aparelho usado no ensaio.
2. Anotar horário, rodízio, senha, corrida, boi e o último registro confirmado. Se a equipe continuar em papel, usar uma única ficha oficial e registrar cada decisão nela.
3. Ao reconectar, abrir a locução e a classificação. Conferir quais ações foram gravadas antes de registrar as que ficaram só no papel.
4. Comparar fila, posição e placar com a ficha. Confirmar que cada chamada e cada resultado foram contabilizados uma única vez.

## Liberação

A organização e o diretor de pista liberam o uso principal depois de conferir as regras da prova, o fechamento e a recuperação da rede. Registrar o resultado de cada etapa como aprovada, reprovada ou pendente e anexar a evidência. Se houver divergência na fila ou no placar, repetir o cenário após a correção.
