-- =====================================================================
-- a03_ranking_motoristas_multas.sql
--
-- PERGUNTA DE NEGÓCIO
--   Quais motoristas mais recebem multas? O problema está espalhado
--   pela equipe ou concentrado em poucas pessoas?
--
-- POR QUE IMPORTA
--   Se poucos motoristas concentram a maior parte do valor (Princípio de
--   Pareto, 80/20), a ação é direcionada (reciclagem, conversa individual)
--   em vez de uma campanha genérica para todos.
--   Normalizar por 1.000 viagens é justo: quem dirige mais se expõe mais.
--   Motorista profissional pode acumular até 40 pontos em 12 meses antes
--   da suspensão da CNH, então pontos altos são risco operacional.
--
-- REGRA: multas CANCELADAS não entram (não geraram custo nem pontos).
--
-- TÉCNICAS
--   CTEs, LEFT JOIN, DENSE_RANK(), SUM() OVER () para % do total e
--   SUM() OVER (ORDER BY ... ROWS UNBOUNDED PRECEDING) para % ACUMULADO
--   (curva de Pareto).
-- =====================================================================

-- [A] Ranking por motorista
WITH multas_validas AS (
    SELECT * FROM fato_multa WHERE status <> 'Cancelada'
),
viagens_por_motorista AS (
    SELECT motorista_id, COUNT(*) AS qtd_viagens
    FROM fato_viagem
    GROUP BY motorista_id
),
multas_por_motorista AS (
    SELECT
        mo.motorista_id,
        mo.nome,
        mo.turno,
        COUNT(mv.multa_id)                                              AS qtd_multas,
        SUM(CASE WHEN mv.gravidade = 'Gravíssima' THEN 1 ELSE 0 END)    AS qtd_gravissimas,
        COALESCE(SUM(mv.pontos), 0)                                     AS pontos,
        COALESCE(SUM(mv.valor), 0)                                      AS valor_total
    FROM dim_motorista mo
    LEFT JOIN multas_validas mv ON mv.motorista_id = mo.motorista_id
    GROUP BY mo.motorista_id, mo.nome, mo.turno
)
SELECT
    DENSE_RANK() OVER (ORDER BY m.qtd_multas DESC, m.valor_total DESC)     AS ranking,
    m.nome,
    m.turno,
    v.qtd_viagens,
    m.qtd_multas,
    ROUND(1000.0 * m.qtd_multas / NULLIF(v.qtd_viagens, 0), 1)             AS multas_por_mil_viagens,
    m.qtd_gravissimas,
    m.pontos,
    ROUND(m.valor_total, 2)                                                AS valor_total,
    ROUND(100.0 * m.valor_total / SUM(m.valor_total) OVER (), 1)           AS pct_valor,
    ROUND(100.0 * SUM(m.valor_total) OVER (ORDER BY m.qtd_multas DESC, m.valor_total DESC
                                           ROWS UNBOUNDED PRECEDING)
          / SUM(m.valor_total) OVER (), 1)                                 AS pct_acumulado
FROM multas_por_motorista m
LEFT JOIN viagens_por_motorista v ON v.motorista_id = m.motorista_id
ORDER BY ranking
LIMIT 15;

-- [B] Multas sem condutor identificado
--     A empresa fica com o custo e ninguém é responsabilizado.
--     Indicador de falha no controle de quem dirigiu qual veículo.
SELECT
    COUNT(*)                                                         AS multas_sem_condutor,
    ROUND(SUM(valor), 2)                                             AS valor,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fato_multa
                              WHERE status <> 'Cancelada'), 1)       AS pct_das_multas
FROM fato_multa
WHERE motorista_id IS NULL
  AND status <> 'Cancelada';
