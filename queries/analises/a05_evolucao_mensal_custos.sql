-- =====================================================================
-- a05_evolucao_mensal_custos.sql
--
-- PERGUNTA DE NEGÓCIO
--   Como o custo operacional da frota evoluiu mês a mês, e quanto
--   variou em relação ao mês anterior?
--
-- COMPOSIÇÃO DO CUSTO
--   manutenção + combustível + multas (exceto canceladas)
--   Combustível = litros x preço do diesel. O preço é uma PREMISSA
--   (parâmetro numa CTE, fácil de alterar). Nas viagens sem litros
--   apontados (~2%) o combustível fica subestimado. Vale citar isso.
--
-- POR QUE IMPORTA
--   A variação % mostra picos (ex.: verão com mais quebras) e permite
--   cobrar explicação. O custo por km neutraliza o efeito do volume:
--   se o custo subiu porque a frota rodou mais, não é necessariamente ruim.
--
-- TÉCNICAS
--   CTE de parâmetros, várias CTEs agregadas unidas pela lista de meses
--   (garante que mês sem evento apareça com zero), LAG() para o mês
--   anterior e SUM() OVER (ORDER BY) para o acumulado no ano.
--   PostgreSQL: troque strftime('%Y-%m', data) por to_char(data, 'YYYY-MM').
-- =====================================================================

WITH parametros AS (
    SELECT 6.20 AS preco_diesel_litro          -- R$/litro (premissa)
),
meses AS (
    SELECT DISTINCT ano_mes, nome_mes FROM dim_calendario
),
manutencao AS (
    SELECT strftime('%Y-%m', data_entrada) AS ano_mes, SUM(custo) AS custo_manutencao
    FROM fato_manutencao
    GROUP BY 1
),
combustivel AS (
    SELECT
        strftime('%Y-%m', data)                                         AS ano_mes,
        SUM(km_rodado)                                                  AS km,
        SUM(litros_combustivel) * (SELECT preco_diesel_litro FROM parametros) AS custo_combustivel
    FROM fato_viagem
    GROUP BY 1
),
multas AS (
    SELECT strftime('%Y-%m', data) AS ano_mes, SUM(valor) AS custo_multas
    FROM fato_multa
    WHERE status <> 'Cancelada'
    GROUP BY 1
),
consolidado AS (
    SELECT
        m.ano_mes,
        m.nome_mes,
        COALESCE(ma.custo_manutencao, 0)  AS custo_manutencao,
        COALESCE(c.custo_combustivel, 0)  AS custo_combustivel,
        COALESCE(mu.custo_multas, 0)      AS custo_multas,
        COALESCE(ma.custo_manutencao, 0) + COALESCE(c.custo_combustivel, 0)
            + COALESCE(mu.custo_multas, 0) AS custo_total,
        c.km
    FROM meses m
    LEFT JOIN manutencao  ma ON ma.ano_mes = m.ano_mes
    LEFT JOIN combustivel c  ON c.ano_mes  = m.ano_mes
    LEFT JOIN multas      mu ON mu.ano_mes = m.ano_mes
)
SELECT
    ano_mes,
    nome_mes,
    ROUND(custo_manutencao, 2)                                         AS manutencao,
    ROUND(custo_combustivel, 2)                                        AS combustivel,
    ROUND(custo_multas, 2)                                             AS multas,
    ROUND(custo_total, 2)                                              AS custo_total,
    ROUND(LAG(custo_total) OVER (ORDER BY ano_mes), 2)                 AS custo_mes_anterior,
    ROUND(100.0 * (custo_total - LAG(custo_total) OVER (ORDER BY ano_mes))
          / NULLIF(LAG(custo_total) OVER (ORDER BY ano_mes), 0), 1)    AS variacao_pct,
    ROUND(SUM(custo_total) OVER (ORDER BY ano_mes), 2)                 AS acumulado_ano,
    ROUND(custo_total / NULLIF(km, 0), 2)                              AS custo_por_km
FROM consolidado
ORDER BY ano_mes;
