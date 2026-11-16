"""
gerar_dados.py
==============
Gera os dados FICTÍCIOS do projeto "Dashboard de Gestão de Frota".

Cenário: empresa fictícia de limpeza urbana em São Paulo, com caminhões de
coleta, hidrojato e pipa, operando de 01/01/2025 a 31/12/2025.

Saída: 6 arquivos CSV em data/raw/
    veiculos.csv, motoristas.csv, manutencoes.csv,
    ausencias.csv, viagens.csv, multas.csv

Os dados são:
- REPRODUZÍVEIS: seed fixa -> rodar de novo gera exatamente os mesmos arquivos.
- COERENTES: caminhão parado em manutenção não roda; motorista que faltou
  não dirige; multa só existe em dia/veículo/motorista que de fato rodou.
- SAZONAIS: hidrojato trabalha mais na época de chuvas, pipa na seca,
  coleta cresce nas festas de fim de ano, faltas sobem no Carnaval.
- "SUJOS" DE PROPÓSITO: nulos, outliers, duplicatas e textos inconsistentes
  (ver função `sujar_dados`) para praticar limpeza no SQL / Power Query.

Nenhum dado real de empresa ou pessoa é usado. Nomes vêm do Faker e placas
são sorteadas aleatoriamente.

Uso:
    python scripts/gerar_dados.py
"""

from pathlib import Path

import numpy as np
import pandas as pd
from faker import Faker

# ---------------------------------------------------------------------------
# 1. CONFIGURAÇÕES GERAIS
# ---------------------------------------------------------------------------
SEED = 42
DATA_INICIO = pd.Timestamp("2025-01-01")
DATA_FIM = pd.Timestamp("2025-12-31")
ANO_REFERENCIA = 2025  # usado para calcular a idade da frota

N_VEICULOS_POR_TIPO = {"Coleta": 22, "Hidrojato": 8, "Pipa": 10}  # 40 no total
N_MOTORISTAS = 55  # 40 titulares + 15 reservas/folguistas

PASTA_SAIDA = Path(__file__).resolve().parent.parent / "data" / "raw"

rng = np.random.default_rng(SEED)  # gerador do NumPy (todas as sorteios)
Faker.seed(SEED)
fake = Faker("pt_BR")

# Modelos de caminhão por tipo de operação (marca, modelo)
CATALOGO_MODELOS = {
    "Coleta": [("Volkswagen", "Constellation 24.280"),
               ("Mercedes-Benz", "Atego 2430"),
               ("Volvo", "VM 270")],
    "Hidrojato": [("Mercedes-Benz", "Atego 1719"),
                  ("Volkswagen", "Delivery 11.180"),
                  ("Iveco", "Tector 170E28")],
    "Pipa": [("Volkswagen", "Constellation 17.190"),
             ("Mercedes-Benz", "Atego 1719"),
             ("Iveco", "Tector 240E30")],
}

# Parâmetros operacionais por tipo.
# kml = km por litro de um caminhão NOVO. Hidrojato e coleta gastam mais
# porque a bomba/compactador consome diesel com o caminhão parado (tomada de força).
PARAMS_TIPO = {
    "Coleta":    {"km_media": 85, "km_dp": 18, "kml": 2.2, "horas_media": 8.5,
                  "custo_prev": (1200, 2800)},
    "Hidrojato": {"km_media": 55, "km_dp": 15, "kml": 1.8, "horas_media": 8.0,
                  "custo_prev": (1500, 3500)},
    "Pipa":      {"km_media": 70, "km_dp": 20, "kml": 3.0, "horas_media": 7.5,
                  "custo_prev": (1000, 2400)},
}

