# Modelo de Dados: Esquema Estrela

## Visão geral

O modelo separa **o que é cadastro** (dimensões: *quem*, *o quê*, *quando*) do **que é evento**
(fatos: *o que aconteceu*, com números para somar). As tabelas fato nunca se ligam
diretamente entre si: elas conversam **através das dimensões que compartilham**.

Como há mais de uma tabela fato usando as mesmas dimensões, o nome técnico é
**constelação de fatos** (*galaxy schema*): várias estrelas que dividem as mesmas pontas.

```mermaid
erDiagram
    dim_calendario ||--o{ fato_viagem      : "data"
    dim_calendario ||--o{ fato_manutencao  : "data_entrada"
    dim_calendario ||--o{ fato_multa       : "data"
    dim_calendario ||--o{ fato_ausencia    : "data"

    dim_veiculo    ||--o{ fato_viagem      : "veiculo_id"
    dim_veiculo    ||--o{ fato_manutencao  : "veiculo_id"
    dim_veiculo    ||--o{ fato_multa       : "veiculo_id"

    dim_motorista  ||--o{ fato_viagem      : "motorista_id"
    dim_motorista  |o--o{ fato_multa       : "motorista_id (pode ser nulo)"
    dim_motorista  ||--o{ fato_ausencia    : "motorista_id"

    dim_veiculo {
        int veiculo_id PK
        text placa
        text tipo
        text marca
        text modelo
        int ano_fabricacao
        int idade_anos
        text faixa_idade
        text base_operacional
        date data_baixa
        text status
    }
    dim_motorista {
        int motorista_id PK
        text nome
        text turno
        text categoria_cnh
        date data_admissao
    }
    dim_calendario {
        date data PK
        int ano
        int mes
        text nome_mes
        text ano_mes
        int trimestre
        int dia_semana_num
        text dia_semana
        int fim_de_semana
    }
    fato_viagem {
        int viagem_id PK
        date data FK
        int veiculo_id FK
        int motorista_id FK
        real km_rodado
        real horas_trabalhadas
        real litros_combustivel
    }
    fato_manutencao {
        int manutencao_id PK
        date data_entrada FK
        int veiculo_id FK
        text tipo_manutencao
        text servico
        text oficina
        real custo
        int dias_parado
    }
    fato_multa {
        int multa_id PK
        date data FK
        int veiculo_id FK
        int motorista_id FK
        text infracao
        text gravidade
        int pontos
        real valor
        text status
    }
    fato_ausencia {
        int ausencia_id PK
        date data FK
        int motorista_id FK
        text tipo_ocorrencia
        text motivo
        int minutos_atraso
        text justificada
    }
```

> O GitHub desenha esse diagrama automaticamente (bloco `mermaid`).

## Granularidade das tabelas fato

**Granularidade** é a resposta para a pergunta: *o que representa uma linha?*
Definir isso antes de tudo evita somar coisas erradas.

| Tabela | Uma linha representa | Métricas (somáveis) |
|---|---|---|
| fato_viagem | um veículo operando em um dia com um motorista | km, horas, litros |
| fato_manutencao | uma entrada do veículo na oficina (ordem de serviço) | custo, dias parado |
| fato_multa | um auto de infração | valor, pontos |
| fato_ausencia | uma falta ou um atraso de um motorista em um dia | minutos de atraso, contagem |

## Relacionamentos

Todos os relacionamentos são **1 : N (um para muitos)**, saindo da dimensão para o fato:

| Dimensão (lado 1) | Fato (lado N) | Chave | Observação |
|---|---|---|---|
| dim_calendario | as 4 fatos | data | Permite filtrar tudo por mês/trimestre com um único filtro |
| dim_veiculo | viagem, manutenção, multa | veiculo_id | Ausência não tem veículo (é do motorista) |
| dim_motorista | viagem, multa, ausência | motorista_id | Em multa a chave **pode ser nula**: condutor não identificado |

**Por que não ligar `fato_multa` direto em `fato_viagem`?** Ligar fato com fato cria
relacionamentos N:N e ambiguidade de filtro no Power BI. Se eu quiser "multas por km rodado",
cruzo as duas pelo veículo e pelo mês, que são dimensões em comum.

## Por que esquema estrela (e não uma tabelona única)?

1. **Desempenho:** o Power BI (motor VertiPaq) é otimizado para estrela, e as dimensões pequenas filtram fatos grandes.
2. **Sem repetição:** a placa e o modelo ficam em um lugar só, não repetidos em 10 mil linhas.
3. **Filtros consistentes:** um único segmentador de "Tipo de veículo" filtra viagens, manutenções e multas ao mesmo tempo.
4. **DAX mais simples:** medidas como `SUM(fato_manutencao[custo])` funcionam com qualquer filtro de dimensão.

## Camadas do banco

```
CSV bruto ──► stg_*  (staging: cópia fiel, sem regras)
                │
                ▼  queries/03_tratamento_dados.sql
          dim_* / fato_*  (modelo estrela limpo, com PK, FK e CHECK)
                │
                ▼
     data/processed/*.csv  ──►  Power BI
```

A camada *staging* preserva o dado original. Assim qualquer regra de limpeza pode ser
revista e reaplicada sem perder informação.
