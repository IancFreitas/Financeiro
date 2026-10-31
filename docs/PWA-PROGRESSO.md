# Financeiro PWA: ponto de retomada

## Objetivo
Versão web instalável pela Tela de Início, usando o mesmo padrão arquitetural do projeto Evolucao: HTML/CSS/JavaScript estáticos, IndexedDB, service worker e exportação de backups. O projeto nativo continua preservado no PR #1.

## Arquitetura
- Cofre criptografado no aparelho com AES-256-GCM e PBKDF2-SHA256; senha não persistida e chave só em memória enquanto desbloqueado.
- Interface pt-BR, receitas/despesas/transferências, categorias, busca e fluxo mensal dos registros.
- Nenhum backend financeiro, analytics ou credencial bancária. Hospedagem entrega somente os arquivos do app.
- Backups criptografados entregues por Compartilhar/Salvar em Arquivos; o envio ao iCloud e conclusão da cópia dependem do usuário/sistema.
- Entradas de Atalhos por JSON/colar/arquivo, com revisão antes de gravar. Links usam apenas fragmento e nunca query para conteúdo financeiro.
- A PWA não lê notificações de outros apps e não executa captura universal em background.

## Frentes
Sênior: modelo, valores, CSV, criptografia, IndexedDB e testes. Pleno: interface e formulários. Gerente: integração, offline, ponte de entrada, hospedagem e revisão.

## Estado
Checkpoint inicial. Não declarar app publicado, teste aprovado ou instalação realizada antes das respectivas evidências.

## Próximo
Integrar fontes, executar testes de regras/criptografia, revisar privacidade e armazenamento, verificar interface/offline, publicar acesso privado e confirmar URL. Não armazenar dados financeiros reais neste repositório.
