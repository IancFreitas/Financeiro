# Trabalho neste projeto

Use a metodologia de equipe solicitada pelo usuário: gerente responsável por escopo/integração, sênior para armazenamento/segurança e pleno para UI, com revisão independente proporcional. Não fingir testes, modelos ou delegações.

Antes de mudanças, leia README.md e docs/PROGRESSO.md. Atualize o progresso com o que realmente foi executado, pendências e evidências. Salve checkpoints em branch/PR cedo e antes de interrupções de contexto. Não fazer merge de código sem build iOS/testes ou sem explicitar a ausência das evidências.

Privacidade: nenhum dado financeiro real, extrato, alerta, senha, chave ou certificado em commits/logs. Sem backend, analytics ou dependências externas de runtime sem discutir alteração de escopo. Só arquivos criptografados saem do sandbox via escolha do usuário.

Valores em centavos inteiros, conversão explícita de localidade, nunca somar moedas distintas. Dinheiro, restauração e importações devem validar antes de gravar; manter atomicidade e proteção de dados. Não inferir operações bancárias de notificações arbitrárias. Documentar os limites da captura de Atalhos.

Atualize o projeto com `python3 scripts/generate_project.py` após adicionar/remover fontes. Verifique `python3 scripts/verify_project.py`. Build/testes: `bash scripts/test-ios.sh` em macOS/Xcode. Verificação estática não equivale a teste executado. Teste de Keychain, Arquivos/iCloud e autenticação requer iPhone.
