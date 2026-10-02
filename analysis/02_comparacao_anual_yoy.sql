-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Análise 02 — Comparação anual (YoY) dos três dias da notícia
-- MAGIC
-- MAGIC **Pergunta:** os dias 26, 27 e 28/09/2026 variam de forma incomum contra o ano anterior? E como essa variação se compara com o YoY dos mesmos dias da semana nas semanas anteriores?
-- MAGIC
-- MAGIC **Fontes:** `pix.gold.variacao_yoy` (comparação anual, dia equivalente = data − 364 dias) e `pix.gold.variacao_vs_semanas_anteriores` (método da notícia), esta última apenas para a comparação lado a lado.
-- MAGIC
-- MAGIC **Janelas usadas:**
-- MAGIC
-- MAGIC | Análise | Janela |
-- MAGIC | --- | --- |
-- MAGIC | Lado a lado | 26 a 28/09/2026 |
-- MAGIC | YoY nas semanas anteriores | 8 semanas anteriores a cada dia (mesmo dia da semana) |
-- MAGIC | Tendência semanal do YoY | 20/07/2026 a 28/09/2026 |
-- MAGIC | Posição na distribuição | 12 meses (26/09/2025 a 25/09/2026) e 24 meses (26/09/2024 a 25/09/2026) |
-- MAGIC
-- MAGIC Os dias 26 a 28/09/2026 não entram no histórico de referência. As janelas foram definidas antes da observação dos resultados (plano de análise, etapa 2).
-- MAGIC
-- MAGIC **Como ler:**
-- MAGIC - O YoY mede o crescimento contra o ano anterior. O Pix cresce de forma sustentada, então um YoY positivo **não** indica ausência de queda: indica apenas que o dia superou o dia equivalente de 2025. A leitura relevante é comparar o YoY desses dias com o YoY de outros dias.
-- MAGIC - A comparação por dia equivalente (364 dias) alinha o dia da semana, mas **não alinha feriados**. Dias cujo equivalente cai em feriado, ou que são feriado, distorcem o YoY (a tabela 2 contém um exemplo).
-- MAGIC - O dia equivalente de 2025 também pode ter sido atípico, e isso afeta o YoY de 2026.
-- MAGIC - As tabelas são descritivas e não afirmam causa.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Lado a lado: método da notícia e YoY
-- MAGIC
-- MAGIC Para cada dia, a variação pelo método da notícia (contra a média dos 4 mesmos dias da semana anteriores) e pelo YoY (contra o dia equivalente do ano anterior), em quantidade e em valor. São perguntas diferentes: a primeira compara com o passado recente, a segunda com o ano anterior.

-- COMMAND ----------

SELECT
  y.data,
  y.nome_dia_da_semana,
  y.data_ano_anterior,
  g.variacao_quantidade_pct              AS noticia_quantidade_pct,
  y.variacao_yoy_quantidade_pct          AS yoy_quantidade_pct,
  g.variacao_valor_reais_pct             AS noticia_valor_pct,
  y.variacao_yoy_valor_reais_pct         AS yoy_valor_pct
FROM pix.gold.variacao_yoy AS y
JOIN pix.gold.variacao_vs_semanas_anteriores AS g USING (data)
WHERE y.data BETWEEN DATE'2026-09-26' AND DATE'2026-09-28'
ORDER BY y.data;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. YoY de cada dia contra o YoY das semanas anteriores
-- MAGIC
-- MAGIC `media_yoy_4_semanas_pct` é a média do YoY dos 4 mesmos dias da semana imediatamente anteriores (por exemplo, para o sábado 26/09, os 4 sábados anteriores). `diferenca_pp` é a diferença, em **pontos percentuais**, entre o YoY do dia e essa média; valores negativos indicam crescimento anual menor que o das semanas anteriores.
-- MAGIC
-- MAGIC Atenção à segunda-feira 28/09: entre as 4 segundas anteriores está 07/09/2026 (feriado de 7 de setembro), cujo dia equivalente em 2025 foi comum. Isso reduz a média da base e distorce a diferença. A tabela 2b mostra a base dia a dia.

-- COMMAND ----------

