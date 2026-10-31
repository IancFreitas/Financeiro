# Integração local com Atalhos

A ação `Registrar transação` recebe campos explícitos e grava diretamente no banco do app. Não usa webhook, servidor, Open Banking ou acesso a notificações pelo próprio app.

## Teste inicial

1. Instale e abra o app uma vez. Abra o Atalhos e crie um atalho novo.
2. Adicione a ação Financeiro > Registrar transação. Se não aparecer, reabra Atalhos após instalar e abrir o app.
3. Preencha valor numérico 1,23, estabelecimento Loja de teste, conta Cartão teste, tipo Despesa e categoria Teste.
4. Execute e confira no Financeiro. O valor é em reais, positivo e com até duas casas decimais. O tipo determina receita/despesa/transferência.
5. Para testar reenvio idempotente, use o mesmo UUID no campo identificador e execute duas vezes. O primeiro insere e o segundo é ignorado. Apague o registro fictício depois.

## Apple Pay

No Atalhos configure uma automação com o gatilho Transação/Carteira, escolhendo o cartão usado. Adicione `Registrar transação` e associe as variáveis que o evento disponibilizar ao valor e ao estabelecimento. Defina conta/cartão e tipo explicitamente.

Os nomes/variáveis e possibilidade de execução imediata variam com a versão. Confira o resultado no iPhone antes de habilitar. Se faltarem valor ou estabelecimento, o app não deve inventá-los: use campos solicitados ao executar ou lançamento manual.

O gatilho documentado pela Apple é o uso do cartão por aproximação; não prometa cobertura de todas as transações, estornos, pagamentos online ou Pix. Configure cada cartão de forma consciente. Não duplique a mesma compra também pelo gatilho de notificação.

Se o evento oferecer a data original, associe-a ao campo opcional. Caso contrário, a ação registra o horário de execução e acrescenta uma observação avisando dessa diferença. O estabelecimento vem da fonte, não de GPS. O app não solicita localização.

## Notificações bancárias

A documentação recente da Apple apresenta o gatilho Notificação, por aplicativo e com filtros de conteúdo. Antes de configurá-lo, confira se ele existe na sua versão de iOS/Atalhos. Não é necessário atualizar o iOS como condição para usar os outros recursos.

Esta versão entrega a ação de entrada estruturada. Não entrega um leitor/parser universal de textos bancários. Para adicionar regras específicas precisamos dos bancos usados e de exemplos fictícios/anonimizados dos alertas, pois um mesmo texto pode representar compra, estorno, tentativa recusada ou saldo. Uma regra que extrai qualquer valor numérico pode registrar saldo como despesa.

Quando houver gatilho compatível e campos confiáveis, uma automação local pode extrair esses campos e chamar a ação. Revise e teste cada regra, incluindo notificações de compra negada, marketing, recebimento, estorno e valores ausentes. Não envie textos financeiros para serviços de IA nem para endpoints de rede dentro do atalho.

## Duplicação, falhas e autenticação

- Sem identificador, cada execução cria um UUID. Se Atalhos repetir um evento, pode duplicar.
- Com identificador, forneça um UUID estável por evento. Nunca use um UUID constante para todas as compras: isso impediria novas inserções.
- O app não infere duplicatas apenas por loja/valor/hora: duas compras iguais podem ser reais.
- A autenticação opcional protege a visualização; a ação é de escrita e pode funcionar com tela bloqueada após o primeiro desbloqueio. Não expõe consultas financeiras à Siri.
- Se o lançamento salvar e o backup falhar, a resposta informa os dois resultados. Não repetir o lançamento apenas por falha na cópia.
- Não há fila mágica de notificações perdidas. Compare periodicamente com o extrato.

Referências Apple: [Transação](https://support.apple.com/en-mo/guide/shortcuts/apd65c67538a/ios), [Notificação no Atalhos](https://developer.apple.com/videos/play/wwdc2026/310/), [execução automática](https://support.apple.com/en-gb/guide/shortcuts/-apd602971e63/ios).