# Sazonalidade da demanda (multiplicador sobre a probabilidade de operar).
# Hidrojato: desobstrução de bueiros/galerias na época de chuvas (nov-mar).
# Pipa: lavagem de vias e umectação na estiagem (jun-set).
# Coleta: aumento de resíduos nas festas de fim de ano e férias de verão.
SAZONALIDADE_OPERACAO = {
    "Coleta":    {1: 1.10, 2: 1.05, 3: 1.00, 4: 0.95, 5: 0.95, 6: 0.95,
                  7: 0.95, 8: 0.95, 9: 1.00, 10: 1.00, 11: 1.05, 12: 1.15},
    "Hidrojato": {1: 1.35, 2: 1.30, 3: 1.20, 4: 0.95, 5: 0.85, 6: 0.75,
                  7: 0.75, 8: 0.75, 9: 0.85, 10: 1.00, 11: 1.15, 12: 1.30},
    "Pipa":      {1: 0.75, 2: 0.75, 3: 0.85, 4: 0.95, 5: 1.05, 6: 1.20,
                  7: 1.35, 8: 1.40, 9: 1.30, 10: 1.05, 11: 0.85, 12: 0.80},
}

# Mais quebras no verão (calor + chuva + mais horas de operação)
SAZONALIDADE_CORRETIVA = {1: 1.25, 2: 1.25, 3: 1.15, 4: 1.0, 5: 0.9, 6: 0.9,
                          7: 0.9, 8: 0.9, 9: 0.95, 10: 1.0, 11: 1.1, 12: 1.2}

# Faltas: pico no Carnaval (março/2025) e em dezembro.
SAZONALIDADE_FALTA = {1: 1.10, 2: 1.05, 3: 1.40, 4: 0.95, 5: 0.90, 6: 0.95,
                      7: 1.00, 8: 0.90, 9: 0.90, 10: 0.95, 11: 1.05, 12: 1.30}
# Atrasos: pico nos meses de chuva (alagamentos e trânsito em SP).
SAZONALIDADE_ATRASO = {1: 1.40, 2: 1.40, 3: 1.30, 4: 1.00, 5: 0.85, 6: 0.80,
                       7: 0.80, 8: 0.80, 9: 0.90, 10: 1.00, 11: 1.20, 12: 1.30}

# Infrações (valores reais do CTB por gravidade, em R$)
INFRACOES = [
    # (descrição, gravidade, valor, pontos, peso do sorteio)
    ("Excesso de velocidade até 20%",           "Média",      130.16, 4, 0.25),
    ("Excesso de velocidade entre 20% e 50%",   "Grave",      195.23, 5, 0.08),
    ("Avançar sinal vermelho",                  "Gravíssima", 293.47, 7, 0.10),
    ("Estacionar em local proibido",            "Média",      130.16, 4, 0.15),
    ("Desrespeitar restrição de circulação (ZMRC)", "Média",  130.16, 4, 0.10),
    ("Usar celular ao volante",                 "Gravíssima", 293.47, 7, 0.10),
    ("Transitar em faixa exclusiva de ônibus",  "Gravíssima", 293.47, 7, 0.07),
    ("Deixar de usar cinto de segurança",       "Grave",      195.23, 5, 0.15),
]


# ---------------------------------------------------------------------------
# 2. FUNÇÕES AUXILIARES
# ---------------------------------------------------------------------------
def gerar_placa() -> str:
    """Placa no padrão Mercosul (ABC1D23), sorteada aleatoriamente."""
    letras = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    return (
        "".join(rng.choice(list(letras), 3))
        + str(rng.integers(0, 10))
        + rng.choice(list(letras))
        + f"{rng.integers(0, 100):02d}"
    )


def sortear(opcoes: list, pesos: list):
    """Sorteia um item de `opcoes` respeitando `pesos` (normalizados)."""
    p = np.array(pesos, dtype=float)
    return opcoes[rng.choice(len(opcoes), p=p / p.sum())]


