# Financeiro PWA

A versão web foi autorizada como alternativa ao projeto nativo. Não exigir Xcode para validar JavaScript. O app iOS fica preservado em outro PR.

Aplicar equipe proporcional e checkpoints. Sem dados financeiros reais, instituições usadas ou condições pessoais em commits. HTML/CSS/ES modules sem dependências externas de runtime, sem backend financeiro, CDN, analytics ou fontes remotas.

Cofre IndexedDB só armazena envelope cifrado, senha não persistida. Não diminuir custo KDF nem alterar formato sem validar compatibilidade. Centavos seguros e totais BigInt. Importação inteira validada antes de mutar, revisão explícita e merge por UUID. Não publicar conteúdo financeiro em parâmetros de URL. Fragmento é entrada temporária, limpo imediatamente, sem autoimportação.

Testes: npm test, npm run check. Browser QA deve verificar formulários, reload, erros de senha, ciphertext no IndexedDB e offline. Atualizar shell/version do service worker ao adicionar/remover arquivos. Alterações no código exigem revisão sênior antes da entrega.
