# Progresso e continuidade

## Estado atual

Primeira implementação do app iOS pronta para validação Apple, na branch `feat/ios-local-first`, PR #1. Ainda não foi instalada nem homologada num iPhone. Não confundir verificação estrutural com compilação.

## Entregue no código

- SwiftUI pt-BR: resumo mensal, lista/busca/categorias, criação/edição/exclusão e horário.
- SQLite local protegido pelo iOS, centavos inteiros, operações atômicas, UUID para identidade e exclusão do backup padrão do sistema.
- Backup AES-256-GCM/PBKDF2-SHA256 600.000, salt/nonce aleatórios, formato v1, importação validada antes de gravar.
- Backup automático oportunista: bookmark de pasta escolhida em Arquivos, senha somente Keychain local, latest/previous; falha na cópia separada do resultado do lançamento.
- App Intent de escrita `Registrar transação`, sem rede, para configuração no Atalhos.
- CSV UTF-8 com prévia, validação integral e merge atômico; valores e moedas explícitos.
- Proteção de visualização opcional com LocalAuthentication, incluindo modais e retorno do background.
- Projeto Xcode determinístico, ícone e manifest de privacidade. Script de testes e workflow macOS sem credenciais bancárias/Apple.
- 25 casos XCTest escritos, cobrindo dinheiro, armazenamento, rollback/concorrência, criptografia, CSV e conversão Atalhos.

## Evidências reais

Executado no ambiente atual: gerador do projeto, verificação de referências/arquivos plist/XML/JSON, sintaxe do script Bash e compilação sintática dos scripts Python. Busca de APIs de rede/SDKs de analytics em fontes de runtime sem ocorrência. Revisão independente sênior trouxe correções de proteção de arquivos, fail-open em autenticação e formato AppIntent.

Executado remotamente no GitHub Actions: compilação completa e 25 testes XCTest aprovados, zero falhas, Xcode 16.4 / SDK iOS Simulator 18.5. Commit de código validado: `0ae117152aaff280096deda0e1d1b6b058fcfd46`. Evidência: https://github.com/IancFreitas/Financeiro/actions/runs/41180272013 . O primeiro build encontrou argumento Foundation incorreto (`setAttributes`), corrigido para `ofItemAtPath` antes da execução aprovada.

Não executado: inspeção visual da UI, Keychain e acesso persistente a pasta/iCloud reais, autenticação/modal no aparelho e automações reais de bancos/Carteira. Ambiente local Linux sem Xcode/Swift; o runner macOS forneceu as evidências de compilação e testes unitários. Os commits posteriores exclusivamente de documentação não alteram o código validado.

## Equipe

Gerente: integração, App Intents, formato CSV, projeto/CI e documentação. Sênior: SQLite, modelo/criptografia/testes e revisão cruzada. Pleno: UI. Sênior: viabilidade Apple e backup automático. Revisão gerencial independente adicional para bugs substantivos antes da entrega.

## Decisões e limites

1. Sem backend, analytics ou dependências externas de runtime; não armazenar dados reais no repositório.
2. App iOS não tem acesso direto a notificações de terceiros. Automação Carteira é caminho inicial; novo gatilho Notificação precisa ser conferido na versão instalada. Não exigir atualização do iOS como premissa.
3. FinanceKit não é integração geral para bancos brasileiros. Não foram criados conectores bancários/credenciais.
4. O app aceita campos estruturados via Atalhos; não há parser universal de textos bancários. Precisamos dos bancos e formatos para criar regras confiáveis.
5. Backup é cópia criptografada em pasta escolhida. Status de gravação não confirma upload iCloud. Sem timer permanente em background e sem sincronização entre dispositivos.
6. Restauração é merge de IDs ausentes: não sobrescreve versão editada de um ID existente. CSV sem IDs usa conteúdo+ocorrência; duas fontes com dados idênticos podem colidir. Preferir UUID estável de origem.
7. A capacidade também é limitada a 14 MiB de JSON contabilizado para garantir backups de até 20 MiB. Operações que ultrapassam o limite falham com rollback e aviso; o banco não passa a aceitar dados impossíveis de exportar.
8. Totais são fluxo dos registros em BRL, sem saldo bancário, financiamento, parcelas/faturas ou conciliação automática nesta primeira versão.
9. Não enviar build à Apple nem gastar com assinatura sem decisão do usuário. Conta gratuita via Xcode e TestFlight têm limites/expiração documentados.

## Pendências com o usuário

- Quais bancos/cartões devem ser priorizados? Precisamos exemplos fictícios ou anonimizados dos alertas, não extratos/senhas.
- Há acesso a Mac? Há conta Apple Developer? Isso determina instalação pessoal vs TestFlight.
- Conferir no aparelho se o Atalhos oferece gatilho Notificação na versão instalada e quais campos chegam da Carteira.

## Próximo ponto de retomada

1. CI de código aprovada no PR #1: 25/25 testes, zero falhas. Manter rascunho enquanto instalação e validação no aparelho ainda estiverem pendentes.
2. Escolher instalação conforme acesso/conta informados pelo usuário.
3. Validar no iPhone o roteiro em INSTALACAO.md com dados fictícios, incluindo restauração real e retorno de autenticação nos modais.
4. Configurar e testar captura específica por banco/cartão. Conferir duplicação, compra negada, estorno, alerta ausente e offline.

## Verificação técnica de distribuição

Build e testes no simulador não produzem, por si só, um app instalável no iPhone. A instalação nativa exige assinatura e provisionamento Apple. A opção gratuita oficial usa Xcode e perfis temporários; distribuição por TestFlight requer Apple Developer Program e builds assinados. Antes de preparar distribuição, esclarecer o caminho de instalação e seus custos com o usuário. Não contratar assinatura nem assumir acesso a ambiente de assinatura.

Este checkpoint registra somente o requisito técnico público; detalhes pessoais, instituições bancárias utilizadas e condições da conta do usuário não devem ser registrados aqui sem autorização específica.
