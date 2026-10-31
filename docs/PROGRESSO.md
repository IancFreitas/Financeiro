# Continuidade do projeto

## Objetivo
App iOS nativo, local, sem servidor ou analytics, receitas/despesas/transferências, Atalhos, backup criptografado no iCloud Drive escolhido pelo usuário.

## Decisões
- SwiftUI iOS 17+, SQLite, centavos inteiros, sem bibliotecas externas de runtime.
- Backup AES-GCM com senha, derivação PBKDF2, restauração validada antes de gravar.
- Pasta de backup escolhida pelo seletor Arquivos; senha só no Keychain local para cópias automáticas.
- App Intents como interface local para Atalhos. Sem acesso direto às notificações de terceiros.
- A Apple documenta novo gatilho Notificação no Atalhos recente, mas disponibilidade precisa ser conferida na versão instalada. Não exigir atualizar iOS como premissa.
- Importação CSV com prévia e confirmação, sem credenciais bancárias.

## Equipe em execução
- Gerente: integração, App Intents, projeto Xcode, CI e revisão.
- Sênior: armazenamento SQLite, criptografia e testes.
- Pleno: interface nativa em português.
- Sênior: pesquisa Apple e backup automático.

## Pontos de salvamento
1. main inicializado com escopo e limitações.
2. Esta branch e PR rascunho: arquitetura e progresso antes de código.
3. Próximo: fontes integrados e verificações estáticas.
4. Próximo: build/testes em ambiente Apple e instalação no iPhone.

## Pendências com usuário
Bancos/cartões usados, existência de Mac e/ou conta Apple Developer, exemplos fictícios/anonimizados de alertas para configurar a captura.

## Limites de validação
Ambiente atual Linux, sem Swift/Xcode/simulador. Não declarar app compilado/instalado sem evidências. Apenas dados sintéticos em testes. Não publicar segredos ou dados financeiros no GitHub.
