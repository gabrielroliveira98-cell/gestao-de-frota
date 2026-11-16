-- =====================================================================
-- 01_criar_tabelas.sql
-- Cria o banco em duas camadas:
--   stg_*            -> STAGING: cópia fiel dos CSVs brutos (sem regras,
--                       sem chave primária, porque o bruto tem duplicatas)
--   dim_* / fato_*   -> MODELO ESTRELA: dados tratados, com PK, FK e CHECK
--
-- Banco: SQLite 3.25+ (Window Functions).
-- No PostgreSQL: troque TEXT de datas por DATE e REAL por NUMERIC(12,2).
-- =====================================================================

PRAGMA foreign_keys = ON;  -- no SQLite as FKs só são validadas com isso ligado

-- Apaga na ordem inversa das dependências (fatos antes das dimensões)
DROP TABLE IF EXISTS fato_viagem;
DROP TABLE IF EXISTS fato_manutencao;
DROP TABLE IF EXISTS fato_multa;
DROP TABLE IF EXISTS fato_ausencia;
DROP TABLE IF EXISTS dim_veiculo;
DROP TABLE IF EXISTS dim_motorista;
DROP TABLE IF EXISTS dim_calendario;
DROP TABLE IF EXISTS stg_veiculos;
DROP TABLE IF EXISTS stg_motoristas;
DROP TABLE IF EXISTS stg_viagens;
DROP TABLE IF EXISTS stg_manutencoes;
DROP TABLE IF EXISTS stg_multas;
DROP TABLE IF EXISTS stg_ausencias;

-- ---------------------------------------------------------------------
-- CAMADA STAGING (espelho dos CSVs)
-- ---------------------------------------------------------------------
CREATE TABLE stg_veiculos (
    veiculo_id        INTEGER,
    placa             TEXT,
    tipo              TEXT,
    marca             TEXT,
    modelo            TEXT,
    ano_fabricacao    INTEGER,
    base_operacional  TEXT,
    data_baixa        TEXT,
    status            TEXT
);

CREATE TABLE stg_motoristas (
    motorista_id   INTEGER,
    nome           TEXT,
    turno          TEXT,
    categoria_cnh  TEXT,
    data_admissao  TEXT
);

CREATE TABLE stg_viagens (
    viagem_id           INTEGER,
    data                TEXT,
    veiculo_id          INTEGER,
    motorista_id        INTEGER,
    km_rodado           REAL,
    horas_trabalhadas   REAL,
    litros_combustivel  REAL
);

CREATE TABLE stg_manutencoes (
    manutencao_id    INTEGER,
    veiculo_id       INTEGER,
    data_entrada     TEXT,
    tipo_manutencao  TEXT,
    servico          TEXT,
    oficina          TEXT,
    custo            REAL,
    dias_parado      INTEGER
);

CREATE TABLE stg_multas (
    multa_id      INTEGER,
    data          TEXT,
    veiculo_id    INTEGER,
    motorista_id  INTEGER,
    infracao      TEXT,
    gravidade     TEXT,
    pontos        INTEGER,
    valor         REAL,
    status        TEXT
);

CREATE TABLE stg_ausencias (
    ausencia_id      INTEGER,
    motorista_id     INTEGER,
    data             TEXT,
    tipo_ocorrencia  TEXT,
    motivo           TEXT,
    minutos_atraso   INTEGER,
    justificada      TEXT
);

-- ---------------------------------------------------------------------
-- DIMENSÕES
-- ---------------------------------------------------------------------
CREATE TABLE dim_calendario (
    data            TEXT PRIMARY KEY,           -- 'AAAA-MM-DD'
    ano             INTEGER NOT NULL,
    mes             INTEGER NOT NULL,
    nome_mes        TEXT    NOT NULL,
    ano_mes         TEXT    NOT NULL,           -- '2025-01' (ótimo para ordenar)
    trimestre       INTEGER NOT NULL,
    dia_semana_num  INTEGER NOT NULL,           -- 0 = domingo ... 6 = sábado
    dia_semana      TEXT    NOT NULL,
    fim_de_semana   INTEGER NOT NULL CHECK (fim_de_semana IN (0, 1))
);

