-- =====================================================================
-- a08_sazonalidade_operacao.sql
--
-- PERGUNTA DE NEGÓCIO
--   A demanda de cada tipo de caminhão muda ao longo do ano?
--   Em quais meses cada operação fica acima do normal?
--
-- POR QUE IMPORTA
--   Planejamento: concentrar preventivas e férias dos motoristas de
--   hidrojato nos meses secos, e as de pipa na época de chuvas, quando
--   a demanda de cada um é menor. Evita faltar caminhão no pico.
--
-- TÉCNICAS
--   GROUP BY por tipo e mês, AVG() OVER (PARTITION BY tipo) para a média
--   mensal de cada tipo e índice de sazonalidade (mês / média do tipo).
--   Índice 1,30 = mês 30% acima do normal para aquele tipo.
-- =====================================================================

WITH rotas_mes AS (
    SELECT
        v.tipo,
        c.ano_mes,
        c.nome_mes,
        COUNT(*)            AS qtd_rotas,
        SUM(f.km_rodado)    AS km
    FROM fato_viagem f
    JOIN dim_veiculo    v ON v.veiculo_id = f.veiculo_id
    JOIN dim_calendario c ON c.data       = f.data
    GROUP BY v.tipo, c.ano_mes, c.nome_mes
)
SELECT
    tipo,
    ano_mes,
    nome_mes,
    qtd_rotas,
    ROUND(km, 0)                                                         AS km,
    ROUND(AVG(qtd_rotas) OVER (PARTITION BY tipo), 1)                    AS media_mensal_tipo,
    ROUND(qtd_rotas / AVG(qtd_rotas) OVER (PARTITION BY tipo), 2)        AS indice_sazonalidade,
    RANK() OVER (PARTITION BY tipo ORDER BY qtd_rotas DESC)              AS ranking_no_tipo
FROM rotas_mes
ORDER BY tipo, ano_mes;