# ---------------------------------------------------------------------------
# 3. TABELAS DE CADASTRO (DIMENSÕES)
# ---------------------------------------------------------------------------
def gerar_veiculos() -> pd.DataFrame:
    registros = []
    placas_usadas = set()
    vid = 1
    for tipo, qtd in N_VEICULOS_POR_TIPO.items():
        for _ in range(qtd):
            placa = gerar_placa()
            while placa in placas_usadas:  # garante placa única
                placa = gerar_placa()
            placas_usadas.add(placa)

            marca, modelo = CATALOGO_MODELOS[tipo][rng.integers(0, 3)]
            registros.append({
                "veiculo_id": vid,
                "placa": placa,
                "tipo": tipo,
                "marca": marca,
                "modelo": modelo,
                "ano_fabricacao": int(rng.integers(2011, 2025)),
                "base_operacional": sortear(
                    ["Zona Norte", "Zona Sul", "Zona Leste", "Zona Oeste", "Centro"],
                    [0.22, 0.22, 0.26, 0.18, 0.12]),
                "data_baixa": pd.NaT,
            })
            vid += 1

    df = pd.DataFrame(registros)

    # Os 2 caminhões mais antigos são baixados (vendidos) durante o ano
    mais_antigos = df.sort_values("ano_fabricacao").head(2).index
    df.loc[mais_antigos[0], "data_baixa"] = pd.Timestamp("2025-08-15")
    df.loc[mais_antigos[1], "data_baixa"] = pd.Timestamp("2025-10-31")
    return df


def gerar_motoristas() -> pd.DataFrame:
    registros = []
    for mid in range(1, N_MOTORISTAS + 1):
        # Frota pesada é majoritariamente masculina, mas não exclusivamente
        if rng.random() < 0.88:
            primeiro = fake.first_name_male()
        else:
            primeiro = fake.first_name_female()
        nome = f"{primeiro} {fake.last_name()} {fake.last_name()}"

        # Os 5 últimos foram contratados durante 2025 (aparecem só depois)
        if mid > N_MOTORISTAS - 5:
            admissao = DATA_INICIO + pd.Timedelta(days=int(rng.integers(30, 270)))
        else:
            admissao = pd.Timestamp("2008-01-01") + pd.Timedelta(
                days=int(rng.integers(0, 17 * 365)))

        registros.append({
            "motorista_id": mid,
            "nome": nome,
            "turno": sortear(["Manhã", "Tarde", "Noite"], [0.45, 0.30, 0.25]),
            "categoria_cnh": sortear(["D", "E"], [0.35, 0.65]),
            "data_admissao": admissao.date(),
            # Fatores "ocultos" de comportamento: NÃO vão para o CSV,
            # servem só para criar diferenças reais entre motoristas
            "risco_multa_oculto": rng.lognormal(0, 0.6),
            "risco_ausencia_oculto": rng.lognormal(0, 0.7),
        })
    return pd.DataFrame(registros)


