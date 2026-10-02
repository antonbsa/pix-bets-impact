-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 03 — Gold: `pix.gold.variacao_yoy`
-- MAGIC
-- MAGIC **Propósito:** para cada dia da série, compara o valor do dia com o dia equivalente do **ano anterior, alinhado pelo dia da semana**. É a comparação anual (YoY, *year over year*) prevista na etapa 2 do plano de análise.
-- MAGIC
-- MAGIC - **Alinhamento:** o dia de comparação é `data - 364 dias` (52 semanas exatas), e não a mesma data do calendário. Assim, um sábado é comparado com um sábado, o que evita misturar dias úteis e fins de semana. O custo é que datas fixas (feriados, 1º de janeiro) deixam de coincidir: por exemplo, o 7 de setembro cai em uma segunda-feira em 2026, mas o dia equivalente de 2025 foi uma segunda-feira comum.
-- MAGIC - **Métricas:** `quantidade` e `valor_reais`, lado a lado.
-- MAGIC - **Sem dia equivalente** (primeiros 364 dias da série), as colunas de variação ficam `NULL`.
-- MAGIC - A variação YoY **inclui a tendência de crescimento anual** do Pix: ela não é "queda ou alta em relação ao normal", é crescimento em relação ao ano anterior. Por isso é lida contra o YoY de outras semanas, e não contra zero.
-- MAGIC - Esta view **não afirma causa** para nenhuma variação.
-- MAGIC
-- MAGIC É uma **view** pelo mesmo motivo de `variacao_vs_semanas_anteriores`: ~2 mil linhas, cálculo barato, sempre reflete a silver atual.

-- COMMAND ----------

CREATE SCHEMA IF NOT EXISTS pix.gold;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## A view
-- MAGIC
-- MAGIC É um `LEFT JOIN` da série com ela mesma, deslocada em 364 dias. `LEFT` mantém os dias sem equivalente (com `NULL`) em vez de descartá-los. Em JS: `serie.map(d => ({...d, anterior: porData[d.data - 364 dias]}))`.

-- COMMAND ----------

CREATE OR REPLACE VIEW pix.gold.variacao_yoy
COMMENT 'Variação de cada dia contra o dia equivalente do ano anterior, alinhado pelo dia da semana (data - 364 dias). Inclui a tendência de crescimento anual; descritiva, não indica causa.'
AS
SELECT
  a.data,
  a.dia_da_semana,
  a.nome_dia_da_semana,
  a.quantidade,
  p.data                                                                         AS data_ano_anterior,
  p.quantidade                                                                   AS quantidade_ano_anterior,
  CAST((a.quantidade - p.quantidade) / p.quantidade * 100 AS DECIMAL(10,2))      AS variacao_yoy_quantidade_pct,
  a.valor_reais,
  p.valor_reais                                                                  AS valor_reais_ano_anterior,
  CAST((a.valor_reais - p.valor_reais) / p.valor_reais * 100 AS DECIMAL(10,2))   AS variacao_yoy_valor_reais_pct
FROM pix.silver.pix_diario AS a
LEFT JOIN pix.silver.pix_diario AS p
  ON p.data = DATE_SUB(a.data, 364);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Conferência: integridade
-- MAGIC
-- MAGIC Uma linha por dia da silver; o dia de comparação cai no mesmo dia da semana; só os primeiros 364 dias ficam sem variação.

-- COMMAND ----------

SELECT
  (SELECT COUNT(*) FROM pix.silver.pix_diario)                                    AS linhas_silver,
  COUNT(*)                                                                        AS linhas_view,
  SUM(CASE WHEN data_ano_anterior IS NULL THEN 1 ELSE 0 END)                      AS sem_ano_anterior,
  SUM(CASE WHEN data_ano_anterior IS NOT NULL
            AND DAYOFWEEK(data) <> DAYOFWEEK(data_ano_anterior) THEN 1 ELSE 0 END) AS dia_da_semana_diferente
FROM pix.gold.variacao_yoy;
