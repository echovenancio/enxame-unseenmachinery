# Enxame — modelo e limites

Simulador exploratório de comportamento em Godot 4.5.2. Não existe validação experimental deste confronto. O resultado não prevê lesões, mortalidade ou segurança de exposição a formigas.

## Unidades e integração

O diâmetro do octógono é medido entre faces opostas em metros. Peso em kg, altura em m, temperatura em °C, vento em m/s, umidade em % e chuva em mm/h. A integração usa passos fixos de 0,1 s. A mesma configuração, semente e versão reproduzem a mesma trajetória. Se a CPU não suporta a velocidade escolhida, a velocidade efetiva cai; o relógio virtual só avança com passos realmente calculados.

A ampliação inicial das formigas é 8× e afeta somente a imagem. O modo 1:1 restaura o tamanho de referência real. Geometria regular de oito lados, piso homogêneo, uma espécie/colônia, ausência de reprodução e castas são condições de contorno. Sem fuga, uma barreira idealizada retém insetos; com fuga, cruzar a borda remove o inseto da arena.

## População e desempenho

Até 6.000 agentes usam posições independentes. Acima disso, a população é distribuída em grupos inteiros, com o resto distribuído sem perdas. Cada grupo percorre uma trajetória representativa. Pisadas e contato aplicam uma aproximação binomial aos integrantes. A aproximação conserva contagens, mas aumenta correlação e variância espacial: não resolve cada microcolisão.

Formigas sobre o corpo são contabilizadas separadamente. Removê-las pode esmagar parte e devolver o restante ao piso. A devolução usa um slot livre ou se funde ao grupo mais próximo. O invariante verificado é:

`população inicial = no chão + nos corpos + removidas + fugitivas`

Arrays compactos, grade espacial 64×64, mapa de proximidade dos humanos e MultiMesh evitam um nó ou corpo rígido por formiga. Humanos usam apoio dos pés e cinemática inversa planar das pernas, cotovelos independentes e movimentos de defesa/exaustão. O contato com insetos é calculado na projeção planar dos pés; insetos sobre o corpo são um compartimento agregado. Esta versão não é um solver de biomecânica corporal 3D.

## Representação visual de grandes populações

O limite aceito é 10.000.000. O número no HUD é a população modelada viva, não a quantidade de malhas. Até 6.000 trajetórias são instanciadas em lotes MultiMesh. Cada instância contém até 8 detalhes no desktop / 4 no celular, ocultando as cópias que excedem o peso do grupo. Somam no máximo 48.000 / 24.000 formigas detalhadas. À distância são silhuetas recortadas; perto da câmera, até 512 grupos no desktop / 256 no celular usam a malha articulada (4.096 / 1.024 modelos). As pernas usam um padrão de tripés alternados no shader e param com o tempo virtual.

A população no chão que excede esses detalhes é depositada por interpolação bilinear numa grade 64×64, suavizada e convertida em cobertura óptica `1-exp(-densidade*área_representativa)`. A área representativa é 0,65 × comprimento²: hipótese visual, não medida biológica. Um shader anima a textura pelo fluxo local. A camada fica mais escura e preenchida com populações maiores; não substitui uma formiga pequena por um gigante.

O custo de memória depende das 6.000 trajetórias, dos lotes e da grade. Transformações atualizam a até 12,5 Hz e a densidade a aproximadamente 3,3 Hz; o shader anima entre envios. Campos e buffers estáticos são reutilizados em pausa. A densidade é combinada no material do próprio piso para evitar sobreposição de superfícies e z-fighting. A densidade não resolve cada corpo, contato ou empilhamento. Acima de um milhão em arenas pequenas, a falta de exclusão de volume e camadas físicas é especialmente relevante. Os 10 milhões não têm posições e IAs individuais.

## Formigas

Operárias fazem caminhada exploratória persistente. O campo de alarme decai e seu gradiente modifica a caminhada. Proximidade e movimento dos pés podem provocar uma resposta defensiva local quando há defesa do ninho ou alarme. Exploração sem ninho não vira perseguição global. Subir num humano exige proximidade. Calçado e movimento reduzem contato. Um limite dependente do tamanho da operária e da altura humana impede adesão ilimitada instantânea.

| Perfil | Comprimento representativo | Velocidade de referência* | Resposta |
|---|---:|---:|---|
| Solenopsis invicta | 4 mm | 0,045 m/s | Mordida, ferroada e recrutamento por alarme |
| Paraponera clavata | 25 mm | 0,075 m/s | Ferroada de dor persistente; menor recrutamento |
| Camponotus floridanus | 9 mm | 0,065 m/s | Mordida / ácido fórmico; sem ferrão |
| Pheidole megacephala | 3 mm | 0,033 m/s | Mordida defensiva de baixo efeito; sem ferroada |