# ---------------------------------------------------------------------------
# 4. TABELAS DE EVENTOS (FATOS)
# ---------------------------------------------------------------------------
def gerar_manutencoes(veiculos: pd.DataFrame, datas: pd.DatetimeIndex):
    """
    Percorre o calendário dia a dia para cada veículo:
    - Preventiva a cada ~55 dias (plano de manutenção).
    - Corretiva sorteada diariamente; chance maior para caminhões velhos.
    Retorna o DataFrame e um dicionário {veiculo_id: set(datas paradas)}.
    """
    registros = []
    dias_parado_por_veiculo = {}

    pecas_comuns = ["Freios", "Suspensão", "Sistema elétrico", "Pneus",
                    "Motor", "Embreagem", "Arrefecimento"]
    pecas_especificas = {"Coleta": "Compactador hidráulico",
                         "Hidrojato": "Bomba de alta pressão",
                         "Pipa": "Bomba d'água / tanque"}

    for v in veiculos.itertuples():
        idade = ANO_REFERENCIA - v.ano_fabricacao
        fim = v.data_baixa if pd.notna(v.data_baixa) else DATA_FIM
        proxima_preventiva = DATA_INICIO + pd.Timedelta(days=int(rng.integers(0, 50)))
        livre_a_partir = DATA_INICIO
        parado = set()

        for d in datas:
            if d > fim:
                break
            if d < livre_a_partir:  # ainda está na oficina
                continue

            if d >= proxima_preventiva:
                tipo = "Preventiva"
                servico = sortear(["Revisão (óleo e filtros)", "Revisão de freios",
                                   "Lubrificação geral", "Alinhamento e balanceamento"],
                                  [0.5, 0.2, 0.2, 0.1])
                lo, hi = PARAMS_TIPO[v.tipo]["custo_prev"]
                custo = rng.uniform(lo, hi) * (1 + 0.03 * idade)
                dias = int(sortear([1, 2], [0.7, 0.3]))
                oficina = sortear(["Oficina interna", "Concessionária"], [0.7, 0.3])
                proxima_preventiva = d + pd.Timedelta(days=int(rng.normal(55, 8)))
            else:
                # Probabilidade diária de quebra: cresce 12% a cada ano de idade
                p = 0.005 * (1 + 0.12 * idade) * SAZONALIDADE_CORRETIVA[d.month]
                if rng.random() >= p:
                    continue
                tipo = "Corretiva"
                servico = sortear(pecas_comuns + [pecas_especificas[v.tipo]],
                                  [0.18, 0.14, 0.14, 0.14, 0.08, 0.07, 0.08, 0.17])
                # Custo com distribuição log-normal (muitos baratos, poucos caros)
                custo = rng.lognormal(np.log(4500), 0.6) * (1 + 0.04 * idade)
                if servico == "Motor":
                    custo *= 2.5
                dias = int(2 + rng.poisson(2 + idade * 0.25))
                oficina = sortear(["Oficina interna", "Concessionária",
                                   "Oficina terceirizada"], [0.35, 0.30, 0.35])

            for k in range(dias):
                parado.add(d + pd.Timedelta(days=k))
            livre_a_partir = d + pd.Timedelta(days=dias)

            registros.append({
                "veiculo_id": v.veiculo_id,
                "data_entrada": d.date(),
                "tipo_manutencao": tipo,
                "servico": servico,
                "oficina": oficina,
                "custo": round(custo, 2),
                "dias_parado": dias,
            })

        dias_parado_por_veiculo[v.veiculo_id] = parado

    df = pd.DataFrame(registros).sort_values(["data_entrada", "veiculo_id"])
    df.insert(0, "manutencao_id", range(1, len(df) + 1))
    return df, dias_parado_por_veiculo


def gerar_ausencias(motoristas: pd.DataFrame, datas: pd.DatetimeIndex):
    """Faltas e atrasos de segunda a sábado. Retorna o DataFrame,
    o conjunto de (motorista, data) com falta e um dict de atrasos."""
    registros = []
    faltas = set()
    atrasos = {}

    for m in motoristas.itertuples():
        admissao = pd.Timestamp(m.data_admissao)
        for d in datas:
            if d < admissao or d.dayofweek == 6:  # domingo = escala reduzida
                continue

            p_falta = 0.010 * m.risco_ausencia_oculto * SAZONALIDADE_FALTA[d.month]
            p_atraso = 0.022 * m.risco_ausencia_oculto * SAZONALIDADE_ATRASO[d.month]
            sorteio = rng.random()

            if sorteio < p_falta:
                motivo = sortear(["Atestado médico", "Falta injustificada",
                                  "Problema familiar", "Consulta/exame médico"],
                                 [0.45, 0.30, 0.15, 0.10])
                registros.append({
                    "motorista_id": m.motorista_id, "data": d.date(),
                    "tipo_ocorrencia": "Falta", "motivo": motivo,
                    "minutos_atraso": np.nan,
                    "justificada": "Sim" if motivo in ("Atestado médico",
                                                       "Consulta/exame médico") else "Não",
                })
                faltas.add((m.motorista_id, d))

            elif sorteio < p_falta + p_atraso:
                chuva = SAZONALIDADE_ATRASO[d.month] > 1.1
                motivo = sortear(["Trânsito", "Transporte público",
                                  "Problema pessoal", "Chuva/alagamento"],
                                 [0.40, 0.25, 0.20, 0.25 if chuva else 0.05])
                minutos = int(min(180, 10 + rng.exponential(20)))
                registros.append({
                    "motorista_id": m.motorista_id, "data": d.date(),
                    "tipo_ocorrencia": "Atraso", "motivo": motivo,
                    "minutos_atraso": minutos,
                    "justificada": "Sim" if motivo == "Chuva/alagamento" else "Não",
                })
                atrasos[(m.motorista_id, d)] = minutos

    df = pd.DataFrame(registros).sort_values(["data", "motorista_id"])
    df.insert(0, "ausencia_id", range(1, len(df) + 1))
    return df, faltas, atrasos


