# Guia de Construção do Dashboard no Power BI

Passo a passo para montar o `dashboards/gestao_frota.pbix` a partir dos CSVs limpos em
`data/processed/`. Os menus estão com os nomes do Power BI Desktop em português.

**Ordem de trabalho:** Configurações → Power Query → Modelo → Calendário → Medidas →
**Validação** → Visuais → Design. Não pule a validação: dashboard bonito com número errado
derruba a credibilidade do analista.

---

## 0. Configurações iniciais (faça antes de importar)

1. **Arquivo → Opções e configurações → Opções → Arquivo Atual → Carregamento de Dados**
   → desmarque **Data/hora automática**.
   *Por quê:* o Power BI cria uma tabela de datas oculta para **cada** coluna de data. Isso
   pesa o modelo e conflita com a nossa tabela calendário.
2. Na mesma janela, em **Configurações Regionais**, deixe a localidade como **Português (Brasil)**.
   Mas atenção ao item 1.3 do Power Query: os CSVs usam **ponto** como separador decimal.

---

## 1. Power Query (importação e tratamento)

### 1.1 Crie um parâmetro com o caminho da pasta

Assim o projeto funciona em qualquer computador: quem clonar o repositório muda só o parâmetro.

**Página Inicial → Transformar dados → Gerenciar Parâmetros → Novo Parâmetro**
- Nome: `PastaDados`
- Tipo: Texto
- Valor atual: o caminho da sua pasta, **terminando com barra invertida**, por exemplo
  `C:\Users\SEU_USUARIO\...\Gestão_de_Frota\data\processed\`

### 1.2 Importe cada tabela pelo Editor Avançado

Para cada tabela: **Nova Fonte → Consulta Nula**, renomeie a consulta (nome abaixo), abra
**Editor Avançado** e cole o código. Escrever em M (a linguagem do Power Query) em vez de
clicar mostra domínio técnico, e cada passo fica com um nome legível.

> **Não importe `dim_calendario.csv`.** O calendário será criado em DAX (seção 3).
> Ter dois calendários gera confusão de filtros.

**dVeiculo**
```m
let
    Fonte = Csv.Document(
        File.Contents(PastaDados & "dim_veiculo.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    CabecalhosPromovidos = Table.PromoteHeaders(Fonte, [PromoteAllScalars = true]),
    TiposAlterados = Table.TransformColumnTypes(
        CabecalhosPromovidos,
        {
            {"veiculo_id", Int64.Type}, {"placa", type text}, {"tipo", type text},
            {"marca", type text}, {"modelo", type text}, {"ano_fabricacao", Int64.Type},
            {"idade_anos", Int64.Type}, {"faixa_idade", type text},
            {"base_operacional", type text}, {"data_baixa", type date}, {"status", type text}
        },
        "en-US"
    ),
    // Rótulo amigável para eixos e segmentações: "UEM1R47 · Coleta"
    VeiculoRotulo = Table.AddColumn(
        TiposAlterados, "Veículo", each [placa] & " · " & [tipo], type text
    )
in
    VeiculoRotulo
```

**dMotorista**: inclui o **membro desconhecido** (explicação logo abaixo do código)
```m
let
    Fonte = Csv.Document(
        File.Contents(PastaDados & "dim_motorista.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    CabecalhosPromovidos = Table.PromoteHeaders(Fonte, [PromoteAllScalars = true]),
    TiposAlterados = Table.TransformColumnTypes(
        CabecalhosPromovidos,
        {
            {"motorista_id", Int64.Type}, {"nome", type text}, {"turno", type text},
            {"categoria_cnh", type text}, {"data_admissao", type date}
        },
        "en-US"
    ),
    // Linha extra para multas sem condutor identificado (motorista_id = 0)
    MembroDesconhecido = #table(
        type table [motorista_id = Int64.Type, nome = text, turno = text,
                    categoria_cnh = text, data_admissao = date],
        {{0, "Não identificado", "Não informado", "-", null}}
    ),
    Combinado = Table.Combine({TiposAlterados, MembroDesconhecido})
in
    Combinado
```
*Por que o membro desconhecido?* Se a multa tem `motorista_id` vazio, o Power BI a joga numa
linha **"(Em branco)"** nos gráficos, que parece erro. Com o ID 0 e o nome "Não identificado",
o gestor lê exatamente o que aconteceu. É uma técnica clássica de modelagem dimensional.

**fViagem**
```m
let
    Fonte = Csv.Document(
        File.Contents(PastaDados & "fato_viagem.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    CabecalhosPromovidos = Table.PromoteHeaders(Fonte, [PromoteAllScalars = true]),
    TiposAlterados = Table.TransformColumnTypes(
        CabecalhosPromovidos,
        {
            {"viagem_id", Int64.Type}, {"data", type date}, {"veiculo_id", Int64.Type},
            {"motorista_id", Int64.Type}, {"km_rodado", type number},
            {"horas_trabalhadas", type number}, {"litros_combustivel", type number}
        },
        "en-US"
    ),
    // Coluna de auditoria não é usada no dashboard: removê-la deixa o modelo mais leve
    ColunasRemovidas = Table.RemoveColumns(TiposAlterados, {"obs_tratamento"})
in
    ColunasRemovidas
```

**fManutencao**
```m
let
    Fonte = Csv.Document(
        File.Contents(PastaDados & "fato_manutencao.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    CabecalhosPromovidos = Table.PromoteHeaders(Fonte, [PromoteAllScalars = true]),
    TiposAlterados = Table.TransformColumnTypes(
        CabecalhosPromovidos,
        {
            {"manutencao_id", Int64.Type}, {"data_entrada", type date},
            {"veiculo_id", Int64.Type}, {"tipo_manutencao", type text},
            {"servico", type text}, {"oficina", type text},
            {"custo", Currency.Type}, {"dias_parado", Int64.Type}
        },
        "en-US"
    ),
    ColunasRemovidas = Table.RemoveColumns(TiposAlterados, {"obs_tratamento"})
in
    ColunasRemovidas
```

**fParadas**: uma linha por **veículo por dia parado** (necessária para a disponibilidade)
```m
let
    // Referencia a consulta fManutencao (reaproveita o tratamento já feito)
    Fonte = fManutencao,
    // Cria uma lista de datas: entrada + cada dia que o caminhão ficou na oficina
    ListaDeDias = Table.AddColumn(
        Fonte, "data",
        each List.Dates([data_entrada], [dias_parado], #duration(1, 0, 0, 0)),
        type list
    ),
    // "Explode" a lista: uma OS de 5 dias vira 5 linhas
    UmaLinhaPorDia = Table.ExpandListColumn(ListaDeDias, "data"),
    TipoData = Table.TransformColumnTypes(UmaLinhaPorDia, {{"data", type date}}),
    // Dias que "vazam" para 2026 ficam fora do período analisado
    SomentePeriodo = Table.SelectRows(TipoData, each [data] <= #date(2025, 12, 31)),
    ColunasMantidas = Table.SelectColumns(
        SomentePeriodo, {"veiculo_id", "data", "tipo_manutencao"}
    ),
    // Duas OS sobrepostas no mesmo dia contariam o dia 2x: remove duplicatas
    SemDuplicatas = Table.Distinct(ColunasMantidas, {"veiculo_id", "data"})
in
    SemDuplicatas
```
*Por que essa tabela existe?* Uma OS que entra em 29/01 com 5 dias parada ocupa janeiro **e**
fevereiro. Se usássemos só `dias_parado` na data de entrada, a disponibilidade de fevereiro
ficaria errada. Transformar o evento em "um dia por linha" é o jeito correto.

**fMulta**
```m
let
    Fonte = Csv.Document(
        File.Contents(PastaDados & "fato_multa.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    CabecalhosPromovidos = Table.PromoteHeaders(Fonte, [PromoteAllScalars = true]),
    TiposAlterados = Table.TransformColumnTypes(
        CabecalhosPromovidos,
        {
            {"multa_id", Int64.Type}, {"data", type date}, {"veiculo_id", Int64.Type},
            {"motorista_id", Int64.Type}, {"infracao", type text},
            {"gravidade", type text}, {"pontos", Int64.Type},
            {"valor", Currency.Type}, {"status", type text}
        },
        "en-US"
    ),
    // Condutor não identificado -> aponta para o membro desconhecido (ID 0)
    CondutorDesconhecido = Table.ReplaceValue(
        TiposAlterados, null, 0, Replacer.ReplaceValue, {"motorista_id"}
    ),
    ColunasRemovidas = Table.RemoveColumns(CondutorDesconhecido, {"obs_tratamento"})
in
    ColunasRemovidas
```

**fAusencia**
```m
let
    Fonte = Csv.Document(
        File.Contents(PastaDados & "fato_ausencia.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    CabecalhosPromovidos = Table.PromoteHeaders(Fonte, [PromoteAllScalars = true]),
    TiposAlterados = Table.TransformColumnTypes(
        CabecalhosPromovidos,
        {
            {"ausencia_id", Int64.Type}, {"data", type date},
            {"motorista_id", Int64.Type}, {"tipo_ocorrencia", type text},
            {"motivo", type text}, {"minutos_atraso", Int64.Type},
            {"justificada", type text}
        },
        "en-US"
    ),
    ColunasRemovidas = Table.RemoveColumns(TiposAlterados, {"obs_tratamento"})
in
    ColunasRemovidas
```

### 1.3 Os três cuidados que mais derrubam iniciantes

| Cuidado | O que acontece se ignorar | Como está resolvido |
|---|---|---|
| **Localidade do decimal** | Com o Power BI em pt-BR, `130.16` vira **13016** | O `"en-US"` no `Table.TransformColumnTypes` informa que o arquivo usa ponto decimal |
| **Codificação** | "Manhã" vira "ManhÃ£" | `Encoding = 65001` (UTF-8) |
| **Nulo ≠ zero** | Litros nulos trocados por 0 derrubam o km/L e criam consumo "infinito" | Nulos de litros, horas e custo **são mantidos**. As medidas DAX ignoram nulos automaticamente |

### 1.4 Confira a qualidade antes de fechar

**Exibição → marque Qualidade da coluna, Distribuição da coluna e Perfil da coluna**. Na barra
inferior, troque para **"Criação de perfil de coluna com base em todo o conjunto de dados"**
(o padrão olha só as primeiras 1.000 linhas). Nenhuma coluna pode mostrar **Erro** acima de 0%.
Vazios são esperados apenas em: `litros_combustivel`, `horas_trabalhadas`, `custo`,
`minutos_atraso` e `data_baixa`.

Confira também se o parâmetro `PastaDados` **não** será carregado como tabela: botão direito
nele → desmarque **Habilitar carga**. Parâmetros e consultas auxiliares não devem ir para o modelo.

Depois: **Fechar e Aplicar**.

> **Desafio opcional (portfólio nível 2):** refaça a limpeza **no Power Query** a partir de
> `data/raw/`, replicando as regras do `03_tratamento_dados.sql`. Mostrar a mesma regra em SQL
> e em M é um bom diferencial.

---

## 2. Relacionamentos do modelo

Vá em **Exibição de modelo**. O Power BI pode criar relações sozinho: **apague todas e crie
manualmente** (arrastando a coluna da dimensão até a coluna da fato), para ter controle.

| De (lado 1) | Para (lado *) | Cardinalidade | Direção do filtro |
|---|---|---|---|
| dCalendario[Data] | fViagem[data] | 1:* | Única |
| dCalendario[Data] | fManutencao[data_entrada] | 1:* | Única |
| dCalendario[Data] | fParadas[data] | 1:* | Única |
| dCalendario[Data] | fMulta[data] | 1:* | Única |
| dCalendario[Data] | fAusencia[data] | 1:* | Única |
| dVeiculo[veiculo_id] | fViagem[veiculo_id] | 1:* | Única |
| dVeiculo[veiculo_id] | fManutencao[veiculo_id] | 1:* | Única |
| dVeiculo[veiculo_id] | fParadas[veiculo_id] | 1:* | Única |
| dVeiculo[veiculo_id] | fMulta[veiculo_id] | 1:* | Única |
| dMotorista[motorista_id] | fViagem[motorista_id] | 1:* | Única |
| dMotorista[motorista_id] | fMulta[motorista_id] | 1:* | Única |
| dMotorista[motorista_id] | fAusencia[motorista_id] | 1:* | Única |

(As relações com dCalendario só podem ser criadas depois da seção 3.)

**Regras de ouro:**
- **Direção única** (dimensão filtra fato). Filtro bidirecional parece prático, mas gera
  ambiguidade e resultados errados quando há várias fatos. Evite.
- **Nunca ligue fato com fato.**
- **Oculte as chaves nas fatos** (botão direito em `veiculo_id` da fViagem → Ocultar na exibição
  de relatório). O usuário deve filtrar pela dimensão, nunca pela coluna da fato.
- **Organize visualmente:** dimensões em cima, fatos embaixo. Um print dessa tela vai para o README.

> **Pegadinha que vale ouro em entrevista:** `fManutencao` **não** tem motorista. Se você
> puser "Custo de Manutenção" num gráfico **por motorista**, todas as barras mostram o
> **total geral**, porque não existe caminho de filtro. Isso não é bug: é o modelo dizendo que
> essa pergunta não faz sentido com esses dados.

---

## 3. Tabela calendário em DAX

**Modelagem → Nova tabela** e cole:

```dax
dCalendario =
VAR _Inicio = DATE ( 2025, 1, 1 )
VAR _Fim    = DATE ( 2025, 12, 31 )
VAR _Base =
    SELECTCOLUMNS ( CALENDAR ( _Inicio, _Fim ), "Data", [Date] )
RETURN
    ADDCOLUMNS (
        _Base,
        "Ano",            YEAR ( [Data] ),
        "Mês Num",        MONTH ( [Data] ),
        "Mês",            FORMAT ( [Data], "mmm", "pt-BR" ),       -- jan, fev...
        "Mês Nome",       FORMAT ( [Data], "mmmm", "pt-BR" ),      -- janeiro...
        "AnoMês",         FORMAT ( [Data], "yyyy-mm" ),            -- 2025-01 (ordena certo)
        "Mês/Ano",        FORMAT ( [Data], "mmm/yy", "pt-BR" ),    -- jan/25
        "Trimestre",      "T" & QUARTER ( [Data] ),
        "Dia Semana Num", WEEKDAY ( [Data], 2 ),                   -- 1 = seg ... 7 = dom
        "Dia Semana",     FORMAT ( [Data], "ddd", "pt-BR" ),
        "Período Chuvoso", IF ( MONTH ( [Data] ) IN { 1, 2, 3, 11, 12 }, "Chuvas", "Estiagem" )
    )
```

Depois:
1. **Ferramentas de tabela → Marcar como tabela de datas** → coluna `Data`.
   Isso libera as funções de inteligência de tempo (`DATEADD`, `DATESMTD`...).
2. Selecione a coluna **Mês** → **Ferramentas de coluna → Classificar por coluna → Mês Num**.
   Faça o mesmo com **Mês Nome** e **Mês/Ano**. Sem isso os meses aparecem em ordem alfabética
   (abr, ago, dez...).
3. Faça o mesmo com **Dia Semana** → classificar por **Dia Semana Num**.
4. Crie as relações com as fatos (tabela da seção 2).

*Por que DAX e não o CSV?* Os dois funcionariam. O calendário em DAX é padrão de mercado,
fica independente da fonte e é fácil de estender. Num projeto real, troque as datas fixas por
`MIN`/`MAX` das datas das fatos para o calendário crescer sozinho.

---

## 4. Medidas DAX

### 4.1 Crie uma tabela só para medidas

**Página Inicial → Inserir dados** → nomeie a tabela `_Medidas` → Carregar. Crie todas as
medidas nela (**botão direito em _Medidas → Nova medida**) e depois oculte a coluna vazia.
O underline faz a tabela aparecer no topo da lista de campos.

Use **pastas de exibição** (Exibição de modelo → selecione a medida → Pasta de exibição) para
agrupar: `1 Custos`, `2 Frota`, `3 Multas`, `4 Pessoas`.

> **Medida vs coluna calculada:** a coluna é calculada linha a linha **na carga** e ocupa
> memória. A medida é calculada **na hora**, respeitando os filtros do visual. Para KPIs,
> use sempre medidas.

### 4.2 Custos

```dax
Preço Diesel (R$/L) = 6.20
```
Premissa de preço, a mesma do SQL. *Upgrade:* **Modelagem → Novo parâmetro → Intervalo
numérico** cria um controle deslizante para o gestor simular cenários ("e se o diesel subir 10%?").

```dax
Custo Manutenção = SUM ( fManutencao[custo] )

Custo Combustível = SUM ( fViagem[litros_combustivel] ) * [Preço Diesel (R$/L)]

Custo Multas =
CALCULATE (
    SUM ( fMulta[valor] ),
    fMulta[status] <> "Cancelada"          -- multa cancelada não é custo
)

Custo Total = [Custo Manutenção] + [Custo Combustível] + [Custo Multas]
```
**Custo Total** é composto de outras medidas (*medidas base*). Se a regra de multas mudar,
você altera num lugar só.

```dax
KM Rodado = SUM ( fViagem[km_rodado] )

Custo por KM = DIVIDE ( [Custo Total], [KM Rodado] )
```
**DIVIDE** em vez de `/`: se o divisor for zero ou vazio, retorna vazio em vez de erro.
*Custo por km* é o KPI que neutraliza o volume: o custo pode subir só porque a frota rodou mais.

```dax
Qtd OS = COUNTROWS ( fManutencao )

Ticket Médio Manutenção =
DIVIDE (
    [Custo Manutenção],
    CALCULATE ( COUNTROWS ( fManutencao ), NOT ISBLANK ( fManutencao[custo] ) )
)
```
O denominador exclui as 5 OS sem custo lançado. Se contasse todas, o ticket médio ficaria
artificialmente menor. (Daria o mesmo resultado que `AVERAGE(fManutencao[custo])`, mas assim a
regra fica explícita.)

```dax
Custo Corretiva =
CALCULATE ( [Custo Manutenção], fManutencao[tipo_manutencao] = "Corretiva" )

Custo Preventiva =
CALCULATE ( [Custo Manutenção], fManutencao[tipo_manutencao] = "Preventiva" )

% Custo Corretivo = DIVIDE ( [Custo Corretiva], [Custo Manutenção] )

OS sem Custo Lançado =
CALCULATE ( [Qtd OS], ISBLANK ( fManutencao[custo] ) )
```
**CALCULATE** é a função mais importante do DAX: calcula uma medida **mudando o filtro**.
Aqui, ela calcula o custo "como se" só existissem corretivas.

### 4.3 Variação mensal

```dax
Custo Total Mês Anterior =
CALCULATE ( [Custo Total], DATEADD ( dCalendario[Data], -1, MONTH ) )

Variação Mensal % =
VAR _Atual    = [Custo Total]
VAR _Anterior = [Custo Total Mês Anterior]
RETURN
    IF (
        HASONEVALUE ( dCalendario[AnoMês] ) && NOT ISBLANK ( _Anterior ),
        DIVIDE ( _Atual - _Anterior, _Anterior )
    )
```
- **VAR** guarda um resultado para reutilizar: o código fica legível e o DAX não recalcula.
- **DATEADD(..., -1, MONTH)** desloca o filtro de datas um mês para trás.
- **HASONEVALUE** garante que a variação só aparece quando há **um único mês** no contexto
  (numa tabela por mês). No total do ano, "variação sobre o mês anterior" não faz sentido.

Para um **cartão de KPI** (que não tem mês no contexto), use esta versão, que compara o
último mês do filtro com o anterior:
```dax
Variação Último Mês % =
VAR _UltimoMes   = CALCULATE ( [Custo Total], DATESMTD ( dCalendario[Data] ) )
VAR _MesAnterior =
    CALCULATE ( [Custo Total], DATEADD ( DATESMTD ( dCalendario[Data] ), -1, MONTH ) )
RETURN
    DIVIDE ( _UltimoMes - _MesAnterior, _MesAnterior )
```

### 4.4 Frota e disponibilidade

```dax
Frota Ativa =
CALCULATE ( COUNTROWS ( dVeiculo ), ISBLANK ( dVeiculo[data_baixa] ) )

Veículo-Dias na Frota =
SUMX (
    dVeiculo,
    VAR _Fim = COALESCE ( dVeiculo[data_baixa], DATE ( 2025, 12, 31 ) )
    RETURN
        COUNTROWS ( FILTER ( dCalendario, dCalendario[Data] <= _Fim ) )
)

Veículo-Dias Parados = COUNTROWS ( fParadas )

% Disponibilidade =
DIVIDE ( [Veículo-Dias na Frota] - [Veículo-Dias Parados], [Veículo-Dias na Frota] )

Meta Disponibilidade = 0.92
```
**Como ler o `SUMX`:** ele passa por **cada veículo** visível no filtro, conta quantos dias do
calendário (também filtrado) ele esteve na frota (até a baixa, se foi vendido) e soma tudo.
É um *iterador*: o "X" no nome indica que ele calcula linha a linha e depois agrega.
Com o filtro "março", o resultado é veículos × dias de março. Com o filtro "Pipa", só os pipas.

A meta de 92% é uma **premissa** (frotas urbanas costumam mirar entre 90% e 95%). Deixe isso
claro no dashboard.

### 4.5 Combustível

```dax
Litros Consumidos = SUM ( fViagem[litros_combustivel] )

Consumo (km/L) =
DIVIDE (
    CALCULATE ( [KM Rodado], NOT ISBLANK ( fViagem[litros_combustivel] ) ),
    [Litros Consumidos]
)
```
O km do numerador considera **só viagens com litros apontados**, a mesma regra do SQL `a06`.
Senão, o km "sem consumo" inflaria a eficiência.

### 4.6 Multas

```dax
Qtd Viagens = COUNTROWS ( fViagem )

Qtd Multas =
CALCULATE ( COUNTROWS ( fMulta ), fMulta[status] <> "Cancelada" )

Valor Multas = [Custo Multas]

Multas por 1.000 Viagens = DIVIDE ( [Qtd Multas], [Qtd Viagens] ) * 1000

Multas sem Condutor =
CALCULATE ( [Qtd Multas], fMulta[motorista_id] = 0 )

Ranking Motorista (Multas) =
IF (
    HASONEVALUE ( dMotorista[motorista_id] ),
    RANKX (
        FILTER ( ALL ( dMotorista ), dMotorista[motorista_id] <> 0 ),  -- ignora "Não identificado"
        [Qtd Multas], , DESC, DENSE
    )
)
```
- **Total de multas** é `Qtd Multas`. **Multas por 1.000 viagens** é a versão justa para
  comparar motoristas: quem dirige mais se expõe mais.
- **ALL** remove o filtro do motorista atual para o RANKX comparar com **todos**.

### 4.7 Absenteísmo

```dax
Qtd Faltas =
CALCULATE ( COUNTROWS ( fAusencia ), fAusencia[tipo_ocorrencia] = "Falta" )

Qtd Atrasos =
CALCULATE ( COUNTROWS ( fAusencia ), fAusencia[tipo_ocorrencia] = "Atraso" )

Horas de Atraso = DIVIDE ( SUM ( fAusencia[minutos_atraso] ), 60 )

Dias de Escala =
SUMX (
    dMotorista,
    VAR _Admissao = dMotorista[data_admissao]
    RETURN
        IF (
            ISBLANK ( _Admissao ),
            0,                                                -- membro "Não identificado"
            COUNTROWS (
                FILTER (
                    dCalendario,
                    dCalendario[Data] >= _Admissao
                        && dCalendario[Dia Semana Num] <> 7   -- domingo fora da escala
                )
            )
        )
)

Taxa de Absenteísmo = DIVIDE ( [Qtd Faltas], [Dias de Escala] )
```

### 4.8 Formatação das medidas

Selecione a medida → **Ferramentas de medida**:
- Custos: **Moeda R$**, 0 casas (Custo por KM e Ticket com 2 casas)
- Percentuais: **%** com 1 casa
- Contagens: número inteiro com separador de milhar

---

## 5. Validação: confira antes de desenhar qualquer gráfico

Crie uma página provisória com um **cartão por medida**, sem nenhum filtro. Os valores devem
bater com o SQL (diferenças só de arredondamento):

| Medida | Valor esperado (ano inteiro) | Fonte no SQL |
|---|---|---|
| Custo Total | R$ 4.203.364 | a05 (acumulado de dezembro) |
| Custo Manutenção | R$ 1.891.513 | a01 [B] (soma) |
| Custo Combustível | R$ 2.276.780 | a05 |
| Custo por KM | R$ 5,51 | a05 |
| KM Rodado | 763.075 | a05 |
| Qtd OS | 409 | |
| Ticket Médio Manutenção | R$ 4.681,96 | |
| % Custo Corretivo | 66,0% | |
| OS sem Custo Lançado | 5 | 02 diagnóstico [5] |
| % Disponibilidade | 91,3% | a02 |
| Veículo-Dias na Frota / Parados | 14.401 / 1.250 | |
| Frota Ativa | 38 | |
| Consumo (km/L) | ≈ 2,04 | a06 |
| Qtd Multas | 191 | |
| Valor Multas | R$ 35.071 | |
| Multas por 1.000 Viagens | 19,1 | |
| Multas sem Condutor | 12 | a03 [B] |
| Qtd Faltas / Atrasos | 266 / 576 | |
| Horas de Atraso | 284,1 | |
| Taxa de Absenteísmo | 1,6% | |

Testes com filtro:
- Tabela com **Mês** + **Variação Mensal %** → dezembro deve mostrar **+62,4%** e maio **-17,0%**.
- Tabela com **tipo** + **Consumo (km/L)** → Hidrojato 1,61 · Coleta 1,96 · Pipa 2,74.

Se algum número não bater, o problema quase sempre está em: tipo de dado/localidade (1.3),
relação faltando ou invertida (2) ou filtro de status esquecido na medida.

---

## 6. Layout das 3 páginas

**Configurações gerais:** tela 16:9 (1280 × 720). Importe o tema em **Exibir → Temas →
Procurar temas → `dashboards/tema_gestao_frota.json`**. Todas as páginas seguem a mesma grade:

```
┌──────────────────────────────────────────────────────────────────────┐
│ CABEÇALHO (60px): título · segmentações · botões de navegação        │
├──────────────────────────────────────────────────────────────────────┤
│ FAIXA DE KPIs (cartões, ~110px)                                      │
├───────────────────────────────────┬──────────────────────────────────┤
│ VISUAL PRINCIPAL (a pergunta #1)  │ VISUAL DE APOIO                  │
├───────────────────────────────────┼──────────────────────────────────┤
│ VISUAL DE DETALHE                 │ VISUAL DE DETALHE / INSIGHT      │
└───────────────────────────────────┴──────────────────────────────────┘
```

**Segmentações (iguais nas 3 páginas):** `Mês/Ano` (lista suspensa), `dVeiculo[tipo]` (botões),
`dVeiculo[base_operacional]` (lista suspensa). Sincronize em **Exibir → Sincronizar
segmentações**, para que o filtro escolhido numa página valha nas outras.

**Navegação:** 3 botões no cabeçalho (**Inserir → Botões → Navegador de páginas**).

### Página 1: Visão Geral
*Pergunta que responde:* "Como está a operação da frota e onde preciso olhar?"

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Gestão de Frota · Visão Geral        [Mês ▾] [Coleta|Hidro|Pipa] [Base ▾]│
├───────────┬───────────┬───────────┬───────────┬───────────┬──────────────┤
│Custo Total│ Custo/km  │Disponib.  │ KM Rodado │  Multas   │ Absenteísmo  │
│ R$ 4,2 mi │  R$ 5,51  │  91,3 %   │  763 mil  │   191     │   1,6 %      │
│▲ 62% m/m  │           │ meta 92%  │           │           │              │
├───────────┴───────────┴─────────┬─┴───────────┴───────────┴──────────────┤
│ Custo mensal por componente     │ Disponibilidade por tipo de veículo    │
│ colunas empilhadas + linha R$/km│ barras + linha de meta (92%)           │
├─────────────────────────────────┼────────────────────────────────────────┤
│ Sazonalidade: rotas/mês por tipo│ Destaques do período (caixa de texto)  │
└─────────────────────────────────┴────────────────────────────────────────┘
```

| Visual | Tipo | Campos |
|---|---|---|
| 6 KPIs | Cartão (novo) | Custo Total (com `Variação Último Mês %` como valor de referência), Custo por KM, % Disponibilidade (referência: Meta), KM Rodado, Qtd Multas, Taxa de Absenteísmo |
| Custo mensal | Gráfico de colunas empilhadas e de linhas | Eixo X: Mês · Colunas: Custo Manutenção, Custo Combustível, Custo Multas · Linha: Custo por KM |
| Disponibilidade por tipo | Barras clusterizadas | Eixo Y: tipo · Valor: % Disponibilidade · **Painel Análise → Linha constante = 0,92** |
| Sazonalidade | Gráfico de linhas | Eixo X: Mês · Valor: Qtd Viagens · Legenda: tipo |
| Destaques | Caixa de texto | 2 ou 3 frases com os principais achados (Etapa 4) |

### Página 2: Manutenção e Custos
*Pergunta que responde:* "Para onde vai o dinheiro de manutenção e quais caminhões são problema?"

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Gestão de Frota · Manutenção e Custos         [segmentações]  [navegação]│
├───────────┬───────────┬───────────┬───────────┬───────────┬──────────────┤
│Custo Manut│ Qtd OS    │Ticket Méd.│% Corretivo│Dias Parad.│OS s/ custo ⚠ │
├───────────┴───────────┴─────────┬─┴───────────┴───────────┴──────────────┤
│ Preventiva x Corretiva por mês  │ Idade x Custo (dispersão por veículo)  │
│ colunas empilhadas              │ tamanho da bolha = dias parado         │
├─────────────────────────────────┼────────────────────────────────────────┤
│ Top veículos por custo (matriz) │ Custo corretivo por serviço (barras)   │
└─────────────────────────────────┴────────────────────────────────────────┘
```

| Visual | Tipo | Campos |
|---|---|---|
| KPIs | Cartão | Custo Manutenção, Qtd OS, Ticket Médio, % Custo Corretivo, Veículo-Dias Parados, OS sem Custo Lançado (fonte vermelha se > 0: **formatação condicional**) |
| Preventiva x Corretiva | Colunas empilhadas | Eixo: Mês · Valores: Custo Preventiva, Custo Corretiva. **Cores fixas:** Preventiva `#8DA9C4`, Corretiva `#D1495B` |
| Idade x Custo | Gráfico de dispersão | Valores: dVeiculo[Veículo] · X: idade_anos · Y: Custo Corretiva · Tamanho: Veículo-Dias Parados · Legenda: tipo |
| Top veículos | Matriz | Linhas: Veículo · Valores: Custo Manutenção, % Custo Corretivo, % Disponibilidade, Qtd OS. **Barras de dados** no custo e **escala de cor** na disponibilidade. Filtro do visual: **Top N = 10** por Custo Manutenção |
| Por serviço | Barras horizontais | Eixo: servico · Valor: Custo Corretiva · ordenado decrescente |

**Visual extra recomendado:** barras clusterizadas por `faixa_idade` comparando a participação
na frota com a participação no custo corretivo. É o gráfico que "vende" a renovação de frota.
Ele precisa de duas medidas extras:
```dax
% da Frota =
DIVIDE ( COUNTROWS ( dVeiculo ), CALCULATE ( COUNTROWS ( dVeiculo ), ALL ( dVeiculo[faixa_idade] ) ) )

% do Custo Corretivo =
DIVIDE ( [Custo Corretiva], CALCULATE ( [Custo Corretiva], ALL ( dVeiculo[faixa_idade] ) ) )
```

### Página 3: Motoristas e Multas
*Pergunta que responde:* "Quais pessoas e comportamentos geram custo e risco?"

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Gestão de Frota · Motoristas e Multas         [segmentações] [Turno ▾]   │
├───────────┬───────────┬───────────┬───────────┬───────────┬──────────────┤
│Qtd Multas │Valor Mult.│Mult/1000v │Sem condut.│Absenteísmo│Horas atraso  │
├───────────┴───────────┴─────────┬─┴───────────┴───────────┴──────────────┤
│ Top 10 motoristas por multas    │ Multas por infração e gravidade        │
│ barras horizontais              │ barras empilhadas                      │
├─────────────────────────────────┼────────────────────────────────────────┤
│ Faltas e atrasos por mês        │ Painel do motorista (matriz)           │
│ colunas clusterizadas           │ ranking, multas, pontos, faltas        │
└─────────────────────────────────┴────────────────────────────────────────┘
```

| Visual | Tipo | Campos |
|---|---|---|
| KPIs | Cartão | Qtd Multas, Valor Multas, Multas por 1.000 Viagens, Multas sem Condutor, Taxa de Absenteísmo, Horas de Atraso |
| Top 10 | Barras horizontais | Eixo: dMotorista[nome] · Valor: Qtd Multas · Filtro Top N 10 · Dica de ferramenta: Valor Multas, Multas por 1.000 Viagens |
| Por infração | Barras empilhadas | Eixo: infracao · Valor: Qtd Multas · Legenda: gravidade (Média âmbar, Grave laranja, Gravíssima vermelho) |
| Faltas e atrasos | Colunas clusterizadas | Eixo: Mês · Valores: Qtd Faltas, Qtd Atrasos. Revela o Carnaval (março) e as chuvas |
| Painel do motorista | Matriz | Linhas: nome · Valores: Ranking Motorista (Multas), Qtd Viagens, Qtd Multas, Multas por 1.000 Viagens, Taxa de Absenteísmo, Qtd Atrasos. Ícones (formatação condicional) na taxa de absenteísmo |

Segmentação extra nesta página: `dMotorista[turno]`.

**Bônus (vale muito no portfólio): página de detalhamento.** Crie uma 4ª página "Ficha do
Motorista" com `dMotorista[nome]` no campo **Detalhamento**. No dashboard, o usuário clica com o
botão direito num motorista → **Detalhamento** → e vê o histórico só dele.

---

## 7. Boas práticas de design

**Hierarquia visual (padrão Z):** o olho lê da esquerda para a direita e de cima para baixo.
Por isso: título → KPIs → gráfico principal (canto superior esquerdo) → detalhes embaixo.
O número mais importante fica no topo, à esquerda.

**Paleta (já no tema JSON):**

| Uso | Cor | Hex |
|---|---|---|
| Coleta (e cor principal da marca) | Azul | `#1F6FB2` |
| Hidrojato | Verde-azulado | `#2A9D8F` |
| Pipa | Âmbar | `#E9A23B` |
| Preventiva | Azul acinzentado | `#8DA9C4` |
| Corretiva / alerta / abaixo da meta | Vermelho coral | `#D1495B` |
| Texto secundário | Cinza | `#5C677D` |
| Fundo da página | Cinza muito claro | `#F3F5F8` |

- **Cor tem significado e é consistente:** "Coleta" é azul em **todas** as páginas, e vermelho
  aparece **só** para o que é ruim (corretiva, acima da meta, alerta). Se tudo é colorido, nada
  se destaca.
- No máximo 5 ou 6 cores por página. Prefira tons da mesma cor a cores novas.
- **Não use só vermelho x verde** para bom/ruim (cerca de 8% dos homens são daltônicos):
  combine com ícone, seta ou texto.

**Alinhamento e espaçamento:**
- **Exibir → Linhas de grade** e **Ajustar à grade** ligados.
- Mesma margem em volta de tudo (16px) e o mesmo espaço entre os visuais.
- Cartões de KPI com **exatamente** o mesmo tamanho: selecione todos → **Formatar →
  Alinhar → Distribuir horizontalmente**.
- Use o **Painel de Seleção** (Exibir) para nomear e organizar as camadas.

**Clareza dos gráficos:**
- **Títulos que dizem algo:** "Caminhões com mais de 10 anos concentram 53% do custo corretivo"
  em vez de "Custo por faixa". O título já entrega a conclusão.
- Remova poluição: linhas de grade fortes, bordas, legendas desnecessárias (se há só uma série,
  tire a legenda) e eixos redundantes quando já existe rótulo de dados.
- Valores grandes em **milhares/milhões** (R$ 4,2 mi), nunca R$ 4.203.364,46 num cartão.
- **Nada de pizza com mais de 3 fatias** e nada de 3D. Barras ordenadas são quase sempre melhores.
- Ordene as barras do maior para o menor, a não ser que o eixo seja tempo.
- Toda informação extra vai para a **dica de ferramenta** (tooltip), não para o visual.

**Acessibilidade e acabamento:**
- Texto alternativo em cada visual (**Formatar → Geral → Texto alternativo**).
- Contraste mínimo: texto escuro em fundo claro (o tema já garante).
- Rodapé discreto: "Dados fictícios · Atualizado em 31/12/2025 · Fonte: sistema de frota (simulado)".
- **Antes de publicar:** revise cada página com um filtro ativo e veja se algum visual "quebra"
  (fica vazio ou com valores estranhos).

---

## 8. Entregáveis desta etapa (para o repositório)

- `dashboards/gestao_frota.pbix`
- `dashboards/prints/01_visao_geral.png`, `02_manutencao_custos.png`, `03_motoristas_multas.png`,
  `00_modelo.png` (print da exibição de modelo)
- Exporte também um **PDF** (**Arquivo → Exportar → PDF**). Recrutadores sem Power BI conseguem abrir.
