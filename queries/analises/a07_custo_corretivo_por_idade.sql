-- =====================================================================
-- a07_custo_corretivo_por_idade.sql
--
-- PERGUNTA DE NEGÓCIO
--   Caminhões mais velhos concentram o custo de manutenção corretiva?
--   Vale a pena renovar a frota?
--
-- POR QUE IMPORTA
--   É a base de um argumento de RENOVAÇÃO DE FROTA: se os veículos acima
--   de 10 anos são X% da frota, mas Y% do custo corretivo (Y >> X), cada
--   ano a mais com eles custa caro, além dos dias parados.
--
-- TÉCNICAS
--   CTE, LEFT JOIN, SUM() OVER () para participação % da frota e do custo
--   na mesma consulta (sem subquery).
-- =====================================================================

WITH por_faixa AS (
    SELECT
        v.faixa_idade,
        COUNT(DISTINCT v.veiculo_id)                                       AS qtd_veiculos,
        COALESCE(SUM(CASE WHEN m.tipo_manutencao = 'Corretiva' THEN m.custo END), 0)       AS custo_corretivo,
        COALESCE(SUM(CASE WHEN m.tipo_manutencao = 'Corretiva' THEN 1 END), 0)             AS qtd_quebras,
        COALESCE(SUM(CASE WHEN m.tipo_manutencao = 'Corretiva' THEN m.dias_parado END), 0) AS dias_parado_corretiva
    FROM dim_veiculo v
    LEFT JOIN fato_manutencao m ON m.veiculo_id = v.veiculo_id
    GROUP BY v.faixa_idade
)
SELECT
    faixa_idade,
    qtd_veiculos,
    ROUND(100.0 * qtd_veiculos / SUM(qtd_veiculos) OVER (), 1)          AS pct_da_frota,
    ROUND(custo_corretivo, 2)                                           AS custo_corretivo,
    ROUND(100.0 * custo_corretivo / SUM(custo_corretivo) OVER (), 1)    AS pct_custo_corretivo,
    ROUND(custo_corretivo / qtd_veiculos, 2)                            AS custo_corretivo_por_veiculo,
    ROUND(1.0 * qtd_quebras / qtd_veiculos, 1)                          AS quebras_por_veiculo,
    ROUND(1.0 * dias_parado_corretiva / qtd_veiculos, 1)                AS dias_parado_por_veiculo
FROM por_faixa
ORDER BY faixa_idade;