def gerar_viagens(veiculos, motoristas, datas, dias_parado, faltas, atrasos):
    """Uma linha = um veículo operando um turno em um dia (rota diária)."""
    # Cada veículo ativo tem um motorista titular (contratados antes de 2025)
    veteranos = motoristas.loc[pd.to_datetime(motoristas["data_admissao"]) < DATA_INICIO,
                               "motorista_id"].to_numpy()
    titulares = rng.choice(veteranos, size=len(veiculos), replace=False)
    titular_do_veiculo = dict(zip(veiculos["veiculo_id"], titulares))
    admissao = dict(zip(motoristas["motorista_id"],
                        pd.to_datetime(motoristas["data_admissao"])))

    registros = []
    for d in datas:
        # 1) Quais veículos operam hoje?
        operando = []
        for v in veiculos.itertuples():
            if pd.notna(v.data_baixa) and d > v.data_baixa:
                continue
            if d in dias_parado[v.veiculo_id]:
                continue
            p = 0.82 * SAZONALIDADE_OPERACAO[v.tipo][d.month]
            if d.dayofweek == 6:
                p *= 0.5  # domingo com escala reduzida
            if rng.random() < min(p, 0.97):
                operando.append(v)

        # 2) Motoristas disponíveis hoje (admitidos e sem falta)
        disponiveis = {mid for mid, adm in admissao.items()
                       if adm <= d and (mid, d) not in faltas}

        # 3) Titular dirige o próprio caminhão; se faltou, entra um reserva
        alocacao = {}
        for v in operando:
            t = titular_do_veiculo[v.veiculo_id]
            if t in disponiveis:
                alocacao[v.veiculo_id] = t
                disponiveis.discard(t)
        for v in operando:
            if v.veiculo_id not in alocacao and disponiveis:
                reserva = int(rng.choice(sorted(disponiveis)))
                alocacao[v.veiculo_id] = reserva
                disponiveis.discard(reserva)

        # 4) Métricas da operação
        for v in operando:
            if v.veiculo_id not in alocacao:
                continue  # sem motorista disponível: rota não saiu
            mid = alocacao[v.veiculo_id]
            prm = PARAMS_TIPO[v.tipo]
            idade = ANO_REFERENCIA - v.ano_fabricacao
            fator_saz = SAZONALIDADE_OPERACAO[v.tipo][d.month]

            km = max(15, rng.normal(prm["km_media"], prm["km_dp"])
                     * (1 + (fator_saz - 1) * 0.5))
            horas = float(np.clip(rng.normal(prm["horas_media"], 1.0), 4, 12))
            horas -= atrasos.get((mid, d), 0) / 60  # atraso reduz a jornada
            # Caminhões velhos gastam mais: -1,2% de eficiência por ano de idade
            kml_real = prm["kml"] * (1 - 0.012 * idade) * rng.normal(1, 0.07)
            litros = km / kml_real

            registros.append({
                "data": d.date(),
                "veiculo_id": v.veiculo_id,
                "motorista_id": mid,
                "km_rodado": round(km, 1),
                "horas_trabalhadas": round(horas, 2),
                "litros_combustivel": round(litros, 1),
            })

    df = pd.DataFrame(registros)
    df.insert(0, "viagem_id", range(1, len(df) + 1))
    return df


