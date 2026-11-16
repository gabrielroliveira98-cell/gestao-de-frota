-- =====================================================================
-- a04_ranking_absenteismo.sql
--
-- PERGUNTA DE NEGÓCIO
--   Quais motoristas têm a maior taxa de absenteísmo (faltas e atrasos)?
--
-- POR QUE IMPORTA
--   Cada falta obriga a puxar um reserva ou deixar a rota sem sair.
--   Contar só "número de faltas" é injusto com quem foi contratado no
--   meio do ano. Por isso usamos TAXA:
--     taxa de absenteísmo = faltas / dias de escala * 100
--   Dias de escala = segunda a sábado desde a admissão (ou desde 01/01).
--
-- TÉCNICAS
--   JOIN com a tabela calendário usando condição de desigualdade
--   (c.data >= data_admissao), CTEs, RANK() e NTILE(4) para dividir a
--   equipe em quartis (o 1º quartil = 25% com pior taxa).
-- =====================================================================

WITH dias_de_escala AS (
    SELECT
        mo.motorista_id,
        COUNT(c.data) AS dias_escala
    FROM dim_motorista mo
    JOIN dim_calendario c
      ON c.data >= mo.data_admissao     -- datas 'AAAA-MM-DD' comparam certo como texto
     AND c.dia_semana_num <> 0          -- domingo fora da escala padrão
    GROUP BY mo.motorista_id
),
ocorrencias AS (
    SELECT
        motorista_id,
        SUM(CASE WHEN tipo_ocorrencia = 'Falta' THEN 1 ELSE 0 END)                         AS faltas,
        SUM(CASE WHEN tipo_ocorrencia = 'Falta' AND justificada = 'Não' THEN 1 ELSE 0 END)  AS faltas_injustificadas,
        SUM(CASE WHEN tipo_ocorrencia = 'Atraso' THEN 1 ELSE 0 END)                        AS atrasos,
        COALESCE(SUM(minutos_atraso), 0)                                                   AS minutos_atraso
    FROM fato_ausencia
    GROUP BY motorista_id
),
indicadores AS (
    SELECT
        mo.nome,
        mo.turno,
        d.dias_escala,
        COALESCE(o.faltas, 0)                                     AS faltas,
        COALESCE(o.faltas_injustificadas, 0)                      AS faltas_injustificadas,
        COALESCE(o.atrasos, 0)                                    AS atrasos,
        ROUND(COALESCE(o.minutos_atraso, 0) / 60.0, 1)            AS horas_atraso,
        ROUND(100.0 * COALESCE(o.faltas, 0) / d.dias_escala, 2)   AS taxa_absenteismo_pct
    FROM dim_motorista mo
    JOIN dias_de_escala d   ON d.motorista_id = mo.motorista_id
    LEFT JOIN ocorrencias o ON o.motorista_id = mo.motorista_id
)
SELECT
    RANK()   OVER (ORDER BY taxa_absenteismo_pct DESC, atrasos DESC)  AS ranking,
    NTILE(4) OVER (ORDER BY taxa_absenteismo_pct DESC, atrasos DESC)  AS quartil,
    nome,
    turno,
    dias_escala,
    faltas,
    faltas_injustificadas,
    taxa_absenteismo_pct,
    atrasos,
    horas_atraso
FROM indicadores
ORDER BY ranking;