WITH yoy AS (
  SELECT
    data,
    nome_dia_da_semana,
    variacao_yoy_quantidade_pct,
    AVG(variacao_yoy_quantidade_pct) OVER (
      PARTITION BY dia_da_semana ORDER BY data ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING
    ) AS media_yoy_4_semanas
  FROM pix.gold.variacao_yoy
)
SELECT
  data,
  nome_dia_da_semana,
  variacao_yoy_quantidade_pct                                                   AS yoy_quantidade_pct,
  CAST(media_yoy_4_semanas AS DECIMAL(10,2))                                    AS media_yoy_4_semanas_pct,
  CAST(variacao_yoy_quantidade_pct - media_yoy_4_semanas AS DECIMAL(10,2))      AS diferenca_pp
FROM yoy
WHERE data BETWEEN DATE'2026-09-26' AND DATE'2026-09-28'
ORDER BY data;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2b. A base dia a dia (8 semanas anteriores)
-- MAGIC
-- MAGIC YoY de cada sábado, domingo e segunda-feira das 8 semanas anteriores e dos 3 dias da notícia, em quantidade e em valor. Permite ver a oscilação normal do YoY e identificar dias distorcidos por feriado.

-- COMMAND ----------

SELECT
  nome_dia_da_semana,
  data,
  data_ano_anterior,
  variacao_yoy_quantidade_pct,
  variacao_yoy_valor_reais_pct
FROM pix.gold.variacao_yoy
WHERE dia_da_semana IN (6, 7, 1)
  AND data BETWEEN DATE'2026-08-01' AND DATE'2026-09-28'
ORDER BY dia_da_semana, data;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Tendência semanal do YoY
-- MAGIC
-- MAGIC Média do YoY de todos os dias, por semana (segunda a domingo). Mostra o ritmo de crescimento anual que precede os 3 dias. A semana de 28/09 tem apenas 1 dia.

-- COMMAND ----------

SELECT
  DATE_TRUNC('week', data)                                  AS semana_inicio,
  COUNT(*)                                                  AS dias,
  ROUND(AVG(variacao_yoy_quantidade_pct), 2)                AS yoy_quantidade_medio_pct,
  ROUND(AVG(variacao_yoy_valor_reais_pct), 2)               AS yoy_valor_medio_pct
FROM pix.gold.variacao_yoy
WHERE data BETWEEN DATE'2026-07-20' AND DATE'2026-09-28'
GROUP BY DATE_TRUNC('week', data)
ORDER BY semana_inicio;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Onde caem os 3 dias na distribuição do YoY
-- MAGIC
-- MAGIC `pct_igual_ou_pior` é o percentual de dias do mesmo dia da semana, na janela histórica, com YoY igual ou menor (menor crescimento) que o do dia da notícia. Valores baixos indicam crescimento anual menor que o habitual para aquele dia da semana. Janelas de 12 e 24 meses lado a lado.

-- COMMAND ----------

SELECT
  n.data,
  n.nome_dia_da_semana,
  n.variacao_yoy_quantidade_pct                                                             AS yoy_dia_pct,
  COUNT(CASE WHEN h.data >= DATE'2025-09-26' THEN 1 END)                                    AS dias_12m,
  ROUND(100 * AVG(CASE WHEN h.data >= DATE'2025-09-26'
                       THEN CASE WHEN h.variacao_yoy_quantidade_pct <= n.variacao_yoy_quantidade_pct THEN 1.0 ELSE 0 END
                  END), 1)                                                                  AS pct_igual_ou_pior_12m,
  COUNT(*)                                                                                  AS dias_24m,
  ROUND(100 * AVG(CASE WHEN h.variacao_yoy_quantidade_pct <= n.variacao_yoy_quantidade_pct THEN 1.0 ELSE 0 END), 1) AS pct_igual_ou_pior_24m
FROM pix.gold.variacao_yoy AS n
JOIN pix.gold.variacao_yoy AS h
  ON  h.dia_da_semana = n.dia_da_semana
  AND h.data BETWEEN DATE'2024-09-26' AND DATE'2026-09-25'
WHERE n.data BETWEEN DATE'2026-09-26' AND DATE'2026-09-28'
GROUP BY n.data, n.nome_dia_da_semana, n.variacao_yoy_quantidade_pct
ORDER BY n.data;
