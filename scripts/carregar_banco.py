"""
carregar_banco.py
=================
Monta o banco SQLite do projeto a partir dos CSVs brutos.

Passo a passo:
    1. Apaga e recria data/frota.db
    2. Executa queries/01_criar_tabelas.sql   (staging + modelo estrela)
    3. Carrega data/raw/*.csv nas tabelas stg_*
    4. Executa queries/03_tratamento_dados.sql (limpeza -> dim_* / fato_*)
    5. Exporta as tabelas limpas para data/processed/*.csv (usadas no Power BI)

O SQLite já vem com o Python: não precisa instalar servidor de banco.

Uso:
    python scripts/carregar_banco.py
"""

import sqlite3
import sys
from pathlib import Path

import pandas as pd

RAIZ = Path(__file__).resolve().parent.parent
PASTA_RAW = RAIZ / "data" / "raw"
PASTA_PROCESSED = RAIZ / "data" / "processed"
PASTA_QUERIES = RAIZ / "queries"
BANCO = RAIZ / "data" / "frota.db"

# arquivo CSV -> tabela de staging
CARGA = {
    "veiculos.csv": "stg_veiculos",
    "motoristas.csv": "stg_motoristas",
    "viagens.csv": "stg_viagens",
    "manutencoes.csv": "stg_manutencoes",
    "multas.csv": "stg_multas",
    "ausencias.csv": "stg_ausencias",
}

TABELAS_MODELO = ["dim_calendario", "dim_veiculo", "dim_motorista",
                  "fato_viagem", "fato_manutencao", "fato_multa", "fato_ausencia"]


def executar_script(con: sqlite3.Connection, arquivo: Path) -> None:
    print(f"Executando {arquivo.relative_to(RAIZ)}")
    con.executescript(arquivo.read_text(encoding="utf-8"))


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")

    if BANCO.exists():
        BANCO.unlink()
    con = sqlite3.connect(BANCO)
    con.execute("PRAGMA foreign_keys = ON")

    executar_script(con, PASTA_QUERIES / "01_criar_tabelas.sql")

    print("Carregando CSVs brutos na staging...")
    for arquivo, tabela in CARGA.items():
        # Datas continuam texto 'AAAA-MM-DD' (o pandas só converte se pedirmos)
        df = pd.read_csv(PASTA_RAW / arquivo)
        df.to_sql(tabela, con, if_exists="append", index=False)
        print(f"  {tabela:<17}{len(df):>7} linhas")

    executar_script(con, PASTA_QUERIES / "03_tratamento_dados.sql")
    con.commit()

    # Confere integridade referencial (deve vir vazio)
    problemas_fk = con.execute("PRAGMA foreign_key_check").fetchall()
    if problemas_fk:
        raise RuntimeError(f"Violação de chave estrangeira: {problemas_fk[:5]}")

    print("\nModelo estrela carregado e exportado para data/processed/:")
    PASTA_PROCESSED.mkdir(parents=True, exist_ok=True)
    for tabela in TABELAS_MODELO:
        df = pd.read_sql(f"SELECT * FROM {tabela}", con)
        df.to_csv(PASTA_PROCESSED / f"{tabela}.csv", index=False, encoding="utf-8")
        print(f"  {tabela:<17}{len(df):>7} linhas")

    con.close()
    print(f"\nBanco pronto: {BANCO.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
