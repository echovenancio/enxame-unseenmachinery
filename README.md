# Enxame

Simulador de humanos × formigas em um octógono de MMA, feito em **Godot 4.5.2**. Arena, interface, personagens e modelo rodam na engine. Não usa Three.js.

Visual: low-poly, texturas pequenas com filtro nearest, snapping dos vértices, UV afim, paleta de 5 bits, dithering e um galpão escuro.

## Jogar

- Web: [Jogar Enxame](https://enxame.monvenancio4.chatgpt.site). Chrome / Firefox atual, WebGL 2 e WebAssembly. No celular, `MENU` abre o menu de pausa; as abas Luta, Corpo, Arena e Visual reúnem os ajustes. A primeira abertura carrega aproximadamente 38 MB de engine.
- Linux x86_64: extrair o ZIP; manter executável e `enxame.pck` juntos. `chmod +x enxame.x86_64` e abrir o executável.
- Windows x86_64: extrair o ZIP e abrir `enxame.exe`, mantendo `enxame.pck` na mesma pasta.

Configure 0–10.000.000 formigas, 0–32 humanos, espécie, contexto da colônia, perfis humanos, diâmetro de 4–30 m, piso, temperatura, umidade, vento, chuva e fuga. A semente repete uma rodada. Mudanças durante a execução ficam pendentes até iniciar outra.

`Editar humano = 0` aplica peso, altura, condicionamento, tolerância e calçado a todos. `1`, `2`, etc. editam só aquele indivíduo e o selecionam para acompanhamento.

Arraste para orbitar; roda / pinça aproxima. `Esc` abre / fecha o menu, `Espaço` pausa, `R` prepara novamente e `1/2/3` alternam câmera. Câmera, ampliação, feromônios e filtro PS1 estão na aba Visual. `CSV` exporta a série temporal. A rodada abre em tempo normal, 1×. Velocidade desejada: 0,5× a 32×; a velocidade efetiva cai quando a CPU não acompanha.

## Editar e exportar

Importe `godot/project.godot` no [Godot 4.5.2](https://godotengine.org/download/archive/4.5.2-stable/) ou compatível e pressione F5. Sem npm, add-ons ou assets pagos. Texturas e malhas são procedurais; as fontes DejaVu incluem licenças em `godot/assets/FONT-LICENSE.txt` e `GAME-FONT-LICENSE.txt`.

- `godot/scripts/simulation.gd`: modelo, espécies e ambiente.
- `godot/scripts/arena.gd`: personagens articulados, malhas, MultiMesh e câmera.
- `godot/scripts/main.gd`: interface, tempo virtual e CSV.
- `godot/shaders/`: efeitos retro.
- `MODEL.md`: hipóteses, limitações, fontes e interpretação do resultado.

Instale os templates oficiais da mesma versão para exportar. `python3 tools/build.py --engine /caminho/para/godot` cria Web e divide a engine em arquivos cacheáveis para hospedagem estática. O Web usa single-thread e Compatibility. Presets Linux / Windows também estão no projeto. A build Web precisa de servidor HTTP; não funciona via `file://`.

## Realismo

Até 6.000 agentes de solo; acima disso, grupos inteiros conservam a população com menor precisão espacial. A ampliação visual inicial é 8×, com opção 1:1; não muda a física. Comportamentos são plausíveis e documentados, mas os coeficientes de contato, dor, retirada e ambiente são heurísticos. Não é um modelo médico ou biomecânico validado.

## Renderização do enxame

O limite de população é **10 milhões**. Até 6.000 trajetórias calculam o comportamento; acima disso são grupos, não 10 milhões de IAs independentes. Cada grupo desenha até 8 formigas detalhadas no desktop ou 4 no celular, por MultiMesh e shader de marcha com tripés alternados. À distância usam silhuetas recortadas; perto da câmera há até 4.096 modelos completos no desktop ou 1.024 no celular. O máximo é 48.000 / 24.000 detalhes 3D. A população restante compõe uma textura de densidade e fluxo 64×64 aplicada ao piso; sua cobertura usa a quantidade real, área e tamanho da espécie. O custo não cresce linearmente com a população.

Transformações são enviadas a até 12,5 Hz, densidade a aproximadamente 3,3 Hz; pernas das formigas animam na GPU, com tempo ligado à simulação. Buffers de solo e densidade são reutilizados quando o tempo virtual e a câmera não mudam. Humanos usam passos proporcionais ao deslocamento, pés plantados no mundo, transferência de apoio e cinemática inversa 3D de pernas e braços. Viradas e mudanças de velocidade têm inércia, e decisões de trajeto duram cerca de um segundo. Dor e fôlego aparecem acima de cada humano, em cartões numerados com a mesma fonte bitmap, painéis e barras segmentadas da interface. Os cartões acompanham a câmera e se afastam quando necessário, mantendo uma linha até o dono; o CSV conserva as médias da população. A pisada escolhe o pé próximo do alvo sem girar o tronco a cada ação; a remoção de insetos usa uma mão na perna ou no peito, com a outra apoiada. Não há oscilação contínua dos dois braços. As poses são procedurais, não captura de movimento. A configuração fica num menu de pausa com quatro abas.

A camada de densidade é uma aproximação visual, não uma malha para cada formiga. O campo perde informação de microdistribuição; não há empilhamento 3D nem exclusão de volume entre milhões de insetos. A população e os contatos continuam sendo calculados no modelo agregado documentado em `MODEL.md`.

A defesa mantém o tronco mais ereto: a pisada levanta um pé e a remoção de formigas aproxima a canela da mão. A retirada tem uma animação fantasiosa: um par de asas de penas cresce nas costas, bate, eleva o humano acima da grade e o leva para fora da arena. O voo termina mesmo quando a última retirada encerra a rodada; durante uma rodada pausada, ele pausa também. Essa saída é visual e não altera os cálculos da simulação.

As mortes de formigas emitem pequenas partículas douradas e terracota por 0,6 s: no ponto do solo para pisadas e temperatura, ou no corpo para remoção de insetos. As pisadas esperam o pé baixar para emitir o efeito. A pausa congela as partículas e uma nova rodada limpa os efeitos. A fila guarda até 256 notificações de mortes e o desenho usa no máximo 128 efeitos / 512 partículas simultâneas, amostrando perdas em enxames grandes sem alterar a contagem de formigas ou a sequência aleatória do modelo.

## Verificação do projeto

Na raiz do repositório, com `godot` apontando para o executável 4.5.2:

```bash
godot --headless --editor --path godot --import
godot --headless --path godot --script res://tests/test_simulation.gd
godot --headless --path godot --script res://tests/test_ui.gd
godot --headless --path godot --script res://tests/test_animation.gd
godot --headless --path godot --script res://tests/test_feedback.gd
```

Os testes verificam conservação da população, limites, configuração individual, medidores por humano nas três câmeras e no celular, apoio dos pés, postura de defesa, retirada por voo e efeitos de morte (posição, pausa, duração e limite de partículas). Recursos gráficos e fontes já estão incluídos. A regeneração opcional da interface com `tools/make_game_ui.py` usa Python, Pillow e os arquivos DejaVu dos caminhos Linux indicados no script.

## Organização dos arquivos

O repositório contém o projeto editável, recursos, shaders, testes e ferramentas de exportação. Builds Web e executáveis são gerados em `dist/` e `native/`, respectivamente. Caches da engine e credenciais locais de exportação ficam fora do Git.
