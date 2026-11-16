-- =====================================================================
-- 03_tratamento_dados.sql
-- Transforma staging (bruto) -> modelo estrela (limpo).
-- Cada regra de limpeza está comentada com a JUSTIFICATIVA de negócio.
-- Toda linha alterada recebe um texto em obs_tratamento (rastreabilidade).
--
-- Princípio adotado: só CORRIGIR quando há evidência clara do valor certo.
-- Quando não há (ex.: custo não lançado), manter NULO e sinalizar.
-- Inventar número para "fechar a conta" esconde problema do gestor.
-- =====================================================================

PRAGMA foreign_keys = ON;

-- Limpa o modelo para o script poder rodar várias vezes (idempotente)
DELETE FROM fato_viagem;
DELETE FROM fato_manutencao;
DELETE FROM fato_multa;
DELETE FROM fato_ausencia;
DELETE FROM dim_veiculo;
DELETE FROM dim_motorista;
DELETE FROM dim_calendario;

-- ---------------------------------------------------------------------
-- dim_calendario: gerada com CTE RECURSIVA (um dia por linha em 2025)
-- No PostgreSQL seria: SELECT generate_series('2025-01-01'::date, '2025-12-31', '1 day')
-- ---------------------------------------------------------------------
WITH RECURSIVE dias (d) AS (
    SELECT '2025-01-01'
    UNION ALL
    SELECT date(d, '+1 day') FROM dias WHERE d < '2025-12-31'
)
INSERT INTO dim_calendario
SELECT
    d,
    CAST(strftime('%Y', d) AS INTEGER),
    CAST(strftime('%m', d) AS INTEGER),
    CASE strftime('%m', d)
        WHEN '01' THEN 'Janeiro'  WHEN '02' THEN 'Fevereiro' WHEN '03' THEN 'Março'
        WHEN '04' THEN 'Abril'    WHEN '05' THEN 'Maio'      WHEN '06' THEN 'Junho'
        WHEN '07' THEN 'Julho'    WHEN '08' THEN 'Agosto'    WHEN '09' THEN 'Setembro'
        WHEN '10' THEN 'Outubro'  WHEN '11' THEN 'Novembro'  ELSE 'Dezembro'
    END,
    strftime('%Y-%m', d),
    (CAST(strftime('%m', d) AS INTEGER) + 2) / 3,          -- divisão inteira -> 1 a 4
    CAST(strftime('%w', d) AS INTEGER),
    CASE strftime('%w', d)
        WHEN '0' THEN 'Domingo' WHEN '1' THEN 'Segunda' WHEN '2' THEN 'Terça'
        WHEN '3' THEN 'Quarta'  WHEN '4' THEN 'Quinta'  WHEN '5' THEN 'Sexta'
        ELSE 'Sábado'
    END,
    CASE WHEN strftime('%w', d) IN ('0', '6') THEN 1 ELSE 0 END
FROM dias;

-- ---------------------------------------------------------------------
-- dim_veiculo
--  * placa: padroniza em MAIÚSCULAS (3 placas vieram minúsculas)
--  * modelo nulo -> 'Não informado' (dimensão não deve ter vazio:
--    no Power BI vira "(Em branco)" e confunde o usuário)
--  * cria idade e faixa de idade (essenciais para a análise de custo)
-- ---------------------------------------------------------------------
INSERT INTO dim_veiculo
SELECT
    veiculo_id,
    UPPER(TRIM(placa)),
    TRIM(tipo),
    marca,
    COALESCE(modelo, 'Não informado'),
    ano_fabricacao,
    2025 - ano_fabricacao,
    CASE
        WHEN 2025 - ano_fabricacao <= 5  THEN '1) Até 5 anos'
        WHEN 2025 - ano_fabricacao <= 10 THEN '2) 6 a 10 anos'
        ELSE                                  '3) Mais de 10 anos'
    END,                       -- prefixo numérico garante a ordem certa nos gráficos
    base_operacional,
    data_baixa,
    status
FROM stg_veiculos;

-- ---------------------------------------------------------------------
-- dim_motorista: turno nulo -> 'Não informado'
-- ---------------------------------------------------------------------
INSERT INTO dim_motorista
SELECT motorista_id, TRIM(nome), COALESCE(turno, 'Não informado'), categoria_cnh, data_admissao
FROM stg_motoristas;

