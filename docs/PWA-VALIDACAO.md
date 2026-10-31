# Validação do Financeiro PWA

## Concluído

- 19 testes Node, zero falhas; `npm run check` aprovado.
- Revisão cruzada do núcleo e UI por sênior; revisão gerencial independente, decisão APROVADO para PR e publicação privada de QA.
- Pacote estático contém somente13 arquivos do app. Sem testes, dados de runtime, senhas ou fontes nativas.
- Sites confirmou implantação privada bem-sucedida. O navegador verificou que o endereço HTTPS exige autenticação, sem reduzir o acesso para viabilizar QA.

## Não concluído

Preview gerenciado HTTP não disponibiliza Web Crypto; criação do cofre foi recusada. Não há fallback em texto claro. A página publicada HTTPS estava atrás de login sem sessão no navegador remoto, então não foi validado o fluxo completo nessa instância.

IndexedDB real/CAS entre janelas, criação/reabertura/bloqueio, offline, exportação/restore por arquivo e comportamento Safari/PWA/iCloud devem ser testados no aparelho ou em ambiente HTTPS autorizado. O helper de12 testes de navegador existe no código, mas não foi executado até este checkpoint. Testes Node não equivalem a esses testes.

## Aceite recomendado, somente dados fictícios

1. Instalar pelo Safari antes de criar o cofre, abrir pelo ícone, criar senha e guardá-la fora do app.
2. Adicionar receita100,00 e despesa25,50; fluxo esperado74,50. Transferência de10,00 não altera fluxo. Mudar mês e retornar.
3. Editar categoria sem alterar centavos, data ou hora. Buscar por descrição e filtrar conta/categoria.
4. Bloquear, testar senha errada, desbloquear com correta e verificar persistência após fechar/reabrir. Trocar de aplicativo durante a abertura deve cancelar o desbloqueio.
5. Exportar backup cifrado, guardar no iCloud via Arquivos, verificar arquivo e testar restauração com senha correta/incorreta. Um erro de senha não pode alterar o cofre.
6. Importar JSON fictício duas vezes com mesmo UUID e confirmar uma única inserção. CSV com linha inválida deve rejeitar o lote inteiro. Prévia não salva sem confirmação.
7. Carregar online, aguardar o primeiro cache completo e testar modo avião. Não apagar o app/dados do site para testar com registros reais.

A senha do cofre e dados financeiros reais não devem ser enviados em chats, logs ou repositórios.