*Velocidades, capacidades, taxas de contato, retirada e coeficientes ambientais são hipóteses ajustáveis no código, não calibração experimental. Comprimentos são referências médias; a versão não sorteia castas ou tamanhos. A distinção qualitativa entre mordida e ferroada segue as fontes abaixo.

Atividade usa um fator gaussiano em torno de uma temperatura de referência, combinado com um fator de umidade. Perda em temperaturas extremas é heurística; não representa uma curva térmica medida por espécie. Vento e chuva aceleram o decaimento do alarme; não existe uma solução aerodinâmica detalhada.

## Humanos

Peso, altura, condicionamento, tolerância e calçado podem ser individuais. `Editar humano = 0` aplica um perfil uniforme e limpa alterações individuais. Outros números editam aquele participante e o selecionam para a câmera de acompanhamento.

Reação automática evita concentrações, remove formigas aderidas e pisa quando ameaçada. Modos adicionais: evitar formigas, defender/pisar ou ficar imóvel. Pisadas usam área física dependente da altura e largura dependente do peso. Piso, calçado, aderência e chuva modificam o contato. Areia reduz esmagamento. Movimento, defesa, calor e dor geram esforço; descanso recupera energia. A velocidade se aproxima da direção desejada com aceleração limitada; uma penalidade de mudança de direção evita alternância constante entre caminhos de densidade quase equivalente. A direção escolhida é mantida por aproximadamente um segundo; a decisão pode ser antecipada por dor/alarme ou proximidade da borda. A pisada busca alvos num arco à frente. Esses parâmetros e a duração de remoção de insetos são escolhas exploratórias, não dados de captura de movimento.

Dor 0–100 é um índice interno, não escala clínica, dose de veneno, toxicidade ou chance de morte. Dor e letalidade são dimensões diferentes. Um participante retira-se após permanecer no limiar de dor/exaustão pelo intervalo dependente da tolerância. Nenhum humano é declarado morto.

## Resultado e exportação

A rodada admite retirada dos humanos, nenhum inseto ativo, ausência inicial de oposição ou encerramento pelo relógio. O relógio pode resultar em coexistência: não força um vencedor. `Removidas` inclui esmagamento e perdas térmicas heurísticas. `Ativas` inclui insetos no piso e nos corpos, mesmo após a retirada de um humano.

CSV: tempo virtual, formigas ativas, humanos ativos, dor/energia médias, contatos e exposições acumuladas. O nome inclui a semente. O simulador não usa backend, serviço de IA ou dados pessoais.

## Fontes

- [NC State Extension — Biology & Behavior of Red Imported Fire Ant](https://content.ces.ncsu.edu/biology-behavior-of-red-imported-fire-ant-rifa): defesa, alarme e ferroadas de Solenopsis invicta.
- [UF/IFAS — Red imported fire ant worker](https://entnemdept.ufl.edu/projex/gallery/dl/Beneficial_Arthropods_Parasitoids/TEXT/HYM_Red_imported_fire_ant_Solenopsis_invicta.html): operárias de 2,4–6 mm.
- [UF/IFAS — Camponotus floridanus](https://ask.ifas.ufl.edu/publication/IN455) e [Florida Carpenter Ants](https://ask.ifas.ufl.edu/publication/IN1075): mordida e ácido fórmico, sem ferroada.
- [UF/IFAS — Pheidole megacephala](https://ask.ifas.ufl.edu/publication/IN712): ausência de ferroada e mordida defensiva geralmente pouco dolorosa.
- [Haddad et al., 2005](https://pubmed.ncbi.nlm.nih.gov/16138209/): contexto biológico e clínico de Paraponera / Dinoponera; não usado para inventar probabilidades de morte.
- [Schmidt, 2019 — Pain and Lethality Induced by Insect Stings](https://pubmed.ncbi.nlm.nih.gov/31330893/): distinção entre dor e letalidade.
- [Godot 4.5 — Web](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_web.html) e [MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).

## Verificação

`godot --headless --path godot --script res://tests/test_simulation.gd`

Testes: determinismo, conservação individual e agrupada, posições finitas, limites da arena, quatro espécies, fuga, frio, casos vazios e encerramento por tempo. `test_ui.gd` verifica perfis individuais, pausa, configuração pendente, orçamento de render, maior cobertura para 10 milhões e layout móvel. `test_animation.gd` verifica apoio dos pés, posições finitas e postura de retirada. Benchmark mede o núcleo e não promete FPS numa GPU específica. A imagem foi verificada na engine usando OpenGL por software. A build Windows foi exportada; execução no Windows não foi testada neste ambiente Linux.
