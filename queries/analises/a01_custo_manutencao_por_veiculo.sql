-- =====================================================================
-- a01_custo_manutencao_por_veiculo.sql
--
-- PERGUNTA DE NEGÓCIO
--   Quanto cada caminhão custou em manutenção em 2025, separando
--   preventiva de corretiva? Quais veículos concentram o gasto?
--
-- POR QUE IMPORTA
--   Veículo com custo corretivo alto e recorrente é candidato a venda/
--   renovação. Uma frota saudável gasta mais em PREVENTIVA (planejada)
--   do que em CORRETIVA (quebra = custo + caminhão parado + rota perdida).
--
-- TÉCNICAS
--   LEFT JOIN (mantém veículos sem manutenção), GROUP BY,
--   SUM(CASE ...) para "pivotar" tipos em colunas,
--   SUM(SUM(...)) OVER () -> window function para % sobre o total da frota.
-- =====================================================================

-- [A] Detalhe por veículo
SELECT
    v.placa,
    v.tipo,
    v.idade_anos,
    COUNT(m.manutencao_id)                                                      AS qtd_os,
    -- COALESCE(..., 0): veículo sem corretiva deve mostrar 0, não vazio
    ROUND(COALESCE(SUM(CASE WHEN m.tipo_manutencao = 'Preventiva' THEN m.custo END), 0), 2) AS custo_preventiva,
    ROUND(COALESCE(SUM(CASE WHEN m.tipo_manutencao = 'Corretiva'  THEN m.custo END), 0), 2) AS custo_corretiva,
    ROUND(COALESCE(SUM(m.custo), 0), 2)                                                     AS custo_total,
    -- % que este veículo representa no custo de toda a frota
    ROUND(100.0 * SUM(m.custo) / SUM(SUM(m.custo)) OVER (), 1)                              AS pct_custo_frota,
    -- quanto do custo do veículo foi "apagando incêndio"
    ROUND(100.0 * COALESCE(SUM(CASE WHEN m.tipo_manutencao = 'Corretiva' THEN m.custo END), 0)
          / NULLIF(SUM(m.custo), 0), 1)                                                     AS pct_corretiva
FROM dim_veiculo v
LEFT JOIN fato_manutencao m ON m.veiculo_id = v.veiculo_id
GROUP BY v.veiculo_id, v.placa, v.tipo, v.idade_anos
ORDER BY custo_total DESC;

-- [B] Resumo por tipo de veículo x tipo de manutenção
--     "Custo médio por veículo" permite comparar grupos de tamanhos diferentes
--     (22 caminhões de coleta vs 8 hidrojatos).
SELECT
    v.tipo                                                  AS tipo_veiculo,
    m.tipo_manutencao,
    COUNT(*)                                                AS qtd_os,
    ROUND(SUM(m.custo), 2)                                  AS custo_total,
    ROUND(AVG(m.custo), 2)                                  AS ticket_medio_os,
    ROUND(SUM(m.custo) / COUNT(DISTINCT m.veiculo_id), 2)   AS custo_medio_por_veiculo
FROM fato_manutencao m
JOIN dim_veiculo v ON v.veiculo_id = m.veiculo_id
GROUP BY v.tipo, m.tipo_manutencao
ORDER BY v.tipo, m.tipo_manutencao;
