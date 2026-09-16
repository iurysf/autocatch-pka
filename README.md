# PokeAlliance AutoCatch + Auto Item Refresh

Módulos de AutoCatch e Auto Item Refresh para o cliente PokeAlliance no Windows.

> ⚠️ **Aviso de risco:** o uso de automações pode violar as regras do jogo e
> resultar em advertência, suspensão ou banimento da conta. Use este projeto
> somente se estiver ciente e disposto a assumir esses riscos. Os autores não
> se responsabilizam por contas banidas, suspensas, perdas de itens, personagens
> ou qualquer outra consequência decorrente do uso.

## Recursos

- Captura por ID do corpo do Pokémon.
- Cards ilimitados para configurar Ball e corpo.
- Seleção por arrastar ou pelos botões do painel.
- Auto Item Refresh com vários itens independentes.

## Requisitos

- Windows 10 ou superior.
- Cliente PokeAlliance instalado.
- Python 3 disponível no `PATH`.
- Jogo e launcher fechados durante a instalação.

## Instalação

### Preparação

1. Instale ou atualize o PokeAlliance pelo launcher oficial.
2. Feche completamente o jogo e o launcher.
3. Baixe o repositório pelo GitHub ou use `git clone`.
4. Extraia o pacote inteiro. A pasta precisa conter `modules/game_autocatch/`.

### Opção recomendada: pacote separado

1. Abra a pasta do pacote.
2. Execute `instalar_notebook.bat`.
3. Se o cliente não for encontrado automaticamente, informe a pasta que contém
   `PokeAlliance_gl.exe`.
4. Inicie o jogo pelo atalho **PokeAlliance AutoCatch**.

### Opção alternativa: mesma pasta do cliente

1. Copie todos os arquivos do pacote para a pasta do PokeAlliance.
2. Aceite a substituição dos arquivos existentes.
3. Confirme que `modules/game_autocatch/` está dentro da pasta do cliente.
4. Execute `instalar_notebook.bat` nessa mesma pasta.

Quando os módulos já estiverem nessa pasta, o instalador não os apaga nem tenta
copiar a pasta sobre ela mesma.

O instalador cria um backup do executável antes do primeiro patch. Depois da
instalação, abra o cliente pelo atalho personalizado; o launcher oficial pode
restaurar os arquivos originais.

Também é possível executar pelo terminal:

```powershell
python patch_notebook.py
```

Se o script solicitar o caminho do jogo, informe a pasta, e não o arquivo
`PokeAlliance_gl.exe` diretamente.

### Atualizações

Depois que o launcher atualizar o cliente, feche o launcher, substitua os
arquivos pelos da nova versão deste pacote e execute o instalador novamente.

## AutoCatch

1. Abra o painel **Auto Catch**.
2. Na aba **Captura**, clique em **+ Add novo Pokemon**.
3. Escolha a Ball e o corpo correspondente em cada card.
4. Ative o AutoCatch.

## Auto Item Refresh

1. Abra a aba **Auto Item**.
2. Clique em **+ Add novo Item**.
3. Arraste um item da mochila ou use **Selecionar Item**.
4. Ative o card do item.


O recurso usa o módulo `game_autocatch` junto com a API de buffs em
`modules/game_buffs/playerbuffs.lua`.

## Solução de problemas

### Python não encontrado

Instale o Python 3 e habilite a opção **Add Python to PATH**. Feche e abra o
terminal novamente antes de executar o instalador.

### Pasta do jogo não encontrada

O instalador precisa da pasta que contém `PokeAlliance_gl.exe`, não do caminho
do executável. Se a detecção automática falhar, informe essa pasta quando ela
for solicitada.

### Módulo AutoCatch não encontrado

Confirme que a origem contém:

```text
modules/game_autocatch/
```

Execute o instalador na pasta do pacote ou copie o pacote inteiro para a pasta
do cliente. Se o script estiver dentro do cliente e pedir a origem, informe a
pasta do pacote que contém `modules/game_autocatch/`.

### Build não suportado

O patcher aceita somente builds conhecidos do `PokeAlliance_gl.exe`. Atualize o
cliente pelo launcher oficial e use uma versão do pacote compatível. Não tente
alterar o executável manualmente.

### Arquivo em uso ou acesso negado

Feche o jogo, o launcher e todas as outras instâncias do cliente. Verifique
também se sua conta possui permissão de escrita na pasta da instalação.

### O atalho não foi criado

Execute o instalador novamente ou abra `PokeAlliance_gl.exe` diretamente na
pasta do cliente. O diretório de trabalho deve ser a própria pasta do jogo.

### O painel não aparece ou abre vazio

Abra o cliente pelo atalho personalizado e confirme se estes arquivos existem:

```text
modules/game_autocatch/autocatch.otmod
modules/game_autocatch/autocatch.lua
modules/game_autocatch/autocatch.otui
```

Depois de copiar ou substituir os arquivos, feche e abra o cliente novamente.

### O Auto Item Refresh não renova

Verifique se o card está ativo, se o item está na mochila e se o ícone do buff
aparece no cliente. O primeiro uso precisa ser confirmado pelo servidor para
associar o buff ao item. A renovação ocorre somente depois que todos os buffs
associados terminam.

## Estrutura

```text
autocatch-pka/
├─ instalar_notebook.bat
├─ patch_notebook.py
├─ README.md
└─ modules/
   ├─ game_autocatch/
   └─ game_buffs/
      └─ playerbuffs.lua
```

## Conteúdo

Este repositório não distribui o cliente oficial, executáveis, sprites, sons ou
dados de usuário. Use as modificações somente em instalações que você tenha
permissão para alterar.
