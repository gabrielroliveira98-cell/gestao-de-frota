# Principais Insights e Recomendações

> **Como usar este arquivo:** os números abaixo saíram das queries de `queries/analises/` e
> devem bater com o seu dashboard. Se você alterar algo (seed, regras de limpeza, premissas),
> atualize os números e mantenha a estrutura. O bloco **"Resumo executivo"** vai para o
> README e para a caixa de texto da página Visão Geral.

---

## Resumo executivo

Em 2025 a frota custou **R$ 4,2 milhões** (R$ 5,51 por km rodado), com disponibilidade de
**91,3%**, abaixo da meta de 92%. Três frentes concentram a maior parte do problema:
**caminhões de coleta com mais de 10 anos**, que custam 3x mais em manutenção corretiva;
**três veículos crônicos**, que sozinhos tiram a frota da meta de disponibilidade; e **poucos
motoristas**, que concentram multas e faltas. As ações propostas são direcionadas e têm
indicador de acompanhamento.

---

## Insight 1: Caminhões de coleta com mais de 10 anos custam 3x mais em corretiva

**Achado.** Os veículos com mais de 10 anos são **32,5% da frota**, mas respondem por
**52,7% do custo de manutenção corretiva** (R$ 658 mil de R$ 1,25 milhão). Na coleta, que
reúne 10 dos 13 caminhões antigos, o custo corretivo médio é de **R$ 59,6 mil por caminhão
antigo, contra R$ 19,1 mil por caminhão com até 5 anos (3,1x)**. Os antigos também ficam mais
tempo parados (31,8 contra 14,5 dias/ano) e consomem 11% mais diesel por km.

**Teste de robustez.** Retirando as duas trocas de motor (R$ 103 mil e R$ 78,5 mil, ambas
em caminhões antigos), os veículos com mais de 10 anos ainda somam **44,6%** do custo corretivo.
O achado não depende de outliers.

**Ressalva.** Em pipa e hidrojato há apenas 1 ou 2 veículos antigos por tipo. Amostra pequena
demais para concluir algo nesses grupos.

**Recomendação.** Abrir um estudo de **renovação dos caminhões de coleta com mais de 10 anos**,
começando por **UEM1R47** e **HUO4N56**: juntos custaram R$ 342 mil (18% de toda a manutenção
da frota), com duas trocas de motor no ano. Estimativa de ganho por caminhão substituído:
**R$ 20 a 40 mil/ano** em corretiva, mais ~R$ 6 mil/ano em diesel e ~17 dias a mais de
disponibilidade. Esse valor deve ser comparado ao custo de aquisição ou locação (próximo passo).

**Indicador de acompanhamento.** Custo corretivo por veículo, por faixa de idade (trimestral).

*Fonte: `a07_custo_corretivo_por_idade.sql`, `a06` [B] · Dashboard: página 2, dispersão Idade x Custo.*

---

## Insight 2: A manutenção é reativa e as quebras se concentram no verão

**Achado.** **66% do gasto de manutenção é corretivo** (R$ 1,25 mi) e só 34% é preventivo.
Numa frota bem gerida, a proporção tende ao contrário. Além disso, **48% do custo corretivo
do ano ocorreu entre dezembro e março**: 4 meses, ou 33% do calendário.

**Cuidado com a leitura.** O salto de **+62% no custo total de dezembro** em relação a
novembro tem um evento pontual dentro dele: uma troca de motor de R$ 103 mil (41% da
manutenção do mês). Sem ela, a alta seria de **+27%**, o que ainda é relevante e coerente com
a sazonalidade do verão (mais resíduo, mais chuva, mais horas de operação).

**Recomendação.** Criar uma **"Operação Verão"**: antecipar para outubro e novembro uma
revisão reforçada dos sistemas que mais quebram no período (freios, compactador hidráulico,
bomba de alta pressão). Para OS acima de R$ 30 mil, exigir **duas cotações e aprovação da
gestão**.

