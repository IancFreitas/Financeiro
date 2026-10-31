# Financeiro local · PWA

Aplicativo web instalável pela Tela de Início, inspirado na arquitetura do projeto Evolucao: HTML, CSS e módulos JavaScript sem dependências externas de runtime. A interface chama-se Entrecontas; o ícone instalado aparece como Financeiro.

## Recursos

- Cofre cifrado no próprio navegador: AES-256-GCM, PBKDF2-SHA256 com 600.000 iterações, salt16 e nonce12 aleatórios. Senha mínima12, máximo1024 bytes, jamais persistida pelo app; chave apenas em memória enquanto aberto.
- Lançamentos em reais com valor exato, data/horário, tipo, conta, categoria, descrição e observação; edição/exclusão; busca e filtros; fluxo mensal (não saldo do banco).
- IndexedDB guarda somente o envelope cifrado; revisões detectam gravações de outra janela para evitar perda silenciosa. Bloqueio manual e ao ocultar o app.
- Exportação de backup cifrado para Compartilhar/Salvar em Arquivos/iCloud ou download; restauração em prévia, com merge de IDs ausentes. Não sobrescreve registros já existentes.
- CSV e captura JSON de Atalhos com validação integral e confirmação. O guia dentro do app explica como copiar JSON e colar pelo ícone instalado.
- Manifest e service worker para instalação e uso offline após o primeiro carregamento completo.

## Uso no iPhone

1. Abra o endereço HTTPS publicado no Safari. A hospedagem privada pode pedir autenticação de acesso antes de servir o app.
2. Compartilhar → Adicionar à Tela de Início. Mantenha Abrir como App da Web ativado quando disponível.
3. Abra o novo ícone, crie uma senha e guarde-a fora do aplicativo. Não envie essa senha em chats nem a coloque no repositório.
4. Adicione um registro fictício primeiro. Em Cofre, prepare uma cópia, compartilhe e escolha Salvar em Arquivos → iCloud Drive. Confira no Arquivos se foi salvo e sincronizado.
5. Use sempre o ícone instalado: Safari e app da Tela de Início podem ter armazenamentos separados. A migração entre eles é por backup/restauração.

## Limites explícitos

O app não acessa diretamente notificações, contas ou credenciais de bancos. Atalhos e arquivos preparam entradas, mas você confirma a importação. Não há App Intent nativo, captura universal em background, conciliação automática, cálculo de saldo bancário ou sincronização entre dispositivos.

Backup no iCloud é por exportação/compartilhamento; a PWA não escreve silenciosamente numa pasta do iCloud. O status informa solicitação de exportação, nunca comprova upload. O navegador pode remover dados locais, e apagar o app/site pode apagar o cofre. Preserve backups e senha; não há recuperação de senha.

Dados não são enviados pelo código do app a servidores financeiros, analytics ou IA. A hospedagem serve o código e pode receber metadados normais de acesso, como em qualquer site. Dados desbloqueados estão acessíveis ao código que roda na página: mantenha aparelho, origem e atualizações sob controle. HTTPS é obrigatório para a criptografia e o service worker; não há fallback em texto claro.

Limites: 20.000 registros e 14 MiB de dados JSON; arquivos cifrados/importados até20 MiB. Regras de moeda e datas são explícitas. Totais usam BigInt; cada valor armazenado é inteiro seguro em centavos.

## CSV

UTF-8, delimitador `;`, cabeçalho `date;merchant;amount;kind`, opcionais `id;category;account;currency;note`. date ISO com fuso (`2026-10-31T12:30:00-03:00`), amount positivo pt-BR (`123,45`), kind income/expense/transfer. Moeda apenas BRL. IDs UUID estáveis são preferíveis. Sem ID, conteúdo normalizado e ocorrência geram UUID determinístico; fontes diferentes com linhas idênticas podem colidir. Arquivo inteiro inválido é rejeitado antes de mutar o cofre.

## Atalhos

Em Registros → Receber dados, cole JSON estruturado. Exemplo fictício:

```json
{"id":"29e3bfd2-740d-4b72-a6b7-171a58354529","amount":"1,23","merchant":"Loja de teste","kind":"expense","account":"Cartão de teste","category":"Teste"}
```

Sem data, será usado o horário de recebimento com observação. Sem UUID, reenvios podem duplicar. O app não interpreta uma notificação arbitrária como transação. Atalho deve fornecer campos explícitos, nunca colocar dados na query de uma URL. O fragmento de entrada é limpo antes de processar e também passa por revisão. Para evitar confusão de armazenamento Safari/PWA, prefira copiar e colar no app instalado.

## Desenvolvimento e evidências

```sh
cd pwa
npm test
npm run check
```

Node22+; testes built-in, sem instalação de pacotes. Há testes adicionais IndexedDB no navegador em `tests/browser-checks.html`, com banco QA isolado e dados sintéticos, nunca no cofre de produção. `scripts/build_pwa.py` copia somente arquivos estáticos conhecidos, excluindo testes e dados de runtime.

A versão nativa iOS permanece preservada no PR #1; esta PWA é entregue no PR #2. Backups nativos e web são formatos diferentes nesta primeira versão. Nenhum dado real ou credencial deve ser versionado.


App publicado com acesso privado: https://financeiro-local-icf.berrybun20.chatgpt.site .
Validação e limites em [docs/PWA-VALIDACAO.md](docs/PWA-VALIDACAO.md).
