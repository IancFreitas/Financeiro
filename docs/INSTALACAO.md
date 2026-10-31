# Instalação e validação no iPhone

O resultado deste repositório é um projeto nativo, não um site e não um app já assinado.

## Se houver acesso a um Mac

1. Instale Xcode compatível com o iOS do aparelho. Clone o repositório privado e abra Financeiro.xcodeproj.
2. Em Xcode > Settings > Accounts, conecte sua conta Apple por conta própria. Não compartilhe senha, código de verificação ou chave aqui.
3. Selecione o target Financeiro, uma equipe em Signing & Capabilities e um bundle ID único da sua conta se necessário.
4. Execute primeiro os testes no simulador (`bash scripts/test-ios.sh`). Depois conecte o iPhone, habilite Developer Mode quando solicitado e execute o app.
5. Faça as verificações de captura, backup e restauração abaixo.

A Personal Team gratuita limita apps/dispositivos e os perfis expiram após sete dias. Reinstalar com o mesmo identificador pode preservar dados, mas não dependa disso: mantenha backups verificáveis.

## Sem Mac pessoal

A alternativa é compilar e assinar em um Mac/serviço macOS remoto e distribuir pelo TestFlight, com sua própria conta Apple Developer. O workflow deste repositório **só executa testes de simulador, sem assinatura nem publicação**. Não gera um IPA instalável nem envia ao TestFlight.

Para publicar uma build pessoal ainda é preciso definir a equipe, bundle ID e assinatura sob a sua conta. Nenhuma assinatura, compra de programa ou envio à App Store foi realizado. Não peça nem coloque credenciais em commits.

Os builds do TestFlight têm validade de até 90 dias; não são instalação permanente. Um app pessoal na App Store também depende da conta, requisitos e revisão Apple. Não usar certificados compartilhados de terceiros.

## Aceite no aparelho

Use dados fictícios até concluir:

- Cadastro e edição de valor, data/horário, categoria e conta. Compare entradas/saídas com resumo mensal.
- Autenticação ativada: bloquear, abrir app, abrir modal, ir para background e voltar. Confirmar que nenhum modal mostra registros antes da autenticação.
- Registrar uma transação pelo Atalhos com app aberto e fechado; repetir com mesmo UUID e verificar que não duplicou. Confirmar diferença entre data original e horário de registro.
- Escolher uma pasta no iCloud Drive, ativar backup e conferir latest/previous no Arquivos. Comparar a data de gravação e aguardar sincronização do iOS.
- Restaurar um arquivo em ambiente de teste: senha correta, senha errada, arquivo alterado. Conferir que os registros atuais foram preservados e não houve importação parcial.
- Revogar acesso à pasta, ficar offline, bloquear/reiniciar iPhone e verificar mensagens de falha separadas do sucesso do lançamento.
- Confirmar que após reiniciar é necessário desbloquear uma vez para permitir o acesso aos dados locais/Chaves.
- Importar CSV de teste duas vezes e conferir identificadores. Não habilitar dois gatilhos para a mesma compra sem deduplicação de origem.

Não desinstale a versão com dados reais para testar restauração. Use outro bundle ID/dispositivo de teste ou uma base fictícia. Preserve a senha fora do aparelho.

Fontes: [conta Apple e limites gratuitos](https://developer.apple.com/help/account/basics/about-your-developer-account/), [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).
