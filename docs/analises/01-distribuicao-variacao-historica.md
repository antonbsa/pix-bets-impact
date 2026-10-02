# Análise 01 — Distribuição histórica da variação vs. semanas anteriores

- **Status:** intermediária (descritiva); valores **a confirmar** com a execução no Databricks
- **Notebook:** [`analysis/01_distribuicao_variacao_historica.sql`](../../analysis/01_distribuicao_variacao_historica.sql)
- **Fonte:** `pix.gold.variacao_vs_semanas_anteriores`, coluna `variacao_quantidade_pct`
- **Extração da bronze usada:** _a preencher (data/hora UTC do arquivo lido no Databricks)_

> **Estado dos números.** As quatro tabelas foram conferidas contra a saída do notebook no Databricks em 02/10/2026 e coincidem com um teste local anterior, realizado com o JSON baixado da API em 29/09/2026. Dados recentes do BCB podem ser revisados, de modo que uma nova execução pode divergir.

## Pergunta

Com que frequência a quantidade diária de transações do Pix varia 10% ou mais, quando comparada com a média do mesmo dia da semana nas 4 semanas anteriores (método usado na notícia do g1)? Em que posição da distribuição histórica caem os três dias da notícia (26, 27 e 28/09/2026)?

## Método e janelas

- **Métrica:** `quantidade` de transações (a mesma da notícia). A variação é `(quantidade do dia − média dos 4 mesmos dias da semana anteriores) / média × 100`.
- **Histórico de referência:** termina em 25/09/2026. Os dias 26 a 28/09/2026 não integram o histórico.
- **Janelas:**

| Tabela | Janela |
| --- | --- |
| Por ano | 01/12/2020 a 25/09/2026 |
| Por dia da semana | 26/09/2025 a 25/09/2026 (12 meses) |
| Posição dos 3 dias | 12 meses (26/09/2025 a 25/09/2026) e 24 meses (26/09/2024 a 25/09/2026) |
| Fins de semana com queda ≥ 10% | 26/09/2024 a 25/09/2026 |

- As janelas foram definidas antes da observação dos resultados e não foram ajustadas depois.
- Não há tratamento de feriados, ciclo do mês, datas FIFA ou tendência. A análise descreve o método original.

## Resultados

### 1. Distribuição por ano

| Ano | Dias | Mediana (%) | P05 (%) | P95 (%) | Dias com queda ≥ 10% (%) | Dias com alta ≥ 10% (%) |
| --- | --- | --- | --- | --- | --- | --- |
| 2020 (só dezembro) | 31 | 77,03 | −4,79 | 229,75 | 3,2 | 87,1 |
| 2021 | 365 | 9,40 | −13,20 | 44,86 | 7,7 | 49,3 |
| 2022 | 365 | 2,91 | −15,03 | 28,18 | 11,5 | 29,0 |
| 2023 | 365 | 1,54 | −14,15 | 25,30 | 10,1 | 24,1 |
| 2024 | 366 | −0,48 | −13,95 | 21,92 | 10,4 | 22,4 |
| 2025 | 365 | −0,37 | −14,40 | 19,85 | 12,1 | 23,0 |
| 2026 (até 25/09) | 268 | −1,13 | −14,21 | 17,74 | 11,9 | 20,9 |

Confirmado no Databricks: 02/10/2026

Leitura: a mediana da variação passa de valores positivos e altos (fase de crescimento acelerado do Pix) para valores próximos de zero a partir de 2024. O resultado do método depende, portanto, do período escolhido.

### 2. Distribuição por dia da semana (últimos 12 meses)

| Dia | Dias | Mediana (%) | P05 (%) | P95 (%) | Dias com queda ≥ 10% | % dos dias |
| --- | --- | --- | --- | --- | --- | --- |
| Segunda | 52 | 0,52 | −15,51 | 17,23 | 7 | 13,5 |
| Terça | 52 | 0,73 | −14,78 | 18,17 | 9 | 17,3 |
| Quarta | 52 | 0,21 | −13,33 | 15,89 | 8 | 15,4 |
| Quinta | 52 | −0,97 | −13,18 | 26,01 | 8 | 15,4 |
| Sexta | 53 | −0,59 | −18,52 | 20,73 | 8 | 15,1 |
| Sábado | 52 | −1,36 | −9,68 | 16,11 | 2 | 3,8 |
| Domingo | 52 | −0,15 | −8,93 | 12,58 | 2 | 3,8 |

