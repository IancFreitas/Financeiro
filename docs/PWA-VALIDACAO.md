# Validação do Financeiro PWA

## Concluído

- 19 testes Node, zero falhas; `npm run check` aprovado.
- Revisão cruzada do núcleo e UI por sênior; revisão gerencial independente, decisão APROVADO para PR e publicação privada de QA.
- Pacote estático contém somente 13 arquivos do app. Sem testes, dados de runtime, senhas ou fontes nativas.
- Em 31/10/2026, na árvore local, `npm test` (19/19), `npm run check` e `npm run test:browser` passaram. O alvo é Chromium (Playwright) emulando iPhone 13 em servidor localhost, contexto seguro com Web Crypto; não é Safari/iOS real. Resultado: 12/12 browser-checks de IndexedDB (`tests/browser-checks.html`) e 11 verificações do roteiro de aceite, todas com dados fictícios:
  - cofre criado, receita/despesa/transferência com fluxo 74,50 e IndexedDB sem texto em claro;
  - senha errada recusada no desbloqueio; após reload, senha correta mantém o fluxo 74,50;
  - captura revisada e importada, reenvio não duplica (4 registros);
  - backup cifrado baixado sem texto em claro; restauração em contexto novo recusa senha errada sem abrir a revisão e, com a correta, restaura 4 registros (fluxo 70,00);
  - offline com service worker: após reload, a tela de desbloqueio carrega.
- Revisão de importação informa quantos registros já existem no cofre e desabilita "Adicionar ao cofre" quando nenhum é novo; cache do service worker v3.
- Sites confirmou implantação privada bem-sucedida. O navegador verificou que o endereço HTTPS exige autenticação, sem reduzir o acesso para viabilizar QA.

## Não concluído

Preview gerenciado HTTP não disponibiliza Web Crypto; criação do cofre foi recusada. Não há fallback em texto claro. A página publicada HTTPS estava atrás de login sem sessão no navegador remoto, então não foi validado o fluxo completo nessa instância.

Continuam pendentes, por exigirem o aparelho ou ambiente HTTPS autorizado: Safari/WebKit real; instalação pela Tela de Início e uso pelo ícone instalado (armazenamento separado do Safari); compartilhamento para Arquivos/iCloud e conferência do arquivo salvo; Atalhos no aparelho; CAS entre janelas reais; instância publicada atrás de login. O job `browser` do GitHub Actions foi adicionado, mas ainda não rodou remotamente. Chromium emulando iPhone não substitui esses testes.

## Aceite recomendado, somente dados fictícios

1. Instalar pelo Safari antes de criar o cofre, abrir pelo ícone, criar senha e guardá-la fora do app.
2. Adicionar receita 100,00 e despesa 25,50; fluxo esperado 74,50. Transferência de 10,00 não altera fluxo. Mudar mês e retornar.
3. Editar categoria sem alterar centavos, data ou hora. Buscar por descrição e filtrar conta/categoria.
4. Bloquear, testar senha errada, desbloquear com correta e verificar persistência após fechar/reabrir. Trocar de aplicativo durante a abertura deve cancelar o desbloqueio.
5. Exportar backup cifrado, guardar no iCloud via Arquivos, verificar arquivo e testar restauração com senha correta/incorreta. Um erro de senha não pode alterar o cofre.
6. Importar JSON fictício duas vezes com mesmo UUID e confirmar uma única inserção. CSV com linha inválida deve rejeitar o lote inteiro. Prévia não salva sem confirmação.
7. Carregar online, aguardar o primeiro cache completo e testar modo avião. Não apagar o app/dados do site para testar com registros reais.

A senha do cofre e dados financeiros reais não devem ser enviados em chats, logs ou repositórios.

## CI remota

GitHub Actions aprovou o código PWA no commit 703cd9bb41b1f6839f8871e01e67ff5b27386a17: https://github.com/IancFreitas/Financeiro/actions/runs/41192476442 . Os 19 testes, a verificação sintática e a montagem dos 13 recursos estáticos passaram. Esse run é anterior ao job `browser` (Playwright 1.63.0), que ainda não foi executado no GitHub Actions. Os limites de validação em Safari/iPhone descritos acima permanecem.
