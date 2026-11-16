"""
executar_query.py
=================
Executa um arquivo .sql no banco data/frota.db e mostra o resultado de
cada consulta no terminal (útil para quem ainda não usa um cliente SQL).

Uso:
    python scripts/executar_query.py queries/analises/a01_custo_manutencao_por_veiculo.sql
    python scripts/executar_query.py --todas        (roda todas as análises)

Alternativa visual: abra data/frota.db no "DB Browser for SQLite" ou no
DBeaver e cole as consultas lá.
"""

import sqlite3
import sys
from pathlib import Path

import pandas as pd

RAIZ = Path(__file__).resolve().parent.parent
BANCO = RAIZ / "data" / "frota.db"

pd.set_option("display.width", 250)
pd.set_option("display.max_columns", 30)
pd.set_option("display.max_rows", 60)


def dividir_consultas(texto: str):
    """Separa o arquivo em consultas individuais, guardando como título
    o primeiro comentário '-- [X] ...' que aparece antes de cada uma."""
    buffer, titulo = "", None
    for linha in texto.splitlines(keepends=True):
        if linha.strip().startswith("-- [") and titulo is None:
            titulo = linha.strip("- \n")
        buffer += linha
        if sqlite3.complete_statement(buffer):
            yield titulo, buffer.strip()
            buffer, titulo = "", None


def executar_arquivo(con: sqlite3.Connection, arquivo: Path) -> None:
    print("=" * 100)
    print(f"ARQUIVO: {arquivo.relative_to(RAIZ)}")
    print("=" * 100)
    for titulo, sql in dividir_consultas(arquivo.read_text(encoding="utf-8")):
        corpo = "\n".join(l for l in sql.splitlines() if not l.strip().startswith("--"))
        primeira_palavra = corpo.strip().split()[0].upper()
        if primeira_palavra in ("SELECT", "WITH"):
            df = pd.read_sql(sql, con)
            if titulo:
                print(f"\n>> {titulo}")
            print(df.to_string(index=False) if not df.empty else "(nenhuma linha)")
            print()
        else:
            con.execute(sql)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    if not BANCO.exists():
        sys.exit("Banco não encontrado. Rode antes: python scripts/carregar_banco.py")
    if len(sys.argv) != 2:
        sys.exit(__doc__)

    con = sqlite3.connect(BANCO)
    if sys.argv[1] == "--todas":
        arquivos = sorted((RAIZ / "queries" / "analises").glob("*.sql"))
    else:
        arquivos = [Path(sys.argv[1]).resolve()]
    for arquivo in arquivos:
        executar_arquivo(con, arquivo)
    con.close()


if __name__ == "__main__":
    main()