-- ---------------------------------------------------------------------
-- fato_viagem
--  * DISTINCT remove as linhas duplicadas (cópias idênticas)
--  * km > 300: o maior valor plausível é ~160 km e os suspeitos começam em
--    431. Todos são ~10x o normal -> erro de digitação (vírgula perdida).
--    Corrige dividindo por 10.
--  * litros = 0: caminhão que rodou consumiu diesel -> zero é falha de
--    apontamento. Vira NULO (não sabemos o valor real).
--  * litros/horas nulos: mantidos nulos. As análises de consumo filtram.
-- ---------------------------------------------------------------------
INSERT INTO fato_viagem
SELECT DISTINCT
    viagem_id,
    data,
    veiculo_id,
    motorista_id,
    CASE WHEN km_rodado > 300 THEN ROUND(km_rodado / 10.0, 1) ELSE km_rodado END,
    horas_trabalhadas,
    CASE WHEN litros_combustivel <= 0 THEN NULL ELSE litros_combustivel END,
    CASE
        WHEN km_rodado > 300          THEN 'km corrigido (/10): erro de digitação'
        WHEN litros_combustivel <= 0  THEN 'litros zerado convertido em nulo'
        WHEN litros_combustivel IS NULL THEN 'litros não apontado'
    END
FROM stg_viagens;

-- ---------------------------------------------------------------------
-- fato_manutencao
--  * tipo: TRIM + padronização ('CORRETIVA ' -> 'Corretiva')
--  * preventiva > R$ 20 mil: preventivas custam no máximo ~R$ 4,7 mil.
--    R$ 191 mil é ~100x o normal -> casas decimais erradas. Divide por 100.
--  * corretivas de motor de R$ 78 mil a R$ 103 mil (retífica/troca de
--    motor) são caras, mas PLAUSÍVEIS: mantidas. Outlier não é sinônimo
--    de erro! O teste é: "esse valor é possível para esse serviço?"
--  * custo nulo: mantido nulo e sinalizado (OS sem custo lançado é um
--    achado para o gestor cobrar da oficina, não um número para inventar).
-- ---------------------------------------------------------------------
INSERT INTO fato_manutencao
SELECT
    manutencao_id,
    data_entrada,
    veiculo_id,
    CASE UPPER(TRIM(tipo_manutencao))
        WHEN 'PREVENTIVA' THEN 'Preventiva'
        WHEN 'CORRETIVA'  THEN 'Corretiva'
    END,
    servico,
    oficina,
    CASE
        WHEN UPPER(TRIM(tipo_manutencao)) = 'PREVENTIVA' AND custo > 20000
            THEN ROUND(custo / 100.0, 2)
        ELSE custo
    END,
    dias_parado,
    CASE
        WHEN UPPER(TRIM(tipo_manutencao)) = 'PREVENTIVA' AND custo > 20000
            THEN 'custo corrigido (/100): casas decimais'
        WHEN custo IS NULL THEN 'custo não lançado'
        WHEN tipo_manutencao <> TRIM(tipo_manutencao)
          OR tipo_manutencao NOT IN ('Preventiva', 'Corretiva')
            THEN 'tipo padronizado'
    END
FROM stg_manutencoes;

-- ---------------------------------------------------------------------
-- fato_multa
--  * valor nulo: no CTB o valor é determinado pela gravidade, então
--    é possível preencher com segurança (imputação determinística).
--  * motorista nulo: mantido nulo (condutor não identificado). É um dado
--    de negócio relevante, pois a empresa pode ser autuada por não indicar.
-- ---------------------------------------------------------------------
INSERT INTO fato_multa
SELECT
    multa_id,
    data,
    veiculo_id,
    motorista_id,
    infracao,
    gravidade,
    pontos,
    COALESCE(valor, CASE gravidade
                        WHEN 'Leve'       THEN 88.38
                        WHEN 'Média'      THEN 130.16
                        WHEN 'Grave'      THEN 195.23
                        WHEN 'Gravíssima' THEN 293.47
                    END),
    status,
    CASE
        WHEN valor IS NULL        THEN 'valor preenchido pela gravidade (CTB)'
        WHEN motorista_id IS NULL THEN 'condutor não identificado'
    END
FROM stg_multas;

-- ---------------------------------------------------------------------
-- fato_ausencia
--  * atraso > 240 min (4h) é implausível como atraso. Vira nulo e
--    sinalizado para conferência com o RH.
-- ---------------------------------------------------------------------
INSERT INTO fato_ausencia
SELECT
    ausencia_id,
    data,
    motorista_id,
    tipo_ocorrencia,
    motivo,
    CASE WHEN minutos_atraso > 240 THEN NULL ELSE minutos_atraso END,
    justificada,
    CASE WHEN minutos_atraso > 240 THEN 'atraso implausível (>4h): conferir com RH' END
FROM stg_ausencias;
