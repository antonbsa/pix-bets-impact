# Databricks notebook source
# MAGIC %md
# MAGIC # 01 — Bronze: coleta do Pix na API do BCB
# MAGIC
# MAGIC Baixa a série diária completa de `PixLiquidadosAtual` (API Olinda do BCB) e grava o JSON **exatamente como veio** em um Volume do Unity Catalog, com a data/hora da extração no nome do arquivo.
# MAGIC
# MAGIC - Nenhum filtro de data é aplicado aqui: recortes de período pertencem às camadas silver/gold.
# MAGIC - Não é usado `$filter` na API (retorna erro 400 com datas); a série inteira é baixada com `$top=10000`.
# MAGIC - Cada execução gera um arquivo novo; arquivos anteriores nunca são sobrescritos.

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE CATALOG IF NOT EXISTS pix;
# MAGIC CREATE SCHEMA IF NOT EXISTS pix.bronze;
# MAGIC CREATE VOLUME IF NOT EXISTS pix.bronze.raw_api;

# COMMAND ----------

import json
from datetime import datetime, timezone
from pathlib import Path

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

URL = "https://olinda.bcb.gov.br/olinda/servico/SPI/versao/v1/odata/PixLiquidadosAtual"
PARAMS = {"$format": "json", "$top": 10000}  # sem $filter: a API retorna 400 com datas
TIMEOUT_SEGUNDOS = 180
DESTINO = Path("/Volumes/pix/bronze/raw_api/pix_liquidados_atual")

# COMMAND ----------

# A API é lenta e instável: a sessão refaz a requisição em falhas de rede e erros 5xx,
# esperando um tempo maior a cada tentativa (backoff exponencial).
sessao = requests.Session()
retry = Retry(
    total=3,
    backoff_factor=5,
    status_forcelist=[429, 500, 502, 503, 504],
    allowed_methods=["GET"],
)
sessao.mount("https://", HTTPAdapter(max_retries=retry))

resposta = sessao.get(URL, params=PARAMS, timeout=TIMEOUT_SEGUNDOS)
resposta.raise_for_status()  # erro HTTP interrompe aqui: nada é gravado na bronze

# Só grava se o conteúdo for JSON válido com a chave "value" (formato OData)
linhas = resposta.json()["value"]
print(f"HTTP {resposta.status_code} — {len(linhas)} linhas recebidas")

# COMMAND ----------

# Grava os bytes originais da resposta (sem re-serializar), para a bronze ficar idêntica ao que a API enviou.
extracao = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
arquivo = DESTINO / f"pix_liquidados_atual_{extracao}.json"

DESTINO.mkdir(parents=True, exist_ok=True)
arquivo.write_bytes(resposta.content)
print(f"gravado: {arquivo} ({arquivo.stat().st_size / 1024:.0f} KB)")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Conferência da extração
# MAGIC
# MAGIC Checagem do arquivo recém-gravado: quantidade de linhas, primeira e última data. Apenas leitura; nada é alterado.

# COMMAND ----------

datas = sorted(linha["Data"] for linha in json.loads(arquivo.read_text())["value"])

print(f"arquivo:        {arquivo.name}")
print(f"linhas:         {len(datas)}")
print(f"datas únicas:   {len(set(datas))}")
print(f"primeira data:  {datas[0]}")
print(f"última data:    {datas[-1]}")

if len(datas) >= PARAMS["$top"]:
    print(f"ATENÇÃO: {len(datas)} linhas = $top ({PARAMS['$top']}); a série pode ter sido truncada.")
