-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 03 — Gold: `pix.gold.variacao_vs_semanas_anteriores`
-- MAGIC
-- MAGIC **Propósito:** para cada dia da série, compara o valor do dia com a **média dos mesmos dias da semana nas 4 semanas anteriores** (ex.: um sábado contra a média dos 4 sábados anteriores). É o método de comparação usado na notícia do g1, aplicado a toda a série e não só aos 3 dias divulgados.
-- MAGIC
-- MAGIC - **Métricas:** `quantidade` (a usada na notícia) e `valor_reais`, lado a lado.
-- MAGIC - **Janela da base:** as 4 ocorrências imediatamente anteriores do mesmo dia da semana (28 dias antes, sem incluir o dia). Sem tratamento de feriados, de ciclo do mês ou de tendência: a view reproduz o método original, e as comparações ajustadas serão construídas em outras tabelas.
-- MAGIC - **Só calcula variação com 4 semanas completas.** Nas primeiras semanas da série, `variacao_*_pct` fica `NULL`.
-- MAGIC - **Por que cobrir a série inteira:** a mesma comparação pode ser aplicada a qualquer dia, o que permite ver quanto a variação costuma oscilar sem nenhuma intervenção (o "ruído normal" do método).
-- MAGIC - Esta view **não afirma causa** para nenhuma variação: apenas descreve a diferença entre um dia e a sua base.
-- MAGIC
-- MAGIC É uma **view**, não uma tabela: o cálculo é barato (~2 mil linhas) e a view sempre reflete a silver atual, sem etapa de carga.
-- COMMAND ----------
CREATE SCHEMA IF NOT EXISTS pix.gold;

-- COMMAND ----------
-- MAGIC %md
-- MAGIC ## A view
-- MAGIC
-- MAGIC `PARTITION BY dia_da_semana ORDER BY data` separa a série em 7 (uma por dia da semana), cada uma com uma linha por semana. A moldura `ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING` pega as 4 semanas anteriores e exclui a linha atual. Isso é correto porque a silver tem uma linha por dia, sem buracos (validado na carga da silver); com buracos, "4 linhas antes" deixaria de significar "4 semanas antes".
-- MAGIC
-- MAGIC Uma função de janela é como um `map` em que cada elemento enxerga uma fatia dos vizinhos: em JS, algo como `serie.map((x, i) => media(serie.slice(i - 4, i)))`, aqui feito dentro de cada dia da semana.
-- COMMAND ----------
CREATE
OR REPLACE VIEW pix.gold.variacao_vs_semanas_anteriores COMMENT 'Variação de cada dia contra a média do mesmo dia da semana nas 4 semanas anteriores (método da notícia do g1). Descritiva: não indica causa.' AS
WITH
  base AS (
    SELECT
      data,
      dia_da_semana,
      nome_dia_da_semana,
      quantidade,
      valor_reais,
      CAST(AVG(quantidade) OVER janela AS DECIMAL(18, 2)) AS media_quantidade_4_semanas,
      CAST(AVG(valor_reais) OVER janela AS DECIMAL(18, 2)) AS media_valor_reais_4_semanas,
      COUNT(*) OVER janela AS semanas_na_base
    FROM
      pix.silver.pix_diario
    WINDOW
      janela AS (
        PARTITION BY
          dia_da_semana
        ORDER BY
          data ROWS BETWEEN 4 PRECEDING
          AND 1 PRECEDING
      )
  )
SELECT
  data,
  dia_da_semana,
  nome_dia_da_semana,
  quantidade,
  media_quantidade_4_semanas,
  CASE
    WHEN semanas_na_base = 4 THEN CAST(
      (quantidade - media_quantidade_4_semanas) / media_quantidade_4_semanas * 100 AS DECIMAL(10, 2)
    )
  END AS variacao_quantidade_pct,
  valor_reais,
  media_valor_reais_4_semanas,
  CASE
    WHEN semanas_na_base = 4 THEN CAST(
      (valor_reais - media_valor_reais_4_semanas) / media_valor_reais_4_semanas * 100 AS DECIMAL(10, 2)
    )
  END AS variacao_valor_reais_pct,
  semanas_na_base
FROM
  base;

-- COMMAND ----------
-- MAGIC %md
-- MAGIC ## Conferência: reprodução da notícia
-- MAGIC
-- MAGIC Os três dias da notícia, com o valor **divulgado** ao lado do **calculado**. Diferenças pequenas são esperadas, porque a notícia arredonda e os dados do BCB podem ter sido revisados depois da publicação. Esta consulta só compara; não interpreta.
-- MAGIC
-- MAGIC | Dia | Transações divulgadas | Variação divulgada |
-- MAGIC | --- | --- | --- |
-- MAGIC | 26/09/2026 (sábado) | 229,6 milhões | −11% |
-- MAGIC | 27/09/2026 (domingo) | 165,9 milhões | −12% |
-- MAGIC | 28/09/2026 (segunda) | 213 milhões | −7,4% |
-- COMMAND ----------
SELECT
  v.data,
  v.nome_dia_da_semana,
  v.quantidade AS quantidade_calculada,
  n.quantidade_divulgada,
  v.media_quantidade_4_semanas,
  v.variacao_quantidade_pct AS variacao_calculada_pct,
  n.variacao_divulgada_pct,
  v.variacao_valor_reais_pct AS variacao_valor_calculada_pct
FROM
  pix.gold.variacao_vs_semanas_anteriores AS v
  JOIN (
    VALUES
      (DATE '2026-09-26', 229600000, -11.0),
      (DATE '2026-09-27', 165900000, -12.0),
      (DATE '2026-09-28', 213000000, -7.4)
  ) AS n (
    data,
    quantidade_divulgada,
    variacao_divulgada_pct
  ) ON v.data = n.data
ORDER BY
  v.data;

-- COMMAND ----------
-- MAGIC %md
-- MAGIC ## Conferência: integridade
-- MAGIC
-- MAGIC A view deve ter uma linha por dia da silver, e `variacao_*_pct` só pode ser `NULL` onde `semanas_na_base < 4` (as primeiras 4 semanas de cada dia da semana).
-- COMMAND ----------
SELECT
  (
    SELECT
      COUNT(*)
    FROM
      pix.silver.pix_diario
  ) AS linhas_silver,
  COUNT(*) AS linhas_view,
  SUM(
    CASE
      WHEN semanas_na_base < 4 THEN 1
      ELSE 0
    END
  ) AS sem_base_completa,
  SUM(
    CASE
      WHEN semanas_na_base = 4
      AND variacao_quantidade_pct IS NULL THEN 1
      ELSE 0
    END
  ) AS nulos_inesperados
FROM
  pix.gold.variacao_vs_semanas_anteriores;