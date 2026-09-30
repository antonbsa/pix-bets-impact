# Databricks notebook source
# MAGIC %md
# MAGIC # 02 — Silver: `pix.silver.pix_diario`
# MAGIC
# MAGIC Lê o snapshot **mais recente** da bronze, aplica tipagem e colunas de calendário, e carrega a tabela Delta por `MERGE` na chave `data`.
# MAGIC
# MAGIC - Uma linha por dia (`data` é a chave única).
# MAGIC - `Total` chega da API em **milhares de R$** e é convertido para reais **uma única vez**, aqui: `valor_reais = Total * 1000`.
# MAGIC - Valores monetários em `DECIMAL(18,2)`, nunca `float`.
# MAGIC - `quantidade_canal_primario` e `quantidade_canal_secundario` são `NULL` até 28/10/2023: a API não informa esses campos antes disso (`NULL` = "não informado", diferente de zero).
# MAGIC - Carga idempotente: reexecutar não duplica linhas; dias novos são inseridos e dias revisados pelo BCB são atualizados.
# MAGIC - Feriados e dia útil **não** entram nesta tabela; serão uma tabela de calendário própria, cruzada na gold.

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE SCHEMA IF NOT EXISTS pix.silver;
# MAGIC
# MAGIC CREATE TABLE IF NOT EXISTS pix.silver.pix_diario (
# MAGIC   data                        DATE          NOT NULL COMMENT 'Dia de liquidação (chave única)',
# MAGIC   quantidade                  BIGINT        COMMENT 'Quantidade de transações liquidadas no dia',
# MAGIC   quantidade_canal_primario   BIGINT        COMMENT 'Quantidade no canal primário; NULL antes de 2023-10-29',
# MAGIC   quantidade_canal_secundario BIGINT        COMMENT 'Quantidade no canal secundário; NULL antes de 2023-10-29',
# MAGIC   valor_reais                 DECIMAL(18,2) COMMENT 'Valor total liquidado no dia, em reais (API informa em milhares de R$)',
# MAGIC   valor_medio_reais           DECIMAL(18,2) COMMENT 'Valor médio por transação, em reais (campo Media da API)',
# MAGIC   ano                         INT           COMMENT 'Ano de data',
# MAGIC   mes                         INT           COMMENT 'Mês de data (1-12)',
# MAGIC   dia_do_mes                  INT           COMMENT 'Dia do mês (1-31)',
# MAGIC   dia_da_semana               INT           COMMENT 'Dia da semana ISO: 1 = segunda ... 7 = domingo',
# MAGIC   nome_dia_da_semana          STRING        COMMENT 'Nome do dia da semana em português',
# MAGIC   fim_de_semana               BOOLEAN       COMMENT 'TRUE para sábado e domingo',
# MAGIC   CONSTRAINT pix_diario_pk PRIMARY KEY (data)
# MAGIC )
# MAGIC COMMENT 'Pix liquidado por dia (BCB/SPI), tipado e com colunas de calendário. Fonte: pix.bronze.raw_api';

# COMMAND ----------

from pathlib import Path

from pyspark.sql import functions as F
from pyspark.sql.types import (
    ArrayType, DecimalType, LongType, StringType, StructField, StructType,
)

BRONZE = Path("/Volumes/pix/bronze/raw_api/pix_liquidados_atual")
TABELA = "pix.silver.pix_diario"

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. Leitura da bronze
# MAGIC
# MAGIC O arquivo é um único JSON `{"value": [ ... ]}`, então a leitura usa `multiLine=true` (o padrão do Spark espera um objeto JSON por linha) e `explode` para transformar o array em uma linha por dia.
# MAGIC
# MAGIC O schema é declarado explicitamente, em vez de inferido: a tipagem fica documentada no código e `Total` e `Media` são lidos direto como `DECIMAL`, sem passar por `double`.
# MAGIC
# MAGIC O snapshot mais recente é o último arquivo em ordem alfabética; o timestamp UTC no nome do arquivo garante que a ordem alfabética coincide com a cronológica.

# COMMAND ----------

schema_bronze = StructType([
    StructField("value", ArrayType(StructType([
        StructField("Data", StringType()),
        StructField("Quantidade", LongType()),
        StructField("CanalPrimario", LongType()),
        StructField("CanalSecundario", LongType()),
        StructField("Total", DecimalType(18, 2)),
        StructField("Media", DecimalType(18, 2)),
    ]))),
])

arquivo = sorted(BRONZE.glob("pix_liquidados_atual_*.json"))[-1]
print(f"snapshot: {arquivo.name}")

