# Financeiro PWA: ponto de retomada

## Estado

Implementação web instalável entregue no PR #2, branch feat/pwa-local-first. O app nativo permanece preservado no PR #1. A interface web usa a marca Entrecontas; o ícone instalado chama-se Financeiro.

## Publicação

Acesso privado: https://financeiro-local-icf.berrybun20.chatgpt.site

Sites confirmou implantação bem-sucedida, somente para o proprietário, em 31/10/2026. Código financeiro não usa backend nem analytics; a hospedagem serve o app e administra apenas acesso aos arquivos estáticos.

## Implementado

- Cofre IndexedDB cifrado por senha, AES-256-GCM e PBKDF2-SHA256600.000, senha não persistida, chave apenas em memória.
- Gravações com revisão CAS e fila local; conflitos entre janelas não sobrescrevem silenciosamente.
- Receitas/despesas/transferências, datas e horários, categorias/contas/observações, edição/exclusão, filtros e fluxo mensal. Centavos seguros, totais BigInt, sem saldo bancário presumido.
- JSON e CSV revisados antes de merge por UUID. Backup cifrado exportado por Compartilhar/download e restaurado após validação integral.
- Captura estruturada de Atalhos por colar/arquivo; entrada por fragmento de URL é limpa imediatamente, não autoimportada. Preferir colar no ícone instalado para evitar armazenamento separado do Safari.
- Manifest, ícones e service worker para instalação e cache offline após carregamento completo.
- Bloqueio imediato da interface ao ocultar e cancelamento de abertura pendente; formulários, revisões e arquivos preparados são limpos.

## Evidências

19/19 testes Node aprovados: dinheiro/limites, datas, CSV/BOM/aspas/IDs, importação, envelope/tamper/custo KDF, defesa de tamanho, fragmento, arquivos shell e ausência de cliente de rede no runtime. npm run check aprovado.

Revisão sênior e gerencial independentes aprovaram PR e implantação privada de QA. Corrigidos: resumo de mês antigo, centavos ao editar valores altos, segundos/ms originais, DOM visível durante bloqueio, resultados assíncronos após ocultar, cancelamento de desbloqueio e clareza do status de backup.

Limite de QA: a prévia gerenciada foi aberta e a interface inspecionada, mas usa HTTP e não oferece crypto.subtle. Não foi usado fallback inseguro. O app mostra orientação para abrir HTTPS. A publicação HTTPS foi confirmada pela ferramenta; o navegador de QA alcançou a proteção de login da conta e não tinha sessão autorizada para acessar o app. Não foram concluídos fluxo real IndexedDB/CAS, recarregamento/offline, compartilhamento ou instalação em iPhone. Não declarar esses testes aprovados.

O helper tests/browser-checks.html contém12 verificações de IndexedDB em banco QA isolado, com dados fictícios, sem tocar o cofre principal. Testes não são incluídos no pacote publicado.

## Limites do produto

Sem acesso direto a notificações, credenciais ou extrato de bancos. Atalhos fornecem campos explícitos, com confirmação. Sem App Intents nativos, captura universal/background, conciliação automática ou sincronização entre dispositivos.

Backup iCloud por exportação/compartilhamento; status de exportação solicitada não comprova gravação ou upload. Senha é indispensável para recuperar o arquivo. Dados do Safari/PWA podem ser separados; abrir sempre pelo ícone instalado. Não inserir dados reais no repositório.

## Próxima retomada

1. Abrir endereço HTTPS no Safari com a conta autorizada e instalar pela Tela de Início antes de criar registros reais.
2. Executar roteiro com dados fictícios: criar cofre, cadastrar/editar, bloquear, senha errada/correta, recarregar, testar offline e restaurar uma cópia.
3. Confirmar compartilhamento em Arquivos/iCloud no iPhone. Não depender de uma cópia que não foi verificada.
4. Configurar captura por Atalhos com campos que realmente estejam disponíveis, revisar e testar duplicatas/alertas incompletos. Não assumir parser de texto universal.

## CI remota

GitHub Actions aprovou o código PWA no commit703cd9bb41b1f6839f8871e01e67ff5b27386a17: https://github.com/IancFreitas/Financeiro/actions/runs/41192476442 . Os19 testes, a verificação sintática e a montagem dos13 recursos estáticos passaram. Os limites de validação no navegador/iPhone descritos acima permanecem.
