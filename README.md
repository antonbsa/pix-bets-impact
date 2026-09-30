# pix-bets-impact

Pipeline de dados e análise para testar uma afirmação que circulou na imprensa: **"após o bloqueio das bets, as movimentações de Pix caíram 10%"**.

A hipótese deste projeto é que a comparação feita na notícia pode ter sido enviesada (sazonalidade, composição de dias, janela escolhida). O objetivo é verificar, com os dados públicos do Banco Central, se a queda existe quando a comparação é realizada corretamente, deixando claro o que os dados conseguem e não conseguem afirmar.

O projeto também é um exercício prático de engenharia de dados, abrangendo ingestão de API, arquitetura medallion (bronze/silver/gold), tipagem, cargas incrementais e documentação de decisões.

## A pergunta

> A queda de ~10% no Pix após o bloqueio das bets se sustenta quando são controlados a sazonalidade, o calendário e a tendência de crescimento?

**Notícia de referência:** [G1 — "Transações com Pix caem após proibição das bets; veja os dados"](https://g1.globo.com/economia/noticia/2026/09/29/transacoes-com-pix-caem-apos-proibicao-das-bets-veja-os-dados.ghtml) (publicada em 29/09/2026).
**Data do bloqueio:** 25 de setembro de 2026 (sexta-feira), data de publicação no Diário Oficial da União da [Medida Provisória nº 1.394/2026](https://www.congressonacional.leg.br/materias/medidas-provisorias/-/mpv/175871), que proíbe a exploração, oferta, intermediação e publicidade de apostas de quota fixa. A MP tem vigência imediata, mas o bloqueio é **escalonado** (fonte: [Ministério da Justiça e Segurança Pública](https://www.gov.br/mj/pt-br/assuntos/noticias-1/governo-federal-proibe-bets-em-todo-o-pais-e-lanca-pacote-de-protecao-as-familias-endividadas-1); exposição de motivos em [planalto.gov.br](https://www.planalto.gov.br/ccivil_03/_ato2023-2026/2026/exm/exm-mp-1394-26.pdf)):

| Data | Marco |
| --- | --- |
| 25/09/2026 | Publicação da MP; fica vedado novo aporte de recursos em contas de apostas |
| até 05/10/2026, 23h59 | Prazo para os apostadores resgatarem o saldo remanescente |
| 06/10/2026, 0h | Sites e aplicativos bloqueados no país |
| 09 a 14/10/2026 | Bancos devolvem os saldos remanescentes |

Dessa forma, a janela "depois" da notícia (26 a 28/09) situa-se **antes** do bloqueio total das plataformas: apenas os novos depósitos estavam vedados. A definição da data a ser usada como marco (25/09 ou 06/10) será documentada em ADR, e as duas datas devem ser testadas nas análises. A MP ainda precisa ser aprovada pelo Congresso em até 120 dias.

**Recorte usado na notícia:**

- **Métrica:** quantidade de transações (não valor em R$).
- **Janela "depois":** sábado 26, domingo 27 e segunda-feira 28/09/2026 (a segunda é o dado mais recente disponível na data da matéria).
- **Base de comparação:** média dos mesmos dias da semana nas **4 semanas anteriores** (ex.: sábado 26 vs média dos 4 sábados anteriores).
- **Fonte:** estatísticas do SPI do Banco Central.

| Dia | Transações | Variação divulgada |
| --- | --- | --- |
| Sábado (26) | 229,6 milhões | −11% |
| Domingo (27) | 165,9 milhões | −12% |
| Segunda-feira (28) | 213 milhões | −7,4% |
| **Acumulado (3 dias)** | **608,6 milhões** | **−10%** |

Observações: na notícia não é feita comparação com o mesmo período do ano anterior, e feriados e ciclo do mês não são tratados. Também é informado que o Banco Central foi questionado pelo g1 sobre uma possível relação entre a queda e a MP, sem resposta até a publicação. Os números acima correspondem ao que é afirmado na notícia e ainda não foram reproduzidos com os dados do projeto.

## O que será testado

A notícia é o ponto de partida. Cada comparação abaixo será apresentada lado a lado com a da notícia:

| Possível viés | Como testar |
| --- | --- |
| Sazonalidade | Comparar com o mesmo período do ano anterior (YoY), não só com o mês anterior |
| Composição de dias | Normalizar por dia da semana, fins de semana e feriados |
| Ciclo do mês | Considerar picos de início/fim de mês (salários, contas) |
| Tendência de crescimento | Comparar contra a tendência esperada, não contra um valor fixo |
| Janela escolhida | Testar a sensibilidade do resultado a diferentes recortes de datas |
| Métrica | Verificar se a queda aparece em valor (R$), em quantidade, ou em ambos |
| Variação típica do período | Calcular a mesma variação (mesma posição no mês e mesmos dias da semana, contra as 4 semanas anteriores) em meses sem bloqueio e verificar se a queda observada está fora da distribuição histórica |

## Análise complementar: pausas da data FIFA

Como segunda hipótese, será examinada a relação entre o volume de Pix e as **pausas de jogos das datas FIFA**, que interrompem as ligas de clubes e afetam as **apostas esportivas**, e não apenas os cassinos online. Esta análise é independente do bloqueio das bets e segue as mesmas regras: a comparação ingênua será apresentada ao lado da ajustada (mesmo dia da semana, mesma posição no mês).

- **Fonte externa necessária:** a série do BCB não contém informação de calendário esportivo. As janelas das datas FIFA serão obtidas do calendário oficial da FIFA e mantidas em uma tabela pequena e versionada no repositório (seed), com a fonte citada.
- **Alternativas consideradas:** API de futebol (API-Football, football-data.org), descartada por exigir chave e por ser desproporcional a poucas datas por ano; calendário da CBF, útil para confirmar a pausa do Brasileirão, mas restrito ao Brasil.
- **Tabela prevista:** `pix.silver.calendario_data_fifa`, com `data_inicio`, `data_fim`, `fonte` e `observacao`, relacionada ao `pix_diario` por data.
- **Definição prévia das janelas:** as janelas serão definidas e documentadas antes da observação dos resultados, para evitar seleção de datas após a visualização dos gráficos.

Cuidados específicos desta análise:

- A pausa não elimina as apostas: jogos de seleções continuam ocorrendo, de modo que o efeito esperado é de deslocamento, sem direção presumida.
- São poucas janelas por ano (cerca de 10 dias cada), o que reduz o poder estatístico.
- Dia de pagamento, fim de mês, feriados e dia da semana são fatores de confusão, assim como a Copa do Mundo de 2026 (junho e julho), que distorce comparações no período.
- Os dados são agregados e não segmentados por bets: nenhuma causalidade poderá ser afirmada.

## Limitações

Os dados do BCB são **agregados diários de todo o Pix**, sem separação por setor ou destinatário. Portanto, **não é possível provar causalidade** entre o bloqueio das bets e qualquer variação com os dados disponíveis. O que pode ser feito é:

- verificar se a queda alegada existe nos dados;
- verificar se ela se mantém sob comparações ajustadas;
- estimar se a variação está fora do padrão histórico, comparando-a com a variação da mesma janela (mesma posição no mês e mesmos dias da semana) em meses sem bloqueio.

## Fonte de dados

**Estatísticas do SPI — Banco Central do Brasil** (API OData "Olinda", licença ODbL)

- Endpoint: `https://olinda.bcb.gov.br/olinda/servico/SPI/versao/v1/odata/PixLiquidadosAtual`
- Granularidade: diária, desde 03/11/2020
- Campos usados: `Data`, `Quantidade`, `Total` (em **milhares de R$**), `Media`
- Considera ordens de transferência (PACS008) e devoluções (PACS004)

## Arquitetura

```
API BCB ──> bronze ──> silver ──> gold ──> análise
            (raw)     (tipado)   (métricas)
```

| Camada | Conteúdo |
| --- | --- |
| **bronze** | Resposta da API sem transformação, com data de extração. Imutável. |
| **silver** | Dados tipados: `DATE`, valores em `DECIMAL`, conversão para reais, colunas de calendário (ano, mês, dia da semana, dia útil, feriado). |
| **gold** | Métricas analíticas: variação YoY, médias por dia da semana, janelas antes/depois do bloqueio, desvio em relação à tendência. |

A execução é realizada no **Databricks**, com tabelas Delta.

**Fonte externa (calendário):** as janelas das datas FIFA entram como uma tabela de apoio (`calendario_data_fifa`), mantida manualmente a partir do calendário oficial da FIFA e relacionada por data às tabelas do Pix.

## Status

- [x] Mapeamento da API e teste de extração
- [x] Localizar a notícia original
- [x] Documentar o recorte usado na notícia (períodos e métrica)
- [ ] Ingestão bronze no Databricks
- [ ] Camada silver com calendário e feriados
- [ ] Camada gold com métricas comparativas
- [ ] Reprodução da análise da notícia
- [x] Seed com as janelas das datas FIFA (fonte citada)
- [ ] Análise complementar: Pix nas pausas da data FIFA
- [ ] Análises ajustadas e conclusão

## Conclusão

_Em aberto. Será preenchida ao final, com base nos dados — seja qual for o resultado._