**Indicador de acompanhamento.** % do custo de manutenção que é preventivo (meta inicial
sugerida: 45% em 12 meses) e custo corretivo de dezembro a março em relação ao ano anterior.

*Fonte: `a01` [B], `a05` · Dashboard: página 2, colunas Preventiva x Corretiva.*

---

## Insight 3: Três caminhões tiram a frota da meta de disponibilidade

**Achado.** A disponibilidade da frota foi de **91,3%** (meta: 92%). Os três piores veículos
(**UEM1R47**: 81 dias parado, **ZRK4K81**: 79 dias, **DPC6Q08**: 69 dias) somam **229 dias
parados, 18% do total da frota**. **73% de todos os dias parados vêm de corretivas.**

**Simulação.** Se esses três caminhões ficassem parados o mesmo que a mediana da frota
(~26 dias), a disponibilidade subiria para **92,4%**, acima da meta, sem mexer no resto da frota.

**Recomendação.** Tratar os três como **casos individuais**: diagnóstico de causa raiz das
quebras repetidas e decisão em 60 dias entre reforma completa e substituição. Para o
UEM1R47, o mais caro e o mais parado, a recomendação é **substituir** (ver Insight 1).
Enquanto isso, manter um **veículo reserva de coleta** nos meses de pico.

**Indicador de acompanhamento.** % de disponibilidade mensal por veículo, com alerta abaixo de 85%.

*Fonte: `a02_veiculos_mais_tempo_parados.sql` · Dashboard: página 1, disponibilidade por tipo; página 2, matriz Top veículos.*

---

## Insight 4: Um motorista concentra 15% do valor das multas e há risco de suspensão de CNH

**Achado.** As multas são **concentradas**. O motorista líder do ranking acumulou **27 multas
(98,5 por 1.000 viagens, 5x a média da frota de 19,1)**, 15% do valor total e **134 pontos**,
muito acima do limite de 40 pontos para motorista profissional. Os 3 primeiros do ranking
somam 28% do valor. As infrações mais frequentes são **comportamentais**: excesso de
velocidade (55), falta de cinto (36) e estacionamento proibido (32). As gravíssimas são 22% das
multas, mas 36% do valor.

**Achado secundário.** **12 multas (6,3%) não têm condutor identificado.** Ninguém responde
por elas e a empresa fica com o custo. Isso indica falha no controle de quem dirige qual veículo.

**Recomendação.**
1. **Ação individual imediata** com o motorista líder: o volume de pontos pode levar à
   suspensão da CNH, e aí ele não pode dirigir (risco operacional e jurídico).
2. **Reciclagem em direção defensiva** para os 10 primeiros do ranking, com foco em
   velocidade e cinto.
3. **Checklist de saída assinado** (motorista × placa × horário) para zerar as multas sem condutor.
4. Pagar as **49 multas pendentes** dentro do prazo para aproveitar o desconto (de 20%, ou de
   até 40% via Sistema de Notificação Eletrônica, quando não houver recurso).

**Indicador de acompanhamento.** Multas por 1.000 viagens (meta: abaixo de 15) e % de multas sem condutor (meta: 0%).

*Fonte: `a03_ranking_motoristas_multas.sql` · Dashboard: página 3.*

---

## Insight 5: O absenteísmo é concentrado e os atrasos sobem 48% na época de chuvas

**Achado.** A taxa média de absenteísmo é de **1,6%**, mas **25% dos motoristas (o 1º quartil)
concentram 53% de todas as faltas**. Das 266 faltas do ano, **42% foram injustificadas**.
Os **atrasos sobem 48% nos meses de chuva** (59 por mês, contra 40 na estiagem), e 68
ocorrências foram atribuídas a chuva ou alagamento. As faltas ficam acima da média
mensal (22) em março (Carnaval), julho (férias escolares) e dezembro (festas).

