"""
gerar_sistema_local.py
======================
Gera sistema/controle_de_frota_local.html: a versão do sistema de lançamentos
que abre direto no navegador (duplo clique), sem depender do claude.ai.

- Usa o mesmo código de sistema/controle_de_frota.html.
- Embute os dados de exemplo de 2025 inteiros, lidos de data/frota.db.
- Os lançamentos feitos na página ficam salvos no navegador (localStorage).

Uso (depois de rodar carregar_banco.py):
    python scripts/gerar_sistema_local.py
"""

import json
import sqlite3
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
BANCO = RAIZ / "data" / "frota.db"
ORIGEM = RAIZ / "sistema" / "controle_de_frota.html"
DESTINO = RAIZ / "sistema" / "controle_de_frota_local.html"
CRIADO_EM = "2026-01-01T00:00:00Z"


def carregar_exemplo(con: sqlite3.Connection) -> dict:
    con.row_factory = sqlite3.Row
    ex = {"veiculos": {}, "motoristas": {}, "manutencoes": {}, "multas": {}, "ocorrencias": {}}
    mid = lambda i: "m%02d" % i if i is not None else None

    for r in con.execute("SELECT * FROM dim_veiculo"):
        ex["veiculos"][r["placa"]] = {
            "placa": r["placa"], "tipo": r["tipo"], "marca": r["marca"], "modelo": r["modelo"],
            "ano": r["ano_fabricacao"], "base": r["base_operacional"], "status": r["status"], "criadoEm": CRIADO_EM}
    for r in con.execute("SELECT * FROM dim_motorista"):
        ex["motoristas"][mid(r["motorista_id"])] = {
            "nome": r["nome"], "turno": r["turno"], "cnh": r["categoria_cnh"],
            "admissao": r["data_admissao"], "status": "Ativo", "criadoEm": CRIADO_EM}
    for r in con.execute("SELECT m.*, v.placa FROM fato_manutencao m JOIN dim_veiculo v USING (veiculo_id)"):
        ex["manutencoes"]["man-%d" % r["manutencao_id"]] = {
            "data": r["data_entrada"], "placa": r["placa"], "tipo": r["tipo_manutencao"], "servico": r["servico"],
            "oficina": r["oficina"], "custo": r["custo"], "dias": r["dias_parado"], "criadoEm": CRIADO_EM}
    for r in con.execute("SELECT m.*, v.placa FROM fato_multa m JOIN dim_veiculo v USING (veiculo_id)"):
        ex["multas"]["mul-%d" % r["multa_id"]] = {
            "data": r["data"], "placa": r["placa"], "motoristaId": mid(r["motorista_id"]), "infracao": r["infracao"],
            "gravidade": r["gravidade"], "pontos": r["pontos"], "valor": r["valor"], "status": r["status"], "criadoEm": CRIADO_EM}
    for r in con.execute("SELECT * FROM fato_ausencia"):
        ex["ocorrencias"]["oco-%d" % r["ausencia_id"]] = {
            "data": r["data"], "motoristaId": mid(r["motorista_id"]), "tipo": r["tipo_ocorrencia"], "motivo": r["motivo"],
            "minutos": r["minutos_atraso"], "justificada": r["justificada"] == "Sim", "criadoEm": CRIADO_EM}
    return ex


def main() -> None:
    pagina = ORIGEM.read_text(encoding="utf-8")
    with sqlite3.connect(BANCO) as con:
        exemplo = carregar_exemplo(con)

    # "</" escapado para o JSON não fechar a tag <script> por acidente
    dados = json.dumps(exemplo, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    script_dados = f"<script>window.FROTA_EXEMPLO = {dados};</script>\n"
    pos = pagina.index("<script>")
    corpo = pagina[:pos] + script_dados + pagina[pos:]

    html = (
        '<!doctype html>\n<html lang="pt-BR">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">\n'
        "<style>body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style>\n"
        "</head>\n<body>\n" + corpo + "\n</body>\n</html>\n"
    )
    DESTINO.write_text(html, encoding="utf-8")
    print(f"Gerado: {DESTINO.relative_to(RAIZ)} ({len(html) // 1024} KB)")
    for nome, docs in exemplo.items():
        print(f"  {nome:<12}{len(docs):>5} registros")


if __name__ == "__main__":
    main()
