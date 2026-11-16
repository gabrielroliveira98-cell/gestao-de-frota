-- =====================================================================
-- a02_veiculos_mais_tempo_parados.sql
--
-- PERGUNTA DE NEGÓCIO
--   Quais caminhões ficaram mais tempo parados em oficina e qual a
--   disponibilidade de cada um?
--
-- POR QUE IMPORTA
--   Caminhão parado = rota sem atendimento ou veículo reserva/locado.
--   Disponibilidade é o KPI clássico de frota: % dos dias em que o
--   veículo estava apto a operar.
--   Disponibilidade = (dias na frota - dias parado) / dias na frota
--
-- CUIDADOS
--   * Veículos baixados (vendidos) só contam os dias até a baixa.
--   * Manutenção que começou em 30/12 com 5 dias parado "vaza" para 2026:
--     limitamos ao período analisado com MIN(). No PostgreSQL: LEAST().
--
-- TÉCNICAS
--   CTEs encadeadas, julianday() para diferença de datas,
--   RANK() OVER para ranking.
-- =====================================================================

WITH dias_na_frota AS (
    SELECT
        veiculo_id,
        placa,
        tipo,
        idade_anos,
        CAST(julianday(COALESCE(data_baixa, '2025-12-31'))
             - julianday('2025-01-01') + 1 AS INTEGER)            AS dias_na_frota
    FROM dim_veiculo
),
paradas_ajustadas AS (
    -- dias parados efetivamente dentro de 2025
    SELECT
        veiculo_id,
        tipo_manutencao,
        MIN(dias_parado,
            CAST(julianday('2025-12-31') - julianday(data_entrada) + 1 AS INTEGER)) AS dias
    FROM fato_manutencao
),
paradas AS (
    SELECT
        veiculo_id,
        SUM(dias)                                                        AS dias_parado,
        SUM(CASE WHEN tipo_manutencao = 'Preventiva' THEN dias ELSE 0 END) AS dias_preventiva,
        SUM(CASE WHEN tipo_manutencao = 'Corretiva'  THEN dias ELSE 0 END) AS dias_corretiva
    FROM paradas_ajustadas
    GROUP BY veiculo_id
)
SELECT
    RANK() OVER (ORDER BY COALESCE(p.dias_parado, 0) DESC)          AS ranking,
    f.placa,
    f.tipo,
    f.idade_anos,
    f.dias_na_frota,
    COALESCE(p.dias_parado, 0)                                      AS dias_parado,
    COALESCE(p.dias_preventiva, 0)                                  AS dias_preventiva,
    COALESCE(p.dias_corretiva, 0)                                   AS dias_corretiva,
    ROUND(100.0 * (f.dias_na_frota - COALESCE(p.dias_parado, 0))
          / f.dias_na_frota, 1)                                     AS pct_disponibilidade
FROM dias_na_frota f
LEFT JOIN paradas p ON p.veiculo_id = f.veiculo_id
ORDER BY ranking;
