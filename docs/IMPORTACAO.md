# Formato de importação CSV

Formato UTF-8 (BOM opcional), delimitador `;` recomendado. O [modelo](modelo-importacao.csv) contém apenas exemplos fictícios. Esta versão não importa formatos arbitrários de extrato de cada banco.

| Coluna | Regra |
| --- | --- |
| date | Obrigatória. ISO 8601 com hora e fuso: `2026-10-31T12:30:00-03:00`. |
| merchant | Obrigatória. Descrição/estabelecimento, até 200 caracteres. |
| amount | Obrigatória. Valor positivo em reais: `123,45`, `1.234,56` ou `123`. Nunca valor em centavos, sinal negativo ou ponto decimal. |
| kind | Obrigatória. `income`, `expense` ou `transfer`. |
| id | UUID opcional e preferível, estável e único na origem. Não repetir dentro do arquivo. |
| currency | Opcional. Apenas `BRL` nesta versão; padrão BRL. |
| category | Opcional. Padrão A categorizar. |
| account | Opcional. Padrão Importada. |
| note | Opcional. Até 4.000 caracteres. |

Aspas escapadas e quebras de linha em campos com aspas são aceitas. Com delimitador vírgula, envolva valores decimais com aspas (`"123,45"`). Colunas desconhecidas, linhas inconsistentes, valores ambíguos, moedas diferentes ou identificadores repetidos rejeitam o arquivo inteiro antes de alterar o banco.

Arquivos de até 20 MiB e 100.000 registros. A base final também precisa caber no orçamento de 14 MiB de JSON contabilizado para garantir que continue exportável. Se exceder esse limite, a operação inteira é recusada sem alterar os registros atuais. A prévia exibe os primeiros 100 e informa o total a importar. O merge inteiro acontece dentro de uma transação SQLite; falhas revertem a operação.

Sem coluna id, o app gera IDs determinísticos pelo conteúdo normalizado e ocorrência de linhas idênticas. Isso permite importar o mesmo arquivo novamente sem duplicá-lo e preserva duas linhas iguais dentro do arquivo. Porém, duas fontes diferentes com dados idênticos podem receber o mesmo ID, e uma linha alterada vira outro ID. Prefira IDs estáveis da origem e confira duplicatas na prévia.

A restauração de backup também acrescenta apenas IDs ausentes. Ela não sobrescreve uma versão editada de um lançamento já existente e não recupera edições sobre o mesmo ID. Não é sincronização entre dispositivos.
