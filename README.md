# Financeiro

App pessoal nativo para iPhone, em português, para organizar receitas, despesas e transferências sem backend, anúncios, analytics ou agregador bancário.

**Estado: primeira implementação em revisão. Não é uma versão instalada ou homologada no iPhone.** Acompanhe a validação no PR e em [docs/PROGRESSO.md](docs/PROGRESSO.md).

## O que foi implementado

- SwiftUI para iOS 17 ou posterior, armazenamento SQLite local, sem dependências externas de runtime.
- Cadastro, edição e exclusão com estabelecimento/descrição, valor, data e horário, categoria, conta, origem e observação.
- Resumo mensal em reais, busca e filtro por categoria. O fluxo é calculado com os lançamentos registrados; não representa o saldo do banco.
- Ação **Registrar transação** no Atalhos, com valor, estabelecimento, conta/cartão, tipo, categoria, data e UUID opcional.
- Importação CSV e restauração com prévia, confirmação e merge atômico; os registros atuais são mantidos. Até 100.000 lançamentos, também limitados a 14 MiB de JSON contabilizado para manter backups criptografados de até 20 MiB.
- Backup manual e automático com AES-256-GCM, senha e PBKDF2-HMAC-SHA256 (600.000 iterações).
- Backup automático na pasta escolhida em Arquivos, inclusive iCloud Drive, após alterações e ao abrir o app. Última cópia e uma cópia anterior. Não é um serviço que executa continuamente com o app fechado.
- Autenticação opcional por Face ID, Touch ID ou código para visualizar o app, incluindo modais.

## Privacidade

O código do app não usa rede nem envia lançamentos a GitHub, OpenAI, empresas de analytics ou servidores próprios. O GitHub guarda apenas código e exemplos fictícios. O iOS/provedor de arquivos administra a sincronização da pasta escolhida; somente o backup criptografado é exportado pelo app.

O banco local usa a proteção de arquivos do iOS após o primeiro desbloqueio. Ele **não tem criptografia própria por senha**: é protegido pelo sistema e pelo código do iPhone. O diretório local é excluído do backup padrão do sistema, para que as cópias deliberadas sejam os arquivos criptografados. Assim, apagar/perder o app sem uma cópia exportada pode perder registros.

A senha da cópia automática fica no Keychain deste aparelho, sem sincronização. Guarde uma cópia da senha fora do app: ela será necessária para recuperar em outro iPhone e não pode ser recuperada por nós. Face ID protege a visualização; a ação de Atalhos pode continuar escrevendo registros com o telefone bloqueado após o primeiro desbloqueio.

## Captura de transações: limites reais

O app não acessa diretamente notificações de outros aplicativos nem credenciais bancárias. A captura automática depende de uma automação configurada pelo usuário no Atalhos:

- **Transação da Carteira/Apple Pay:** a Apple documenta o evento ao aproximar um cartão. Os campos efetivamente disponíveis precisam ser conferidos no aparelho e no cartão. Não cobre por definição todo pagamento online, Pix, salário ou extrato histórico.
- **Notificação de app:** a documentação recente da Apple apresenta este gatilho, mas é necessário conferir se está disponível na versão instalada. Não é uma premissa para usar este app; não é necessário atualizar o iOS apenas para instalar o projeto.
- **Pix, entradas e demais movimentos:** lançamento manual, CSV ou uma automação que forneça campos explícitos. Esta versão não infere valores/tipos de textos bancários arbitrários e não inclui regras específicas de bancos.

Não há garantia de captura de todas as operações. Notificações podem faltar, chegar atrasadas ou omitir campos. Se você registrar uma compra por dois caminhos (Carteira e alerta bancário, por exemplo), poderão surgir duplicatas. Não habilite dois gatilhos para a mesma fonte sem uma regra de identificação.

O UUID opcional torna reenvios do mesmo evento idempotentes. Sem ele, cada execução de Atalhos gera um lançamento novo. Não descartamos automaticamente compras reais apenas por terem mesmo valor/loja/horário.

## Compilar e instalar

Abra `Financeiro.xcodeproj` em um Mac com Xcode e selecione uma equipe de assinatura em Signing & Capabilities. O projeto e o scheme compartilhado já estão incluídos. Não há CocoaPods/SPM ou bibliotecas externas a baixar.

```sh
bash scripts/test-ios.sh
```

O script seleciona um simulador de iPhone disponível, valida a estrutura e executa XCTest. `python3 scripts/verify_project.py` verifica somente referências, formatos de arquivos e marcadores de privacidade; não substitui build/testes.

A instalação num iPhone exige assinatura Apple. Conta gratuita via Xcode exige reprovisionamento periódico (sete dias). TestFlight exige conta Apple Developer e um build enviado ao App Store Connect; não é possível instalar um projeto Swift simplesmente abrindo o link do GitHub no iPhone. Veja [docs/INSTALACAO.md](docs/INSTALACAO.md).

## Usar

1. Adicione um lançamento fictício para verificar valor, data, hora e categoria.
2. Em Ajustes, defina senha forte e escolha uma pasta no iCloud Drive para ativar as cópias automáticas. Preserve essa senha.
3. Confira o arquivo em Arquivos e teste restaurar uma cópia antes de depender dela. O status indica gravação na pasta, não confirmação de upload ao iCloud.
4. Configure Atalhos conforme [docs/ATALHOS.md](docs/ATALHOS.md), começando com um registro fictício.
5. Para extratos, adapte ao formato de [docs/modelo-importacao.csv](docs/modelo-importacao.csv), leia [docs/IMPORTACAO.md](docs/IMPORTACAO.md) e revise a prévia antes de confirmar.

Não coloque extratos, notificações reais, senhas, certificados, chaves ou backups neste repositório.

## Documentação Apple

- [Sandbox e proteção dos apps](https://support.apple.com/pt-br/guide/security/sec15bfe098e/web)
- [Gatilho de transação da Carteira](https://support.apple.com/en-mo/guide/shortcuts/apd65c67538a/ios)
- [Novidades Atalhos, inclusive Notificação](https://developer.apple.com/videos/play/wwdc2026/310/)
- [FinanceKit: países e requisitos](https://developer.apple.com/financekit/) (não é uma integração geral para bancos brasileiros)
- [Pasta escolhida em Arquivos e bookmarks](https://developer.apple.com/documentation/uikit/providing-access-to-directories)
- [Instalação com conta Apple](https://developer.apple.com/help/account/basics/about-your-developer-account/)