CREATE TABLE dim_veiculo (
    veiculo_id        INTEGER PRIMARY KEY,
    placa             TEXT    NOT NULL UNIQUE,
    tipo              TEXT    NOT NULL CHECK (tipo IN ('Coleta', 'Hidrojato', 'Pipa')),
    marca             TEXT    NOT NULL,
    modelo            TEXT    NOT NULL,
    ano_fabricacao    INTEGER NOT NULL,
    idade_anos        INTEGER NOT NULL,         -- coluna derivada: 2025 - ano
    faixa_idade       TEXT    NOT NULL,         -- coluna derivada: agrupa a idade
    base_operacional  TEXT    NOT NULL,
    data_baixa        TEXT,                     -- nulo = continua na frota
    status            TEXT    NOT NULL CHECK (status IN ('Ativo', 'Em manutenção', 'Inativo'))
);

CREATE TABLE dim_motorista (
    motorista_id   INTEGER PRIMARY KEY,
    nome           TEXT NOT NULL,
    turno          TEXT NOT NULL,
    categoria_cnh  TEXT NOT NULL CHECK (categoria_cnh IN ('D', 'E')),
    data_admissao  TEXT NOT NULL
);

-- ---------------------------------------------------------------------
-- FATOS
-- obs_tratamento: registra o que foi corrigido na linha (rastreabilidade)
-- Obs.: CHECK aceita NULL. "litros > 0" barra zero, mas permite vazio.
-- ---------------------------------------------------------------------
CREATE TABLE fato_viagem (
    viagem_id           INTEGER PRIMARY KEY,
    data                TEXT    NOT NULL REFERENCES dim_calendario (data),
    veiculo_id          INTEGER NOT NULL REFERENCES dim_veiculo (veiculo_id),
    motorista_id        INTEGER NOT NULL REFERENCES dim_motorista (motorista_id),
    km_rodado           REAL    NOT NULL CHECK (km_rodado > 0 AND km_rodado < 300),
    horas_trabalhadas   REAL             CHECK (horas_trabalhadas > 0),
    litros_combustivel  REAL             CHECK (litros_combustivel > 0),
    obs_tratamento      TEXT
);

CREATE TABLE fato_manutencao (
    manutencao_id    INTEGER PRIMARY KEY,
    data_entrada     TEXT    NOT NULL REFERENCES dim_calendario (data),
    veiculo_id       INTEGER NOT NULL REFERENCES dim_veiculo (veiculo_id),
    tipo_manutencao  TEXT    NOT NULL CHECK (tipo_manutencao IN ('Preventiva', 'Corretiva')),
    servico          TEXT    NOT NULL,
    oficina          TEXT    NOT NULL,
    custo            REAL             CHECK (custo > 0),
    dias_parado      INTEGER NOT NULL CHECK (dias_parado > 0),
    obs_tratamento   TEXT
);

CREATE TABLE fato_multa (
    multa_id        INTEGER PRIMARY KEY,
    data            TEXT    NOT NULL REFERENCES dim_calendario (data),
    veiculo_id      INTEGER NOT NULL REFERENCES dim_veiculo (veiculo_id),
    motorista_id    INTEGER          REFERENCES dim_motorista (motorista_id), -- pode ser nulo
    infracao        TEXT    NOT NULL,
    gravidade       TEXT    NOT NULL,
    pontos          INTEGER NOT NULL,
    valor           REAL    NOT NULL CHECK (valor > 0),
    status          TEXT    NOT NULL CHECK (status IN ('Paga', 'Pendente', 'Em recurso', 'Cancelada')),
    obs_tratamento  TEXT
);

CREATE TABLE fato_ausencia (
    ausencia_id      INTEGER PRIMARY KEY,
    data             TEXT    NOT NULL REFERENCES dim_calendario (data),
    motorista_id     INTEGER NOT NULL REFERENCES dim_motorista (motorista_id),
    tipo_ocorrencia  TEXT    NOT NULL CHECK (tipo_ocorrencia IN ('Falta', 'Atraso')),
    motivo           TEXT    NOT NULL,
    minutos_atraso   INTEGER          CHECK (minutos_atraso BETWEEN 1 AND 240),
    justificada      TEXT    NOT NULL CHECK (justificada IN ('Sim', 'Não')),
    obs_tratamento   TEXT
);

-- Índices nas chaves estrangeiras: aceleram os JOINs das análises
CREATE INDEX ix_viagem_veiculo     ON fato_viagem (veiculo_id);
CREATE INDEX ix_viagem_motorista   ON fato_viagem (motorista_id);
CREATE INDEX ix_viagem_data        ON fato_viagem (data);
CREATE INDEX ix_manutencao_veiculo ON fato_manutencao (veiculo_id);
CREATE INDEX ix_multa_motorista    ON fato_multa (motorista_id);
CREATE INDEX ix_ausencia_motorista ON fato_ausencia (motorista_id);
