-- =====================================================================
-- 02_diagnostico_qualidade.sql
-- Antes de limpar, MEDIR: quais problemas existem e quantas linhas cada
-- um afeta? Roda sobre a camada staging (dado bruto).
-- Cada consulta abaixo responde a uma pergunta de qualidade.
-- Dica: tente encontrar os problemas por conta própria antes de ler tudo.
-- =====================================================================

-- [1] Quantos nulos existem nas colunas numéricas das viagens?
--     Técnica: SUM(CASE WHEN ... IS NULL) conta nulos por coluna.
SELECT
    COUNT(*)                                                    AS total_linhas,
    SUM(CASE WHEN km_rodado          IS NULL THEN 1 ELSE 0 END) AS nulos_km,
    SUM(CASE WHEN horas_trabalhadas  IS NULL THEN 1 ELSE 0 END) AS nulos_horas,
    SUM(CASE WHEN litros_combustivel IS NULL THEN 1 ELSE 0 END) AS nulos_litros,
    SUM(CASE WHEN litros_combustivel = 0     THEN 1 ELSE 0 END) AS litros_zerados
FROM stg_viagens;

-- [2] Existem viagens duplicadas (mesmo ID aparecendo mais de uma vez)?
SELECT viagem_id, COUNT(*) AS ocorrencias
FROM stg_viagens
GROUP BY viagem_id
HAVING COUNT(*) > 1
ORDER BY viagem_id;

-- [3] Outliers de km: alguma rota diária absurda?
--     Um caminhão urbano raramente passa de 160 km/dia.
SELECT viagem_id, data, veiculo_id, km_rodado, litros_combustivel
FROM stg_viagens
WHERE km_rodado > 200
ORDER BY km_rodado DESC;

-- [4] Valores distintos do tipo de manutenção: há grafias diferentes?
--     O '[' ']' em volta revela espaços escondidos no fim do texto.
SELECT '[' || tipo_manutencao || ']' AS valor_bruto, COUNT(*) AS qtd
FROM stg_manutencoes
GROUP BY tipo_manutencao;

-- [5] Custo de manutenção: nulos e valores fora do padrão por tipo
SELECT
    UPPER(TRIM(tipo_manutencao))                          AS tipo,
    COUNT(*)                                              AS qtd,
    SUM(CASE WHEN custo IS NULL THEN 1 ELSE 0 END)        AS custo_nulo,
    ROUND(MIN(custo), 2)                                  AS minimo,
    ROUND(AVG(custo), 2)                                  AS media,
    ROUND(MAX(custo), 2)                                  AS maximo
FROM stg_manutencoes
GROUP BY UPPER(TRIM(tipo_manutencao));

-- [6] Quais são as manutenções mais caras? (legítimas ou erro?)
SELECT manutencao_id, veiculo_id, tipo_manutencao, servico, custo, dias_parado
FROM stg_manutencoes
ORDER BY custo DESC
LIMIT 5;

-- [7] Placas fora do padrão (minúsculas)
SELECT veiculo_id, placa
FROM stg_veiculos
WHERE placa <> UPPER(placa);

-- [8] Cadastros incompletos
SELECT 'veiculo sem modelo' AS problema, COUNT(*) AS qtd FROM stg_veiculos   WHERE modelo IS NULL
UNION ALL
SELECT 'motorista sem turno',            COUNT(*)        FROM stg_motoristas WHERE turno  IS NULL
UNION ALL
SELECT 'multa sem motorista',            COUNT(*)        FROM stg_multas     WHERE motorista_id IS NULL
UNION ALL
SELECT 'multa sem valor',                COUNT(*)        FROM stg_multas     WHERE valor IS NULL;

-- [9] Atrasos implausíveis (mais de 4h de atraso não é atraso, é falta)
SELECT ausencia_id, motorista_id, data, motivo, minutos_atraso
FROM stg_ausencias
WHERE minutos_atraso > 240;
