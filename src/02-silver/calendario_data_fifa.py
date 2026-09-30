# Databricks notebook source
# MAGIC %md
# MAGIC # 02 — Silver: `pix.silver.calendario_data_fifa`
# MAGIC
# MAGIC Carrega o seed `data/seeds/calendario_data_fifa.csv` (versionado no repositório) na silver, **sem passar pela bronze** (ver ADR 0002).
# MAGIC
# MAGIC - Uma linha por **janela** (`data_inicio` a `data_fim`, ambas inclusivas), não por dia. A expansão para dias é feita em consulta posterior, no cruzamento com `pix_diario`.
# MAGIC - `tipo` distingue `data_fifa` (pausa de seleções), `copa_do_mundo` e `torneio_continental`, para que cada análise escolha quais janelas usar.
# MAGIC - Schema explícito e leitura em modo `FAILFAST`: data inválida ou coluna faltando interrompe a carga em vez de virar `NULL` silenciosamente.
# MAGIC - Carga idempotente por **sobrescrita completa** (`INSERT OVERWRITE`): a tabela inteira vem do arquivo, então não há o que "mesclar".

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE SCHEMA IF NOT EXISTS pix.silver;
# MAGIC
# MAGIC CREATE TABLE IF NOT EXISTS pix.silver.calendario_data_fifa (
# MAGIC   data_inicio DATE   NOT NULL COMMENT 'Primeiro dia da janela (inclusivo)',
# MAGIC   data_fim    DATE   NOT NULL COMMENT 'Último dia da janela (inclusivo)',
# MAGIC   tipo        STRING NOT NULL COMMENT 'data_fifa | copa_do_mundo | torneio_continental',
# MAGIC   fonte       STRING NOT NULL COMMENT 'URL do calendário oficial da FIFA que sustenta a janela',
# MAGIC   observacao  STRING COMMENT 'Detalhes da janela (jogos por seleção, exceções por confederação)',
# MAGIC   CONSTRAINT calendario_data_fifa_pk PRIMARY KEY (data_inicio, tipo)
# MAGIC )
# MAGIC COMMENT 'Janelas do calendário internacional masculino da FIFA (2023-2026). Seed: data/seeds/calendario_data_fifa.csv';

# COMMAND ----------

import os
from pathlib import Path

from pyspark.sql import functions as F
from pyspark.sql.types import DateType, StringType, StructField, StructType

TABELA = "pix.silver.calendario_data_fifa"
TIPOS_VALIDOS = ["data_fifa", "copa_do_mundo", "torneio_continental"]

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. Leitura do seed
# MAGIC
# MAGIC Em um Git folder do Databricks, o diretório de trabalho do notebook é a pasta dele no workspace (`.../src/02-silver`). O CSV fica na raiz do repositório, dois níveis acima, e é lido com o prefixo `file:` (o Spark precisa saber que o arquivo está no sistema de arquivos do workspace, não no DBFS).
# MAGIC
# MAGIC `inferSchema` **não** é usado: a inferência lê uma amostra e pode trocar `DATE` por `STRING` se uma linha vier fora do padrão. O schema declarado documenta o contrato e falha cedo. Analogia com JS: é a diferença entre `JSON.parse` e validar com um schema (zod) logo depois.

# COMMAND ----------

RAIZ_REPO = Path(os.getcwd()).parents[1]
SEED = RAIZ_REPO / "data" / "seeds" / "calendario_data_fifa.csv"
print(f"seed: {SEED}")

schema_seed = StructType([
    StructField("data_inicio", DateType(), nullable=False),
    StructField("data_fim", DateType(), nullable=False),
    StructField("tipo", StringType(), nullable=False),
    StructField("fonte", StringType(), nullable=False),
    StructField("observacao", StringType(), nullable=True),
])