**Cruzamento.** O motorista líder em multas também está no 1º quartil de absenteísmo. Há
um **perfil de risco** que aparece em mais de um indicador.

**Recomendação.**
1. **Conversa individual com o RH** para os motoristas do 1º quartil, separando quem tem
   problema de saúde (faltas justificadas, que pedem acolhimento) de quem tem faltas
   injustificadas recorrentes (que pedem medida disciplinar).
2. **Plano para a época de chuvas** (novembro a março): antecipar a saída das rotas mais
   expostas a alagamento e ampliar o **banco de reservas** nesse período e no Carnaval.

**Indicador de acompanhamento.** Taxa de absenteísmo mensal e atrasos por mês, comparando chuva e estiagem.

*Fonte: `a04_ranking_absenteismo.sql`, `a08` · Dashboard: página 3, faltas e atrasos por mês.*

---

## Premissas e limitações

- **Dados fictícios**, gerados para fins de estudo (`scripts/gerar_dados.py`).
- **Preço do diesel:** R$ 6,20/L (premissa). **Meta de disponibilidade:** 92% (premissa).
- **2% das viagens não têm litros apontados**, então o custo de combustível está levemente subestimado.
- **5 OS sem custo lançado** ficaram fora da soma de manutenção (devem ser cobradas da oficina).
- As análises mostram **associação, não causalidade**. Por exemplo, caminhões antigos podem
  operar em rotas mais pesadas. A recomendação de renovação deve ser confirmada com um
  estudo de custo total de propriedade (TCO).

---

## Guia: como escrever um bom insight (para adaptar aos seus números)

**Estrutura de cada insight:**

| Bloco | Pergunta que responde | Exemplo |
|---|---|---|
| **Título** | Qual é a conclusão? (uma frase, com número) | "Três caminhões tiram a frota da meta" |
| **Achado** | O que os dados mostram? | "229 dias parados, 18% do total" |
| **Contexto ou robustez** | Isso se sustenta? Tem pegadinha? | "Sem o outlier, a alta cai de 62% para 27%" |
| **Recomendação** | O que fazer, quem faz, até quando? | "Decidir reforma ou substituição em 60 dias" |
| **Indicador** | Como saber se funcionou? | "Disponibilidade mensal por veículo" |

**Modelo em branco:**
```
## Insight N: [conclusão em uma frase, com número]
**Achado.** [O grupo X] representa [A%] de [base], mas concentra [B%] de [métrica].
**Teste de robustez.** Sem [outlier/evento], o resultado passa a ser [C].
**Recomendação.** [Ação concreta] para [público/ativo] em [prazo]. Ganho estimado: [R$/dias].
**Indicador de acompanhamento.** [KPI] com meta de [valor] até [data].
*Fonte: [query] · Dashboard: [página/visual].*
```

**Checklist antes de apresentar:**
- [ ] O título tem um **número** e uma **conclusão**, não só o nome do tema?
- [ ] Comparei com uma **base justa** (por veículo, por 1.000 viagens, por dia de escala)?
- [ ] Verifiquei se **um outlier** explica sozinho o resultado?
- [ ] A recomendação é uma **ação** (verbo, responsável, prazo) e não "monitorar"?
- [ ] Deixei claras as **premissas** e o que os dados **não** permitem afirmar?

**Erros comuns de iniciante:**
- Descrever o gráfico ("o custo subiu em dezembro") em vez de interpretar ("subiu por causa de
  um evento pontual; sem ele, a alta é sazonal e previsível").
- Comparar totais de grupos de tamanhos diferentes (22 caminhões de coleta × 8 hidrojatos).
- Apresentar 15 insights. A gestão guarda 3. Priorize por **impacto financeiro**.
- Expor nomes de pessoas num material amplo. Em empresa real, ranking nominal de motorista
  é tratado com o RH e com a LGPD em mente. Num dashboard público, prefira "Motorista A, B, C".