raw = (
    spark.read
    .schema(schema_bronze)
    .option("multiLine", "true")
    .json(str(arquivo))
    .select(F.explode("value").alias("linha"))
    .select("linha.*")
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. Transformação
# MAGIC
# MAGIC - `Data` (texto) → `DATE`.
# MAGIC - `Total` (milhares de R$) × 1000 → `valor_reais`. Esta é a **única** conversão de unidade do projeto.
# MAGIC - Dia da semana no padrão ISO (segunda = 1 ... domingo = 7). O `dayofweek` do Spark começa no domingo (1 = domingo), por isso o ajuste `((n + 5) % 7) + 1`.

# COMMAND ----------

dias_semana = ["segunda", "terca", "quarta", "quinta", "sexta", "sabado", "domingo"]

silver = (
    raw
    .withColumn("data", F.to_date("Data", "yyyy-MM-dd"))
    .withColumn("dia_da_semana", ((F.dayofweek("data") + 5) % 7 + 1).cast("int"))
    .select(
        "data",
        F.col("Quantidade").alias("quantidade"),
        F.col("CanalPrimario").alias("quantidade_canal_primario"),
        F.col("CanalSecundario").alias("quantidade_canal_secundario"),
        (F.col("Total") * 1000).cast(DecimalType(18, 2)).alias("valor_reais"),
        F.col("Media").alias("valor_medio_reais"),
        F.year("data").alias("ano"),
        F.month("data").alias("mes"),
        F.dayofmonth("data").alias("dia_do_mes"),
        "dia_da_semana",
        F.element_at(F.array(*[F.lit(d) for d in dias_semana]), F.col("dia_da_semana")).alias("nome_dia_da_semana"),
        (F.col("dia_da_semana") >= 6).alias("fim_de_semana"),
    )
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. Validação antes de gravar
# MAGIC
# MAGIC Se qualquer checagem falhar, o notebook para e a tabela **não** é alterada. Validar antes do `MERGE` evita gravar um lote quebrado na silver.

# COMMAND ----------

total_linhas = silver.count()
datas_unicas = silver.select("data").distinct().count()
datas_nulas = silver.filter(F.col("data").isNull()).count()
limites = silver.agg(F.min("data").alias("primeira"), F.max("data").alias("ultima")).first()

# a série é diária e contínua: o número de linhas deve ser igual ao número de dias do intervalo
dias_no_intervalo = (limites["ultima"] - limites["primeira"]).days + 1

print(f"linhas: {total_linhas} | datas únicas: {datas_unicas} | datas nulas: {datas_nulas}")
print(f"intervalo: {limites['primeira']} a {limites['ultima']} ({dias_no_intervalo} dias)")

assert datas_nulas == 0, "existem linhas com data nula ou inválida"
assert total_linhas == datas_unicas, "existem datas duplicadas no snapshot"
assert total_linhas == dias_no_intervalo, "a série tem dias faltando dentro do intervalo"

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. `MERGE` por data
# MAGIC
# MAGIC `MERGE` é um "upsert" (update + insert) numa única operação atômica: para cada linha do lote, se a `data` já existe na tabela a linha é atualizada, senão é inserida. É isso que torna a carga idempotente. Equivalente em JS: `Map.set(data, linha)`, em que chave existente é sobrescrita e chave nova é criada.
# MAGIC
# MAGIC A cláusula `WHEN MATCHED AND (...)` só reescreve linhas cujos valores mudaram. O operador `<=>` é a comparação segura para `NULL` (com `<>`, `NULL <> NULL` resulta em `NULL` e a mudança passaria despercebida).
# MAGIC
# MAGIC Dias que existam na silver mas não no snapshot **não** são removidos: a carga nunca apaga histórico.

# COMMAND ----------

silver.createOrReplaceTempView("lote_pix_diario")

resultado = spark.sql(f"""
    MERGE INTO {TABELA} AS destino
    USING lote_pix_diario AS origem
    ON destino.data = origem.data
    WHEN MATCHED AND NOT (
           destino.quantidade                  <=> origem.quantidade
       AND destino.quantidade_canal_primario   <=> origem.quantidade_canal_primario
       AND destino.quantidade_canal_secundario <=> origem.quantidade_canal_secundario
       AND destino.valor_reais                 <=> origem.valor_reais
       AND destino.valor_medio_reais           <=> origem.valor_medio_reais
    ) THEN UPDATE SET *
    WHEN NOT MATCHED THEN INSERT *
""")
resultado.show()

# COMMAND ----------

# MAGIC %md
# MAGIC ## Conferência da tabela

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT
# MAGIC   COUNT(*)                          AS linhas,
# MAGIC   MIN(data)                         AS primeira_data,
# MAGIC   MAX(data)                         AS ultima_data,
# MAGIC   COUNT(*) - COUNT(DISTINCT data)   AS duplicadas
# MAGIC FROM pix.silver.pix_diario;

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT * FROM pix.silver.pix_diario ORDER BY data DESC LIMIT 7;
