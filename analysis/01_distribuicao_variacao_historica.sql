-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Análise 01 — Distribuição histórica da variação vs. semanas anteriores
-- MAGIC
-- MAGIC **Pergunta:** com que frequência a série do Pix varia 10% ou mais, para baixo ou para cima, quando comparada com a média do mesmo dia da semana nas 4 semanas anteriores (o método da notícia)? E onde caem os 3 dias da notícia (26, 27 e 28/09/2026) nessa distribuição?
-- MAGIC
-- MAGIC **Fonte:** `pix.gold.variacao_vs_semanas_anteriores`, coluna `variacao_quantidade_pct` (a métrica da notícia: quantidade de transações).
-- MAGIC
-- MAGIC **Janelas usadas:**
-- MAGIC
-- MAGIC | Análise | Janela | Motivo |
-- MAGIC | --- | --- | --- |
-- MAGIC | Por ano | 01/12/2020 a 25/09/2026 | Primeira data com base de 4 semanas completa até o dia anterior à MP |
-- MAGIC | Por dia da semana e posição dos 3 dias | 26/09/2025 a 25/09/2026 (12 meses) e 26/09/2024 a 25/09/2026 (24 meses) | Janelas recentes, em que o crescimento do Pix é mais estável; as duas são mostradas para verificar se a conclusão depende da janela |
-- MAGIC
-- MAGIC Os dias 26 a 28/09/2026 **não** entram no histórico de referência. Nenhuma janela foi ajustada após ver os resultados.
-- MAGIC
-- MAGIC **Como ler:**
-- MAGIC - As tabelas são **descritivas**: mostram a frequência de variações, sem afirmar causa para nenhuma delas.
-- MAGIC - A distribuição mistura efeitos de feriados, ciclo do mês e fins de ano. O calendário de feriados ainda não foi incorporado, então esses dias aparecem no histórico como variações comuns.
-- MAGIC - Uma variação rara no histórico não implica efeito de um evento específico, e uma variação comum não implica ausência de efeito.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Distribuição por ano
-- MAGIC
-- MAGIC Frequência de dias com variação ≤ −10% e ≥ +10%, mais percentis, para cada ano. A tendência de crescimento do Pix desloca a distribuição para cima nos primeiros anos (a mediana cai de +9,4% em 2021 para perto de 0 a partir de 2024), o que mostra que o método depende do período escolhido.
-- MAGIC
-- MAGIC 2020 cobre apenas dezembro (31 dias). 2026 vai até 25/09.

-- COMMAND ----------

SELECT
  YEAR(data)                                                                        AS ano,
  COUNT(*)                                                                          AS dias,
  CAST(percentile(variacao_quantidade_pct, 0.50) AS DECIMAL(10,2))                  AS mediana_pct,
  CAST(percentile(variacao_quantidade_pct, 0.05) AS DECIMAL(10,2))                  AS p05_pct,
  CAST(percentile(variacao_quantidade_pct, 0.95) AS DECIMAL(10,2))                  AS p95_pct,
  ROUND(100 * AVG(CASE WHEN variacao_quantidade_pct <= -10 THEN 1.0 ELSE 0 END), 1) AS pct_dias_queda_10_ou_mais,
  ROUND(100 * AVG(CASE WHEN variacao_quantidade_pct >=  10 THEN 1.0 ELSE 0 END), 1) AS pct_dias_alta_10_ou_mais
FROM pix.gold.variacao_vs_semanas_anteriores
WHERE variacao_quantidade_pct IS NOT NULL
  AND data <= DATE'2026-09-25'
GROUP BY YEAR(data)
ORDER BY ano;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Distribuição por dia da semana (últimos 12 meses)
-- MAGIC
-- MAGIC A notícia compara sábado, domingo e segunda. A variação típica e a frequência de quedas de 10% ou mais são diferentes conforme o dia da semana, então a referência correta para cada dia é o mesmo dia da semana. Cada linha tem cerca de 52 observações (uma por semana).

