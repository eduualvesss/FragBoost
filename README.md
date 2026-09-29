# FragBoost

Painel gráfico único (`.ps1`, sem `.bat`, sem instalador) pra otimização de Windows voltada a jogo. Junta numa janela só o que antes era um script por jogo: Valorant Otimizador, CPU Otimizador e RamBoost viraram abas do mesmo app.

Roda em PowerShell + WinForms, se auto-eleva como admin sozinho e guarda backup de cada chave de registro que mexe — dá pra reverter tudo.

## O que faz

**Biblioteca de jogos**, cada um com ajustes liga/desliga e checagem de status real (lê o registro, não confia em flag salva):

- Valorant, Roblox, Minecraft, CS2, GTA V, Warframe, DayZ
- Qualquer outro jogo: aba "Otimização Geral" deixa adicionar exe personalizado, ganha os mesmos tweaks universais

Ajustes universais aplicados por jogo:
- Desativar Game DVR / Game Mode / fullscreen exclusivo clássico
- MMCSS (prioridade de rede e CPU pra jogo em foreground)
- Exclusão da pasta do jogo no Defender
- Bloqueio de apps UWP em 2º plano
- Ultimate Performance (plano de energia)
- HAGS (GPU scheduling)
- Desativar Nagle em toda interface de rede ativa
- Prioridade alta de CPU via IFEO (pulado no Minecraft — `javaw.exe` é nome genérico de qualquer app Java, ligar isso afetaria mais coisa que o jogo)

**Aba CPU** (sistema, não depende de jogo):
- Desempenho Máximo (energia + core parking 100%)
- Win32PrioritySeparation pra foreground
- MMCSS sem reserva de CPU
- Power Throttling off + clock travado em 100%
- Desativar SysMain / DiagTrack / WSearch
- Limpeza de processos (mata processo solto, com lista de protegidos hardcoded pra não deixar matar `System`, `csrss`, `lsass` etc.)

**Aba RAM** (ações de uma vez, não é liga/desliga):
- Top 15 processos por consumo de RAM
- Limpar standby list (via `NtSetSystemInformation`) + working set trim de todo processo
- Matar processo de apoio do Discord/Spotify sem fechar o app
- Limpar temp, cache DNS, prefetch, thumbnail cache
- Reiniciar Explorer.exe
- Fechar Firefox/Discord/Spotify de vez (com confirmação, avisa que perde aba/mensagem não enviada)

## Como funciona por baixo

- **Auto-elevação:** detecta se não é admin, relança a si mesmo via `Start-Process -Verb RunAs` e esconde o console (`ShowWindow` via P/Invoke). Sem UAC manual, sem "executar como administrador" — clica duas vezes e pronto.
- **Execution Policy:** primeira vez que o script roda (via atalho ou bypass manual), libera `Bypass` pro usuário atual pra sempre. Isso não ajuda no primeiro download — arquivo baixado da internet cai bloqueado (`Restricted`) e nem chega a carregar; precisa rodar via atalho do próprio FragBoost ou `-ExecutionPolicy Bypass` na primeira vez.
- **Backup:** toda chave de registro mexida vira JSON em `<pasta_do_script>\<nome>_backup\` antes de aplicar. Jogo novo adicionado pelo usuário ganha `custom_backup\<slug-do-nome>`. Botão de reset lê o backup e devolve o valor original.
- **Detecção de jogo instalado:** Steam (lê `libraryfolders.vdf`, cobre biblioteca em outro disco), Epic, Riot, e fallback de path direto pra GTA V (Rockstar Launcher) e Roblox.
- **Config:** `config.json` do lado do script guarda jogo customizado adicionado pelo usuário, pra recarregar na próxima sessão.
- **Ícone:** embutido em base64 no próprio `.ps1`, grava `FragBoost.ico` do lado do script na primeira execução — não depende de arquivo externo solto.

## Rodando

Sem certificado de assinatura, então Windows/navegador vai reclamar no download (SmartScreen, Defender). Isso é esperado num script que mexe em registro e se autoeleva — não é vírus, mas ainda não tem reputação/assinatura. Duas formas de rodar:

1. Baixa o `.ps1`, roda `powershell -ExecutionPolicy Bypass -File FragBoost.ps1` — pede UAC uma vez, libera a policy pro seu usuário depois disso.
2. Usa o atalho gerado pelo próprio app (menu do app cria um sem precisar de UAC toda vez).

Requer PowerShell + .NET com WinForms (padrão em qualquer Windows 10/11).

## Estrutura do código

Arquivo único (~2760 linhas), organizado por região com comentário `# ----- NOME -----`:

```
CAMINHOS / POLÍTICA DE EXECUÇÃO / CONFIG
REGISTRO (Backup-Key, Set-Reg, Get-Reg — comum a tudo)
ATALHO SEM UAC / ADMIN / CONSOLE
LOCALIZAR JOGOS (Steam, Epic, Riot, fallbacks por jogo)
OTIMIZAÇÃO UNIVERSAL (Get-UniversalGameTweaks — motor compartilhado)
VISUAL (tema, cantos arredondados via GDI+, botões)
PAINEL "AJUSTES" (construtor reutilizável de aba de jogo)
ABAS: Valorant, Roblox, Minecraft, CS2, GTA V, Warframe, DayZ, CPU, RAM
BIBLIOTECA (jogo customizado adicionado pelo usuário)
JANELA PRINCIPAL (barra de categoria horizontal + grade de jogos)
```

Cada jogo pré-configurado é um bloco curto que chama `New-TweaksPanel` passando o resultado de `Get-UniversalGameTweaks` (Valorant é exceção, mantém lista própria idêntica à versão original standalone, pra não perder compatibilidade de backup de quem já usava). Jogo novo da biblioteca usa o motor universal direto.

## Próximos passos

Disco e outros otimizadores de sistema operacional entram como mais um item — a estrutura de aba + backup + reset já foi pensada pra isso.