def gerar_multas(viagens: pd.DataFrame, motoristas: pd.DataFrame) -> pd.DataFrame:
    """Sorteia infrações em cima das viagens que realmente aconteceram."""
    risco = dict(zip(motoristas["motorista_id"], motoristas["risco_multa_oculto"]))
    p = 0.016 * viagens["motorista_id"].map(risco)
    multadas = viagens[rng.random(len(viagens)) < p]

    descricoes = [i[0] for i in INFRACOES]
    pesos = [i[4] for i in INFRACOES]
    info = {i[0]: i for i in INFRACOES}

    registros = []
    for row in multadas.itertuples():
        infracao = sortear(descricoes, pesos)
        _, gravidade, valor, pontos, _ = info[infracao]
        # Multas recentes ainda não tiveram tempo de ser pagas
        recente = pd.Timestamp(row.data) >= pd.Timestamp("2025-11-01")
        status = sortear(["Paga", "Pendente", "Em recurso", "Cancelada"],
                         [0.25, 0.60, 0.12, 0.03] if recente else
                         [0.65, 0.15, 0.12, 0.08])
        registros.append({
            "data": row.data,
            "veiculo_id": row.veiculo_id,
            "motorista_id": row.motorista_id,
            "infracao": infracao,
            "gravidade": gravidade,
            "pontos": pontos,
            "valor": valor,
            "status": status,
        })

    df = pd.DataFrame(registros)
    df.insert(0, "multa_id", range(1, len(df) + 1))
    return df


# ---------------------------------------------------------------------------
# 5. "SUJANDO" OS DADOS (para praticar limpeza)
# ---------------------------------------------------------------------------
def sujar_dados(tabelas: dict) -> dict:
    """
    Insere problemas típicos de base operacional real.
    Spoiler: se quiser descobrir sozinho(a) na etapa de limpeza,
    não leia esta função agora. :)
    """
    veic = tabelas["veiculos"]
    mot = tabelas["motoristas"]
    manut = tabelas["manutencoes"]
    aus = tabelas["ausencias"]
    viag = tabelas["viagens"]
    mult = tabelas["multas"]

    # --- veiculos: placas digitadas em minúsculo e modelo não informado
    idx = rng.choice(veic.index, 3, replace=False)
    veic.loc[idx, "placa"] = veic.loc[idx, "placa"].str.lower()
    veic.loc[rng.choice(veic.index, 1), "modelo"] = np.nan

    # --- motoristas: turno não cadastrado
    mot.loc[rng.choice(mot.index, 2, replace=False), "turno"] = np.nan

    # --- manutencoes: texto inconsistente, custo nulo e outliers
    idx = rng.choice(manut.index, int(len(manut) * 0.04), replace=False)
    manut.loc[idx, "tipo_manutencao"] = (
        manut.loc[idx, "tipo_manutencao"].str.upper() + " ")  # "CORRETIVA "
    manut.loc[rng.choice(manut.index, 5, replace=False), "custo"] = np.nan
    # Outlier LEGÍTIMO: retífica completa de motor (cara, mas real)
    i = manut[manut["tipo_manutencao"] == "Corretiva"].index[3]
    manut.loc[i, ["servico", "custo", "dias_parado"]] = ["Motor", 78500.00, 21]
    # Outlier de DIGITAÇÃO: vírgula no lugar errado (x100)
    i = manut[manut["tipo_manutencao"] == "Preventiva"].index[10]
    manut.loc[i, "custo"] = manut.loc[i, "custo"] * 100

    # --- viagens: nulos, erros de digitação e linhas duplicadas
    viag.loc[rng.choice(viag.index, int(len(viag) * 0.02), replace=False),
             "litros_combustivel"] = np.nan
    viag.loc[rng.choice(viag.index, int(len(viag) * 0.01), replace=False),
             "horas_trabalhadas"] = np.nan
    idx = rng.choice(viag.index, 8, replace=False)
    viag.loc[idx, "km_rodado"] = viag.loc[idx, "km_rodado"] * 10  # 85 -> 850
    viag.loc[rng.choice(viag.index, 4, replace=False), "litros_combustivel"] = 0
    duplicadas = viag.loc[rng.choice(viag.index, 25, replace=False)]
    viag = pd.concat([viag, duplicadas]).sort_values("viagem_id")

    # --- ausencias: atraso absurdo (provável erro: 600 min = 10h)
    i = aus[aus["tipo_ocorrencia"] == "Atraso"].index[5]
    aus.loc[i, "minutos_atraso"] = 600

    # --- multas: condutor não identificado e valor em branco
    mult.loc[rng.choice(mult.index, int(len(mult) * 0.06), replace=False),
             "motorista_id"] = np.nan
    mult.loc[rng.choice(mult.index, 2, replace=False), "valor"] = np.nan

    tabelas.update(veiculos=veic, motoristas=mot, manutencoes=manut,
                   ausencias=aus, viagens=viag, multas=mult)
    return tabelas