Confirmado no Databricks: 02/10/2026

Leitura: quedas de 10% ou mais foram frequentes de segunda a sexta (13% a 17% dos dias) e raras aos sábados e domingos (3,8%, isto é, 2 de 52 dias em cada).

### 3. Posição dos três dias da notícia

`pct_igual_ou_pior` é o percentual de dias do mesmo dia da semana, na janela histórica, com variação igual ou pior (mais negativa) que a do dia da notícia.

| Dia | Variação calculada (%) | Variação divulgada (%) | Igual ou pior, 12 meses (%) | Igual ou pior, 24 meses (%) |
| --- | --- | --- | --- | --- |
| Sábado 26/09/2026 | −10,97 | −11 | 3,8 | 5,8 |
| Domingo 27/09/2026 | −12,02 | −12 | 3,8 | 2,9 |
| Segunda 28/09/2026 | −7,35 | −7,4 | 26,9 | 23,1 |

Confirmado no Databricks: 02/10/2026

Leitura: nas duas janelas, as variações de sábado e domingo foram menos frequentes no histórico recente do que as de segunda-feira. A variação da segunda-feira situa-se em faixa que já ocorreu com frequência.

### 4. Sábados e domingos com queda ≥ 10% (últimos 24 meses)

| Data | Dia | Quantidade | Média das 4 semanas | Variação (%) |
| --- | --- | --- | --- | --- |
| 12/10/2024 | sábado | 147.134.548 | 172.216.851,25 | −14,56 |
| 28/12/2024 | sábado | 172.254.730 | 202.202.815,25 | −14,81 |
| 29/12/2024 | domingo | 129.748.340 | 146.289.390,00 | −11,31 |
| 04/01/2025 | sábado | 160.243.695 | 194.259.745,25 | −17,51 |
| 05/01/2025 | domingo | 124.810.434 | 142.725.950,75 | −12,55 |
| 12/01/2025 | domingo | 121.863.613 | 136.587.656,50 | −10,78 |
| 19/04/2025 | sábado | 174.080.945 | 195.574.491,25 | −10,99 |
| 27/12/2025 | sábado | 199.193.756 | 251.905.316,25 | −20,93 |
| 28/12/2025 | domingo | 157.542.812 | 184.002.242,00 | −14,38 |
| 03/01/2026 | sábado | 189.246.741 | 238.793.793,00 | −20,75 |
| 04/01/2026 | domingo | 153.429.683 | 178.553.575,50 | −14,07 |

Confirmado no Databricks: 02/10/2026

Leitura: as datas concentram-se no fim de dezembro e início de janeiro, além de 12/10/2024 e 19/04/2025. A relação com feriados e recessos é uma observação sobre as datas e **não foi verificada** contra uma tabela de feriados.

## O que a análise permite afirmar

- Aplicado a sábados e domingos, o método da notícia produziu variações de −10% ou pior em poucas ocasiões na janela recente, e o sábado e o domingo de 26 e 27/09/2026 estão nessa faixa.
- Para a segunda-feira, a variação da notícia (−7,35%) é compatível com a frequência histórica.

## O que a análise não permite afirmar

- **Causalidade.** Os dados são agregados diários do Pix inteiro; não há separação por setor ou destinatário. Nenhuma variação pode ser atribuída ao bloqueio das bets.
- **Ausência de causas alternativas.** Não foram tratados feriados, ciclo do mês (26 a 28/09 ocorrem no fim do mês), tendência de crescimento nem o efeito das pausas da data FIFA.
- **Significância estatística.** As frequências são descritivas. Com 52 observações por dia da semana (2 ocorrências em cada caso de fim de semana), a comparação é sensível a datas individuais, e nenhum teste estatístico foi aplicado.
- **Robustez à janela.** Foram testadas apenas duas janelas (12 e 24 meses). A sensibilidade a outros recortes permanece em aberto.

## Próximos passos

- Confirmar as tabelas com a execução no Databricks e preencher a data da extração.
- Comparação com o mesmo período do ano anterior (YoY), lado a lado com a da notícia.
- Tabela de feriados na silver, para verificar as datas da tabela 4 e ajustar a comparação.
- Verificação do efeito do ciclo do mês e das pausas da data FIFA.