-- COMMAND ----------

SELECT
  dia_da_semana,
  nome_dia_da_semana,
  COUNT(*)                                                                          AS dias,
  CAST(percentile(variacao_quantidade_pct, 0.50) AS DECIMAL(10,2))                  AS mediana_pct,
  CAST(percentile(variacao_quantidade_pct, 0.05) AS DECIMAL(10,2))                  AS p05_pct,
  CAST(percentile(variacao_quantidade_pct, 0.95) AS DECIMAL(10,2))                  AS p95_pct,
  SUM(CASE WHEN variacao_quantidade_pct <= -10 THEN 1 ELSE 0 END)                   AS dias_queda_10_ou_mais,
  ROUND(100 * AVG(CASE WHEN variacao_quantidade_pct <= -10 THEN 1.0 ELSE 0 END), 1) AS pct_dias_queda_10_ou_mais
FROM pix.gold.variacao_vs_semanas_anteriores
WHERE data BETWEEN DATE'2025-09-26' AND DATE'2026-09-25'
GROUP BY dia_da_semana, nome_dia_da_semana
ORDER BY dia_da_semana;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Onde caem os 3 dias da notícia
-- MAGIC
-- MAGIC Para cada dia, `pct_igual_ou_pior` é o percentual de dias **do mesmo dia da semana** na janela histórica cuja variação foi igual ou pior (mais negativa) que a do dia da notícia. Valores baixos indicam que variações assim foram raras na janela; valores altos, que foram comuns. As janelas de 12 e 24 meses são mostradas lado a lado.

-- COMMAND ----------

SELECT
  n.data,
  n.nome_dia_da_semana,
  n.variacao_quantidade_pct                                                                       AS variacao_dia_pct,
  COUNT(CASE WHEN h.data >= DATE'2025-09-26' THEN 1 END)                                          AS dias_12m,
  ROUND(100 * AVG(CASE WHEN h.data >= DATE'2025-09-26'
                       THEN CASE WHEN h.variacao_quantidade_pct <= n.variacao_quantidade_pct THEN 1.0 ELSE 0 END
                  END), 1)                                                                        AS pct_igual_ou_pior_12m,
  COUNT(*)                                                                                        AS dias_24m,
  ROUND(100 * AVG(CASE WHEN h.variacao_quantidade_pct <= n.variacao_quantidade_pct THEN 1.0 ELSE 0 END), 1) AS pct_igual_ou_pior_24m
FROM pix.gold.variacao_vs_semanas_anteriores AS n
JOIN pix.gold.variacao_vs_semanas_anteriores AS h
  ON  h.dia_da_semana = n.dia_da_semana
  AND h.data BETWEEN DATE'2024-09-26' AND DATE'2026-09-25'
WHERE n.data BETWEEN DATE'2026-09-26' AND DATE'2026-09-28'
GROUP BY n.data, n.nome_dia_da_semana, n.variacao_quantidade_pct
ORDER BY n.data;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Sábados e domingos com queda de 10% ou mais (últimos 24 meses)
-- MAGIC
-- MAGIC Lista dos dias equivalentes aos da notícia (sábado e domingo) com variação ≤ −10% no histórico recente, para verificar em que datas ocorreram. O objetivo é permitir a leitura do contexto de cada data (por exemplo, proximidade de feriados); a coluna de contexto não é preenchida automaticamente.

-- COMMAND ----------

SELECT
  data,
  nome_dia_da_semana,
  quantidade,
  media_quantidade_4_semanas,
  variacao_quantidade_pct
FROM pix.gold.variacao_vs_semanas_anteriores
WHERE data BETWEEN DATE'2024-09-26' AND DATE'2026-09-25'
  AND dia_da_semana IN (6, 7)
  AND variacao_quantidade_pct <= -10
ORDER BY data;
