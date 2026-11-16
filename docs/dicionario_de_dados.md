# Dicionário de Dados

Dados **fictícios** gerados por `scripts/gerar_dados.py` (seed 42), período de 01/01/2025 a 31/12/2025.
Arquivos em `data/raw/`, separador vírgula, decimal ponto, codificação UTF-8.

## Dimensões (cadastros)

### veiculos.csv: 1 linha por caminhão
| Coluna | Tipo | Descrição |
|---|---|---|
| veiculo_id | inteiro (PK) | Identificador do veículo |
| placa | texto | Placa fictícia no padrão Mercosul |
| tipo | texto | Coleta, Hidrojato ou Pipa |
| marca / modelo | texto | Fabricante e modelo do caminhão |
| ano_fabricacao | inteiro | Ano de fabricação (idade = 2025 − ano) |
| base_operacional | texto | Garagem de origem (zona de SP) |
| data_baixa | data | Data de venda/baixa; vazio se ainda está na frota |
| status | texto | Situação em 31/12/2025: Ativo, Em manutenção, Inativo |

### motoristas.csv: 1 linha por motorista
| Coluna | Tipo | Descrição |
|---|---|---|
| motorista_id | inteiro (PK) | Identificador do motorista |
| nome | texto | Nome fictício |
| turno | texto | Manhã, Tarde ou Noite |
| categoria_cnh | texto | D ou E |
| data_admissao | data | Data de admissão |

## Fatos (eventos)

### viagens.csv: 1 linha por veículo operando em um dia (rota diária)
| Coluna | Tipo | Descrição |
|---|---|---|
| viagem_id | inteiro (PK) | Identificador da rota |
| data | data | Dia da operação |
| veiculo_id | inteiro (FK) | → veiculos |
| motorista_id | inteiro (FK) | → motoristas |
| km_rodado | decimal | Quilômetros rodados no dia |
| horas_trabalhadas | decimal | Horas de jornada |
| litros_combustivel | decimal | Diesel consumido (litros) |

### manutencoes.csv: 1 linha por entrada na oficina
| Coluna | Tipo | Descrição |
|---|---|---|
| manutencao_id | inteiro (PK) | Identificador da ordem de serviço |
| veiculo_id | inteiro (FK) | → veiculos |
| data_entrada | data | Data em que o veículo entrou na oficina |
| tipo_manutencao | texto | Preventiva ou Corretiva |
| servico | texto | Serviço/sistema afetado |
| oficina | texto | Oficina interna, Concessionária ou Terceirizada |
| custo | decimal | Custo total em R$ |
| dias_parado | inteiro | Dias que o veículo ficou indisponível |

### multas.csv: 1 linha por auto de infração
| Coluna | Tipo | Descrição |
|---|---|---|
| multa_id | inteiro (PK) | Identificador da multa |
| data | data | Data da infração |
| veiculo_id | inteiro (FK) | → veiculos |
| motorista_id | inteiro (FK) | → motoristas (pode faltar: condutor não identificado) |
| infracao | texto | Descrição da infração |
| gravidade | texto | Média, Grave ou Gravíssima |
| pontos | inteiro | Pontos na CNH |
| valor | decimal | Valor em R$ (tabela do CTB) |
| status | texto | Paga, Pendente, Em recurso, Cancelada |

### ausencias.csv: 1 linha por ocorrência de falta ou atraso
| Coluna | Tipo | Descrição |
|---|---|---|
| ausencia_id | inteiro (PK) | Identificador da ocorrência |
| motorista_id | inteiro (FK) | → motoristas |
| data | data | Dia da ocorrência |
| tipo_ocorrencia | texto | Falta ou Atraso |
| motivo | texto | Motivo declarado |
| minutos_atraso | inteiro | Minutos de atraso (vazio quando é falta) |
| justificada | texto | Sim / Não |

## Qualidade dos dados

A base foi gerada **com problemas de propósito**, como numa planilha operacional real:
valores nulos, outliers (alguns legítimos, outros erros de digitação), linhas duplicadas e
textos inconsistentes. Identificar e tratar cada um faz parte do projeto. O tratamento
aplicado está documentado na etapa de limpeza.