calendario = (
    spark.read
    .schema(schema_seed)
    .option("header", "true")
    .option("dateFormat", "yyyy-MM-dd")
    .option("mode", "FAILFAST")
    .csv(f"file:{SEED}")
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. Validação antes de gravar
# MAGIC
# MAGIC Se qualquer checagem falhar, o notebook para e a tabela **não** é alterada.
# MAGIC
# MAGIC - Nenhum campo obrigatório nulo (o `NOT NULL` do schema do Spark não é aplicado na leitura de CSV, por isso a checagem explícita).
# MAGIC - `data_inicio <= data_fim` em todas as linhas.
# MAGIC - `tipo` restrito ao vocabulário conhecido: um erro de digitação (`data_fiffa`) sumiria dos filtros da análise sem aviso.
# MAGIC - Chave `(data_inicio, tipo)` sem duplicidade.

# COMMAND ----------

total = calendario.count()
nulos = calendario.filter(
    F.col("data_inicio").isNull() | F.col("data_fim").isNull()
    | F.col("tipo").isNull() | F.col("fonte").isNull()
).count()
invertidas = calendario.filter(F.col("data_inicio") > F.col("data_fim")).count()
tipos_invalidos = calendario.filter(~F.col("tipo").isin(TIPOS_VALIDOS)).count()
chaves_unicas = calendario.select("data_inicio", "tipo").distinct().count()

print(f"linhas: {total} | nulos obrigatórios: {nulos} | datas invertidas: {invertidas} | tipos inválidos: {tipos_invalidos}")

assert total > 0, "o seed está vazio"
assert nulos == 0, "existem campos obrigatórios nulos no seed"
assert invertidas == 0, "existem janelas com data_inicio posterior a data_fim"
assert tipos_invalidos == 0, f"tipo fora do vocabulário {TIPOS_VALIDOS}"
assert total == chaves_unicas, "existem janelas duplicadas por (data_inicio, tipo)"

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. Sobrescrita completa
# MAGIC
# MAGIC `INSERT OVERWRITE` troca todo o conteúdo da tabela em uma única transação Delta: quem consulta vê a versão antiga ou a nova, nunca uma tabela vazia no meio. Reexecutar com o mesmo CSV produz o mesmo resultado (idempotente). Como a tabela inteira vem do arquivo, `MERGE` seria complexidade sem ganho; ele faz sentido na `pix_diario`, onde a carga chega em snapshots e os dias antigos precisam ser preservados.
# MAGIC
# MAGIC A escolha de `INSERT OVERWRITE` em vez de `saveAsTable(mode="overwrite")` mantém a definição da tabela (comentários e chave primária) declarada acima.
# MAGIC
# MAGIC Simplificação didática: a alteração de uma janela no CSV substitui a linha antiga sem deixar rastro **na tabela**; o histórico das mudanças está no Git, e a tabela Delta também guarda versões anteriores (`DESCRIBE HISTORY`) pelo período de retenção.

# COMMAND ----------

calendario.createOrReplaceTempView("lote_calendario_data_fifa")

spark.sql(f"""
    INSERT OVERWRITE {TABELA}
    SELECT data_inicio, data_fim, tipo, fonte, observacao
    FROM lote_calendario_data_fifa
""")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Conferência da tabela

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT
# MAGIC   tipo,
# MAGIC   COUNT(*)         AS janelas,
# MAGIC   MIN(data_inicio) AS primeira_data,
# MAGIC   MAX(data_fim)    AS ultima_data
# MAGIC FROM pix.silver.calendario_data_fifa
# MAGIC GROUP BY tipo
# MAGIC ORDER BY tipo;

# COMMAND ----------

# MAGIC %md
# MAGIC Exemplo de como a tabela se relaciona com `pix_diario` (expansão de janela em dias com `sequence` + `explode`; em JS seria um `flatMap` sobre um intervalo de datas):

# COMMAND ----------

# MAGIC %sql
# MAGIC WITH dias_fifa AS (
# MAGIC   SELECT DISTINCT explode(sequence(data_inicio, data_fim, INTERVAL 1 DAY)) AS data
# MAGIC   FROM pix.silver.calendario_data_fifa
# MAGIC   WHERE tipo = 'data_fifa'
# MAGIC )
# MAGIC SELECT p.data, p.quantidade, (d.data IS NOT NULL) AS em_janela_fifa
# MAGIC FROM pix.silver.pix_diario AS p
# MAGIC LEFT JOIN dias_fifa AS d ON p.data = d.data
# MAGIC ORDER BY p.data DESC
# MAGIC LIMIT 14;