# ---------------------------------------------------------------------------
# 6. EXECUÇÃO
# ---------------------------------------------------------------------------
def main():
    datas = pd.date_range(DATA_INICIO, DATA_FIM, freq="D")

    print("Gerando cadastros...")
    veiculos = gerar_veiculos()
    motoristas = gerar_motoristas()

    print("Gerando manutenções...")
    manutencoes, dias_parado = gerar_manutencoes(veiculos, datas)

    print("Gerando ausências...")
    ausencias, faltas, atrasos = gerar_ausencias(motoristas, datas)

    print("Gerando viagens (pode levar alguns segundos)...")
    viagens = gerar_viagens(veiculos, motoristas, datas, dias_parado, faltas, atrasos)

    print("Gerando multas...")
    multas = gerar_multas(viagens, motoristas)

    # Status do veículo na data de corte (31/12/2025)
    def status(row):
        if pd.notna(row.data_baixa):
            return "Inativo"
        if DATA_FIM in dias_parado[row.veiculo_id]:
            return "Em manutenção"
        return "Ativo"
    veiculos["status"] = veiculos.apply(status, axis=1)
    veiculos["data_baixa"] = veiculos["data_baixa"].dt.date

    # Remove as colunas "ocultas" de comportamento antes de exportar
    motoristas = motoristas.drop(columns=["risco_multa_oculto", "risco_ausencia_oculto"])

    tabelas = {
        "veiculos": veiculos,
        "motoristas": motoristas,
        "manutencoes": manutencoes,
        "ausencias": ausencias,
        "viagens": viagens,
        "multas": multas,
    }
    tabelas = sujar_dados(tabelas)

    # Inteiros com nulo precisam do tipo "Int64" (com I maiúsculo) no pandas,
    # senão viram float e aparecem como 12.0 no CSV.
    tabelas["multas"]["motorista_id"] = tabelas["multas"]["motorista_id"].astype("Int64")
    tabelas["ausencias"]["minutos_atraso"] = tabelas["ausencias"]["minutos_atraso"].astype("Int64")

    PASTA_SAIDA.mkdir(parents=True, exist_ok=True)
    print(f"\nArquivos salvos em: {PASTA_SAIDA}")
    print(f"{'tabela':<14}{'linhas':>8}{'colunas':>9}{'nulos':>8}")
    for nome, df in tabelas.items():
        df.to_csv(PASTA_SAIDA / f"{nome}.csv", index=False, encoding="utf-8")
        print(f"{nome:<14}{len(df):>8}{df.shape[1]:>9}{int(df.isna().sum().sum()):>8}")


if __name__ == "__main__":
    main()
