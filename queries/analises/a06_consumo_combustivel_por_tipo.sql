-- =====================================================================
-- a06_consumo_combustivel_por_tipo.sql
--
-- PERGUNTA DE NEGÓCIO
--   Qual o consumo médio de combustível por km de cada tipo de caminhão?
--   A idade do veículo piora o consumo?
--
-- POR QUE IMPORTA
--   Combustível é o maior custo variável da frota. Saber o consumo
--   "normal" de cada tipo permite criar metas e detectar desvios
--   (vazamento, manutenção ruim, direção agressiva, desvio de diesel).
--
-- ATENÇÃO (erro comum de iniciante)
--   Média de razões != razão das somas.
--   AVG(km/litros) dá o mesmo peso a uma rota de 20 km e a uma de 150 km.
--   O correto para consumo é SUM(km) / SUM(litros) (média ponderada).
--   A coluna "media_simples" está aqui só para mostrar a diferença.
--
-- REGRA: só entram viagens com litros apontados (nulos são excluídos
--        dos DOIS lados da conta, senão o km fica "sem consumo").
--
-- TÉCNICAS
--   JOIN, GROUP BY, WHERE para excluir nulos, MAX() OVER (PARTITION BY)
--   para comparar cada faixa com a melhor faixa do mesmo tipo.
-- =====================================================================

-- [A] Consumo por tipo de veículo
SELECT
    v.tipo,
    COUNT(*)                                                  AS viagens_validas,
    ROUND(SUM(f.km_rodado), 0)                                AS km_total,
    ROUND(SUM(f.litros_combustivel), 0)                       AS litros_total,
    ROUND(SUM(f.km_rodado) / SUM(f.litros_combustivel), 2)    AS km_por_litro,
    ROUND(100.0 * SUM(f.litros_combustivel) / SUM(f.km_rodado), 1) AS litros_por_100km,
    ROUND(AVG(f.km_rodado / f.litros_combustivel), 2)         AS media_simples_km_l
FROM fato_viagem f
JOIN dim_veiculo v ON v.veiculo_id = f.veiculo_id
WHERE f.litros_combustivel IS NOT NULL
GROUP BY v.tipo
ORDER BY km_por_litro;

-- [B] Efeito da idade: consumo por tipo x faixa de idade
WITH consumo AS (
    SELECT
        v.tipo,
        v.faixa_idade,
        COUNT(DISTINCT v.veiculo_id)                          AS qtd_veiculos,
        SUM(f.km_rodado) / SUM(f.litros_combustivel)          AS km_por_litro
    FROM fato_viagem f
    JOIN dim_veiculo v ON v.veiculo_id = f.veiculo_id
    WHERE f.litros_combustivel IS NOT NULL
    GROUP BY v.tipo, v.faixa_idade
)
SELECT
    tipo,
    faixa_idade,
    qtd_veiculos,
    ROUND(km_por_litro, 2)                                                       AS km_por_litro,
    -- quanto esta faixa é menos eficiente que a melhor faixa do mesmo tipo
    ROUND(100.0 * (km_por_litro / MAX(km_por_litro) OVER (PARTITION BY tipo) - 1), 1) AS pct_vs_melhor_faixa
FROM consumo
ORDER BY tipo, faixa_idade;
