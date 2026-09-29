# ============================================================
#  FRAGBOOST - painel grafico multi-jogo
#  Suite unica de otimizacao: biblioteca de jogos (Valorant,
#  Roblox, jogos adicionados pelo usuario) + otimizadores de
#  sistema (CPU, RAM), tudo numa janela so, com auto-elevacao
#  UAC, console escondido e a mesma identidade visual das
#  versoes anteriores (Valorant Otimizador / CPU Otimizador /
#  RamBoost).
#
#  Continua um arquivo unico: sem .bat, pede UAC sozinho.
#
#  Cada jogo/sistema tem sua propria pasta de backup (nome
#  igual as versoes antigas onde ja existia: valorant_backup,
#  cpu_backup - assim quem ja tinha essas pastas de uma versao
#  anterior nao perde o backup). Jogo novo adicionado pelo
#  usuario ganha pasta "custom_backup\<slug-do-nome>".
#
#  ARQUITETURA:
#   - VALORANT: array de ajustes praticamente identico ao
#     valorant_otimizador.ps1 original (mesma logica, mesmas
#     chaves de registro) - so adaptado pra virar painel dentro
#     da janela em vez de janela propria.
#   - ROBLOX e JOGO PERSONALIZADO (biblioteca de jogos
#     adicionados pelo usuario): usam Get-UniversalGameTweaks,
#     a versao parametrizada do mesmo conjunto de ajustes -
#     "otimizacao universal" que qualquer executavel de jogo
#     pode receber (prioridade de CPU, Game DVR, HAGS, MMCSS,
#     exclusao no Defender, Nagle, energia).
#   - CPU: ajustes de sistema (nao depende de jogo nenhum),
#     copiado do Otimizador-de-CPU-GUI.ps1 original.
#   - RAM: ferramentas de acao unica (nao sao liga/desliga
#     persistente), adaptadas do RamBoost.ps1 original -
#     mesma logica, so trocando Write-Host por log na tela.
#
#  Proximos otimizadores planejados (disco, sistema
#  operacional, outros jogos): entram como mais um item na
#  lista $SidebarSistema ou como jogo novo na biblioteca -
#  a estrutura ja fica pronta pra isso.
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$ErrorActionPreference = "SilentlyContinue"

# ----------------------- CAMINHOS -----------------------
$ScriptPath = $PSCommandPath
if (-not $ScriptPath) { $ScriptPath = $MyInvocation.MyCommand.Path }
$ScriptDir = Split-Path -Parent $ScriptPath
$BackupRoot = $ScriptDir
$ConfigFile = Join-Path $ScriptDir "config.json"
$IconFile = Join-Path $ScriptDir "FragBoost.ico"

# ----------------------- POLITICA DE EXECUCAO (auto-fix, 1x por usuario) -----------------------
# Arquivo baixado da internet cai como bloqueado (Restricted) por padrao no
# Windows - nesse caso o .ps1 nem chega a carregar, entao isso so entra em
# vigor a partir da vez em que o script consegue rodar pela primeira vez
# (manualmente com -ExecutionPolicy Bypass, ou via atalho/tarefa agendada
# do proprio FragBoost, que ja usam Bypass). Dai em diante fica liberado
# pro usuario atual pra sempre - inclusive clique duplo direto, sem flag.
try {
    Unblock-File -Path $ScriptPath -ErrorAction SilentlyContinue
    if ((Get-ExecutionPolicy -Scope CurrentUser) -notin @("Bypass", "Unrestricted")) {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force -ErrorAction Stop
    }
}
catch {}

# ----------------------- CONFIG (persistido em config.json) -----------------------
# Schema: RiotDir (string), RobloxDir (string), CustomGames (lista de
# { Nome, ExeName, ExePath, Dir, Slug }).
# Compativel com o config.json antigo do Valorant Otimizador, que so
# tinha "RiotDir" - os campos novos entram com valor padrao se nao
# existirem ainda no arquivo.

function Load-Config {
    $cfg = [PSCustomObject]@{
        RiotDir        = "C:\Riot Games"
        RobloxDir      = (Join-Path $env:LOCALAPPDATA "Roblox")
        Cs2Dir         = $null
        GtaDir         = $null
        GtaExeName     = $null
        WarframeDir    = $null
        DayzDir        = $null
        MinecraftJavaw = $null
        CustomGames    = @()
    }
    if (Test-Path $ConfigFile) {
        try {
            $raw = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            if ($raw.RiotDir) { $cfg.RiotDir = $raw.RiotDir }
            if ($raw.RobloxDir) { $cfg.RobloxDir = $raw.RobloxDir }
            if ($raw.Cs2Dir) { $cfg.Cs2Dir = $raw.Cs2Dir }
            if ($raw.GtaDir) { $cfg.GtaDir = $raw.GtaDir }
            if ($raw.GtaExeName) { $cfg.GtaExeName = $raw.GtaExeName }
            if ($raw.WarframeDir) { $cfg.WarframeDir = $raw.WarframeDir }
            if ($raw.DayzDir) { $cfg.DayzDir = $raw.DayzDir }
            if ($raw.MinecraftJavaw) { $cfg.MinecraftJavaw = $raw.MinecraftJavaw }
            if ($raw.CustomGames) {
                $cfg.CustomGames = @($raw.CustomGames | ForEach-Object {
                        [PSCustomObject]@{
                            Nome    = $_.Nome
                            ExeName = $_.ExeName
                            ExePath = $_.ExePath
                            Dir     = $_.Dir
                            Slug    = $_.Slug
                        }
                    })
            }
        }
        catch {}
    }
    return $cfg
}

function Save-Config($cfg) {
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigFile -Encoding UTF8
}

function Get-GameSlug([string]$nome) {
    $slug = $nome.ToLower()
    $slug = ($slug -replace "[^a-z0-9]+", "_").Trim("_")
    if (-not $slug) { $slug = "jogo" }
    return $slug
}

# ----------------------- REGISTRO / BACKUP (comuns a todas as abas) -----------------------
# Mesmas funcoes usadas nos tres scripts originais - agora um lugar so.
# $subDir separa o backup de cada aba/jogo (valorant_backup, cpu_backup,
# roblox_backup, custom_backup\<slug>), pra nao misturar nem sobrescrever.

function Backup-Key([string]$path, [string]$name, [string]$subDir) {
    $dir = Join-Path $BackupRoot $subDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $file = Join-Path $dir "$name.reg"
    if (Test-Path $file) { return $true }
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    $regPath = $path.Replace("HKLM:\", "HKLM\").Replace("HKCU:\", "HKCU\")
    reg.exe export "$regPath" "$file" /y *> $null
    # reg.exe nao lanca excecao, so devolve exit code. Sem checar, falha calada
    return ($LASTEXITCODE -eq 0 -and (Test-Path $file))
}

function Set-Reg([string]$path, [string]$name, $value, [string]$type = "DWord") {
    # dono setado = Apply de uma aba. Guarda o original ANTES de mexer.
    # Nao conseguiu guardar? Nao escreve. Sem volta, sem mudanca.
    if ($global:FragOwner) {
        if (-not (Save-RegOriginal $path $name $global:FragOwner)) {
            $global:FragFalha = $true
            return
        }
    }
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
}

function Get-Reg([string]$path, [string]$name) {
    try { return (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name }
    catch { return $null }
}

function Remove-Reg([string]$path, [string]$name) {
    Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
}

function Get-Guid([string]$text) {
    if ($text -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") { return $Matches[1] }
    return $null
}

function Get-GuidAtivo {
    $raw = powercfg /getactivescheme | Out-String
    return Get-Guid $raw
}

function Save-PowerPlanOriginal([string]$owner) {
    $state = Load-State
    # grava o plano original UMA vez. Se o jogo B chegar depois do A, o plano
    # ativo ja e o Ultimate do A, entao nao pode sobrescrever.
    if (-not $state.PowerPlan) {
        $guid = Get-GuidAtivo
        if (-not $guid) { return }
        $state.PowerPlan = [PSCustomObject]@{ Guid = $guid; Owners = @() }
    }
    if (@($state.PowerPlan.Owners) -notcontains $owner) {
        $state.PowerPlan.Owners = @($state.PowerPlan.Owners) + $owner
    }
    Save-State $state | Out-Null
}

function Get-SavedPowerPlan([string]$subDir) {
    $file = Join-Path (Join-Path $BackupRoot $subDir) "power_plan_anterior.txt"
    if (Test-Path $file) { return (Get-Content $file).Trim() }
    return $null
}

# ----------------------- ESTADO GLOBAL (valor original + quem depende dele) -----------------------
# reg import nao apaga valor que nao existia antes, e o backup por jogo
# pega o valor que outro jogo ja tinha mexido. Aqui e um arquivo so:
# cada valor guarda o original UMA vez + lista de abas que usam ele.
# So restaura quando a ultima aba dona reverte.

$StateFile = Join-Path $BackupRoot "global_backup\state.json"
$global:FragOwner = $null    # aba que ta aplicando agora (Set-Reg le isso)
$global:FragFalha = $false   # true se nao deu pra guardar algum original

function Load-State {
    $s = [PSCustomObject]@{ Regs = @(); PowerPlan = $null }
    if (Test-Path $StateFile) {
        try {
            $raw = Get-Content $StateFile -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($raw.Regs) { $s.Regs = @($raw.Regs) }
            if ($raw.PowerPlan) { $s.PowerPlan = $raw.PowerPlan }
        }
        catch {
            # json quebrado: guarda copia, senao o proximo Save apaga os originais
            Copy-Item $StateFile "$StateFile.corrompido" -Force
        }
    }
    return $s
}

function Save-State($s) {
    try {
        $dir = Split-Path $StateFile
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
        # escreve em .tmp e move: queda no meio da escrita nao deixa json pela metade
        $tmp = "$StateFile.tmp"
        $s | ConvertTo-Json -Depth 6 | Set-Content -Path $tmp -Encoding UTF8 -ErrorAction Stop
        Move-Item -Path $tmp -Destination $StateFile -Force -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

function Save-RegOriginal([string]$path, [string]$name, [string]$owner) {
    $state = Load-State
    $id = "$path|$name"
    $rec = @($state.Regs) | Where-Object { $_.Id -eq $id } | Select-Object -First 1

    if (-not $rec) {
        $existed = $false; $kind = $null; $data = $null
        $key = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if ($key -and ($key.GetValueNames() -contains $name)) {
            $existed = $true
            $kind = $key.GetValueKind($name).ToString()
            # sem expandir %VAR%, senao restaura o valor ja expandido
            $data = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        $rec = [PSCustomObject]@{ Id = $id; Path = $path; Name = $name; Existed = $existed; Kind = $kind; Data = $data; Owners = @() }
        $state.Regs = @($state.Regs) + $rec
    }
    if (@($rec.Owners) -notcontains $owner) { $rec.Owners = @($rec.Owners) + $owner }
    return (Save-State $state)
}

function Restore-Owner([string]$owner) {
    $global:FragOwner = $null   # restaurar nao pode rastrear de novo
    $state = Load-State
    $mexeu = $false

    foreach ($rec in @($state.Regs)) {
        if (@($rec.Owners) -notcontains $owner) { continue }
        $mexeu = $true
        $rec.Owners = @($rec.Owners | Where-Object { $_ -ne $owner })
        # outra aba ainda depende desse valor: deixa como ta
        if (@($rec.Owners).Count -gt 0) { continue }

        if ($rec.Existed) {
            $data = $rec.Data
            if ($rec.Kind -eq "Binary") { $data = [byte[]]$data }
            if ($rec.Kind -eq "MultiString") { $data = [string[]]$data }
            Set-Reg $rec.Path $rec.Name $data $rec.Kind
        }
        else {
            Remove-Reg $rec.Path $rec.Name
        }
    }
    $state.Regs = @($state.Regs | Where-Object { @($_.Owners).Count -gt 0 })

    $pp = $state.PowerPlan
    if ($pp -and (@($pp.Owners) -contains $owner)) {
        $mexeu = $true
        $pp.Owners = @($pp.Owners | Where-Object { $_ -ne $owner })
        if (@($pp.Owners).Count -eq 0) {
            powercfg /setactive $pp.Guid *> $null
            # plano original pode ter sido apagado pelo usuario
            if ($LASTEXITCODE -ne 0) { powercfg /setactive SCHEME_BALANCED *> $null }
            $state.PowerPlan = $null
        }
    }

    Save-State $state | Out-Null
    return $mexeu
}

# ----------------------- ATALHO SEM UAC (app inteiro, um so pra tudo) -----------------------
# Antes cada otimizador (Valorant/CPU) criava sua propria tarefa
# agendada e atalho. Agora e um app so, entao vira uma tarefa e um
# atalho unicos - "FragBoost" - que abrem a suite inteira direto
# como administrador, sem UAC de novo.

$AtalhoTaskName = "FragBoost"

function Test-AtalhoInstalado {
    Import-Module ScheduledTasks -ErrorAction SilentlyContinue
    return [bool](Get-ScheduledTask -TaskName $AtalhoTaskName -ErrorAction SilentlyContinue)
}

function New-Atalho {
    Import-Module ScheduledTasks -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)

    Unregister-ScheduledTask -TaskName $AtalhoTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $AtalhoTaskName -Action $action -Principal $principal -Settings $settings | Out-Null

    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "FragBoost.lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:WINDIR "System32\schtasks.exe"
    $shortcut.Arguments = "/run /tn `"$AtalhoTaskName`""
    $shortcut.WorkingDirectory = $ScriptDir
    $shortcut.WindowStyle = 7
    $shortcut.IconLocation = if (Test-Path $IconFile) { $IconFile } else { (Join-Path $env:WINDIR "System32\shell32.dll") + ",13" }
    $shortcut.Description = "Abre o FragBoost direto como administrador"
    $shortcut.Save()
}

function Remove-Atalho {
    Import-Module ScheduledTasks -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $AtalhoTaskName -Confirm:$false -ErrorAction SilentlyContinue
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "FragBoost.lnk"
    if (Test-Path $shortcutPath) { Remove-Item $shortcutPath -Force }
}

# ----------------------- ADMIN / CONSOLE -----------------------

function Hide-Console {
    Add-Type -Name "ConsoleWindow" -Namespace "NativeMethods" -MemberDefinition '
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    '
    $h = [NativeMethods.ConsoleWindow]::GetConsoleWindow()
    if ($h -ne [IntPtr]::Zero) { [NativeMethods.ConsoleWindow]::ShowWindow($h, 0) | Out-Null }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
    try {
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$ScriptPath`"") `
            -Verb RunAs -ErrorAction Stop | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Precisa de permissao de administrador. Clique com o botao direito no arquivo e escolha 'Executar com PowerShell', e aceite o UAC.",
            "FragBoost") | Out-Null
    }
    exit
}

Hide-Console

$Cfg = Load-Config

# ----------------------- LOCALIZAR JOGOS -----------------------

$RelValorantExe = "VALORANT\live\ShooterGame\Binaries\Win64\VALORANT-Win64-Shipping.exe"

function Get-SteamLibraryPaths {
    # Acha a pasta base da Steam pelo registro (funciona tanto pra instalacao
    # de 32 quanto 64 bits) e depois le o libraryfolders.vdf pra pegar TODAS
    # as bibliotecas adicionais (outro HD/SSD) - sem isso, jogo instalado
    # fora do disco padrao nunca seria achado.
    $bases = @()
    foreach ($regPath in @(
            "HKCU:\Software\Valve\Steam",
            "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
            "HKLM:\SOFTWARE\Valve\Steam"
        )) {
        $v = Get-Reg $regPath "SteamPath"
        if (-not $v) { $v = Get-Reg $regPath "InstallPath" }
        if ($v -and (Test-Path $v)) { $bases += $v }
    }
    if ($bases.Count -eq 0) { $bases = @("C:\Program Files (x86)\Steam") }

    $libs = New-Object System.Collections.Generic.List[string]
    foreach ($base in ($bases | Select-Object -Unique)) {
        $libs.Add($base) | Out-Null
        $vdf = Join-Path $base "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            # VDF e so um KeyValues de texto - nao precisa de parser completo,
            # um regex pegando toda linha '"path"    "..."' resolve.
            $conteudo = Get-Content $vdf -Raw -ErrorAction SilentlyContinue
            if ($conteudo) {
                [regex]::Matches($conteudo, '"path"\s*"([^"]+)"') | ForEach-Object {
                    $p = $_.Groups[1].Value -replace '\\\\', '\'
                    if (Test-Path $p) { $libs.Add($p) | Out-Null }
                }
            }
        }
    }
    return ($libs | Select-Object -Unique)
}

function Find-SteamGameExe([string]$PastaJogo, [string]$ExeRelativo) {
    $exeNome = Split-Path -Leaf $ExeRelativo
    foreach ($lib in (Get-SteamLibraryPaths)) {
        $raiz = Join-Path $lib "steamapps\common\$PastaJogo"
        if (-not (Test-Path $raiz)) { continue }
        $candidato = Join-Path $raiz $ExeRelativo
        if (Test-Path $candidato) { return @{ ExePath = $candidato; GameDir = $raiz } }
        # Caminho relativo "de manual" pode ter mudado (jogo com patch que
        # reorganiza pasta, tipo o Warframe) - busca recursiva dentro da
        # pasta do jogo pelo nome do exe resolve sem precisar saber a
        # subpasta exata de antemao.
        $achado = Get-ChildItem -Path $raiz -Filter $exeNome -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($achado) { return @{ ExePath = $achado.FullName; GameDir = $raiz } }
    }
    return $null
}

# Epic Games Launcher guarda um .item (JSON) por jogo instalado em
# ProgramData\Epic\EpicGamesLauncher\Data\Manifests - sem padrao de nome de
# pasta (as vezes e so um UUID), entao a forma confiavel de achar um jogo
# especifico e ler todos os manifests e comparar o LaunchExecutable.
function Find-EpicGameByExe([string]$ExeNome) {
    $manifestsDir = "C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    if (-not (Test-Path $manifestsDir)) { return $null }
    foreach ($arq in (Get-ChildItem -Path $manifestsDir -Filter "*.item" -ErrorAction SilentlyContinue)) {
        try {
            $dados = Get-Content $arq.FullName -Raw | ConvertFrom-Json
            if ($dados.LaunchExecutable -and $dados.InstallLocation -and
                ([IO.Path]::GetFileName($dados.LaunchExecutable) -ieq $ExeNome)) {
                $exePath = Join-Path $dados.InstallLocation $dados.LaunchExecutable
                if (Test-Path $exePath) { return @{ ExePath = $exePath; GameDir = $dados.InstallLocation } }
            }
        }
        catch {}
    }
    return $null
}

# O cliente da Riot guarda o caminho real de instalacao de cada produto
# (VALORANT, LoL etc.) num YAML de metadata - mais confiavel que assumir
# "C:\Riot Games" fixo, principalmente pra quem instalou em outro disco.
# YAML simples (chave: valor), da pra ler so com regex, sem parser externo.
function Find-RiotProductRoot([string]$ProductSlug) {
    $yamlPath = "C:\ProgramData\Riot Games\Metadata\$ProductSlug\$ProductSlug.product_settings.yaml"
    if (-not (Test-Path $yamlPath)) { return $null }
    $conteudo = Get-Content $yamlPath -Raw -ErrorAction SilentlyContinue
    if (-not $conteudo) { return $null }
    $m = [regex]::Match($conteudo, 'product_install_root:\s*"?([^"\r\n]+)"?')
    if ($m.Success) {
        $caminho = $m.Groups[1].Value.Trim()
        if (Test-Path $caminho) { return $caminho }
    }
    return $null
}

function Find-RobloxExe([string]$baseDir) {
    if (-not $baseDir -or -not (Test-Path $baseDir)) { return $null }
    $versionsDir = Join-Path $baseDir "Versions"
    if (-not (Test-Path $versionsDir)) { return $null }
    $found = Get-ChildItem -Path $versionsDir -Filter "RobloxPlayerBeta.exe" -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Find-Cs2Exe {
    # Pasta continua se chamando "Counter-Strike Global Offensive" - a CS2
    # tomou conta do app da CS:GO na Steam, o nome da pasta nunca mudou.
    $r = Find-SteamGameExe "Counter-Strike Global Offensive" "game\bin\win64\cs2.exe"
    if ($r) { $r.ExeName = "cs2.exe" }
    return $r
}

function Find-GtaExe {
    # GTA V hoje e DOIS jogos separados na Steam: "Grand Theft Auto V" (a
    # Legacy, exe GTA5.exe) e "Grand Theft Auto V Enhanced" (exe
    # GTA5_Enhanced.exe) - tenta os dois. Se nao achar na Steam, cai pro
    # instalador padrao do Rockstar Games Launcher.
    $r = Find-SteamGameExe "Grand Theft Auto V Enhanced" "GTA5_Enhanced.exe"
    if ($r) { $r.ExeName = "GTA5_Enhanced.exe"; return $r }

    $r = Find-SteamGameExe "Grand Theft Auto V" "GTA5.exe"
    if ($r) { $r.ExeName = "GTA5.exe"; return $r }

    $r = Find-EpicGameByExe "GTA5.exe"
    if ($r) { $r.ExeName = "GTA5.exe"; return $r }

    $rockstarReg = Get-Reg "HKLM:\SOFTWARE\WOW6432Node\Rockstar Games\Grand Theft Auto V" "InstallFolder"
    if ($rockstarReg) {
        $tentativa = Join-Path $rockstarReg "GTA5.exe"
        if (Test-Path $tentativa) { return @{ ExePath = $tentativa; GameDir = $rockstarReg; ExeName = "GTA5.exe" } }
    }
    $padraoRockstar = "C:\Program Files\Rockstar Games\Grand Theft Auto V"
    $tentativa = Join-Path $padraoRockstar "GTA5.exe"
    if (Test-Path $tentativa) { return @{ ExePath = $tentativa; GameDir = $padraoRockstar; ExeName = "GTA5.exe" } }

    return $null
}

function Find-WarframeExe {
    # Steam guarda em steamapps\common\Warframe\Downloaded\Public\. A versao
    # standalone (launcher proprio, sem Steam) instala em Program Files ou
    # LocalAppData com a MESMA estrutura interna Downloaded\Public - so muda
    # a raiz.
    $r = Find-SteamGameExe "Warframe" "Downloaded\Public\Warframe.x64.exe"
    if ($r) { $r.ExeName = "Warframe.x64.exe"; return $r }

    foreach ($raiz in @(
            (Join-Path ${env:ProgramFiles(x86)} "Warframe"),
            (Join-Path $env:ProgramFiles "Warframe"),
            (Join-Path $env:LOCALAPPDATA "Warframe")
        )) {
        if (-not $raiz) { continue }
        $tentativa = Join-Path $raiz "Downloaded\Public\Warframe.x64.exe"
        if (Test-Path $tentativa) { return @{ ExePath = $tentativa; GameDir = $raiz; ExeName = "Warframe.x64.exe" } }
    }
    return $null
}

function Find-DayzExe {
    $r = Find-SteamGameExe "DayZ" "DayZ_x64.exe"
    if ($r) { $r.ExeName = "DayZ_x64.exe" }
    return $r
}

function Find-MinecraftJavaw([string]$MinecraftDir) {
    # O launcher oficial baixa o proprio Java dentro de
    # .minecraft\runtime\<nome-do-runtime>\windows-x64\<...>\bin\javaw.exe -
    # o nome do runtime muda de versao pra versao (java-runtime-gamma,
    # -delta etc.), entao busca recursiva e o unico jeito confiavel de achar
    # sem hardcodar uma versao que fica velha rapido. Limitado a pasta
    # "runtime" pra nao vasculhar o .minecraft inteiro (mundo salvo, mods
    # etc. - lento e sem necessidade).
    $runtimeDir = Join-Path $MinecraftDir "runtime"
    if (-not (Test-Path $runtimeDir)) { return $null }
    $achado = Get-ChildItem -Path $runtimeDir -Filter "javaw.exe" -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
    if ($achado) { return $achado.FullName }
    return $null
}

# ----------------------- LISTA COMPARTILHADA: PROCESSOS "PESO MORTO" -----------------------
# Usada pelo "BOOST AGORA" de qualquer jogo (Valorant, Roblox, jogo
# personalizado). Discord (e variantes Canary/PTB) ficam de fora de
# proposito - fechar isso derrubaria call de voz com os amigos no meio
# do jogo, o oposto do que o boost devia fazer.

$BG_HOGS = @(
    "Spotify",
    "chrome", "msedge", "firefox", "opera", "brave",
    "EpicGamesLauncher", "EAApp", "Origin", "Battle.net",
    "Steam", "OneDrive", "Dropbox", "Teams", "Slack", "skype"
)

# IFEO e indexado por NOME de exe. Nome generico = prioridade alta pra
# todo programa da maquina que usa esse nome.
$IFEO_BLOCKLIST = @(
    "java.exe", "javaw.exe", "python.exe", "pythonw.exe", "node.exe", "dotnet.exe",
    "chrome.exe", "msedge.exe", "firefox.exe", "explorer.exe", "cmd.exe",
    "powershell.exe", "pwsh.exe", "launcher.exe", "game.exe", "start.exe",
    "setup.exe", "install.exe", "steam.exe", "electron.exe"
)   

$ULTIMATE_GUID = "e9a42b02-d5df-448d-aa00-03f14749eb61"

# Chaves de registro globais usadas pela otimizacao universal de jogos
# (nao mudam de jogo pra jogo - so o IFEO e a exclusao no Defender sao
# por executavel/pasta).
$G_MMCSS_KEY = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
$G_GAMES_KEY = "$G_MMCSS_KEY\Tasks\Games"
$G_GFXDRV_KEY = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
$G_LAYERS_KEY = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
$G_GAMECFG_KEY = "HKCU:\System\GameConfigStore"
$G_GAMEDVR_KEY = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
$G_BGAPPS_KEY = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
$G_GAMEBAR_KEY = "HKCU:\Software\Microsoft\GameBar"

# ----------------------- OTIMIZACAO UNIVERSAL (qualquer jogo) -----------------------
# Mesmo conjunto de ajustes do Valorant Otimizador original, so que
# parametrizado: recebe o executavel/pasta de UM jogo e devolve os
# ajustes prontos pra ele. Roblox e qualquer jogo que o usuario
# adicionar na biblioteca usam esta mesma funcao - "otimizacoes
# universais" de verdade, um lugar so pra manter.
#
# Cada StatusCheck/Apply usa .GetNewClosure() de proposito: como esta
# dentro de uma funcao com parametro, sem isso o script perderia a
# referencia a $ExeName/$ExePath/$GameDir/$BackupSub assim que a
# funcao retornasse (mesmo motivo do .GetNewClosure() ja usado em
# New-DragHandler nas versoes antigas).

function Test-PastaExclusaoSegura([string]$dir) {
    if (-not $dir -or -not (Test-Path $dir)) { return $false }
    $full = [IO.Path]::GetFullPath($dir).TrimEnd("\")
    # raiz de disco ("C:") tem 2 chars
    if ($full.Length -le 3) { return $false }
    # so bloqueia a pasta exata. Subpasta do Downloads e ok, o Downloads em si nao.
    $largas = @(
        [Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("MyDocuments"),
        (Join-Path $env:USERPROFILE "Downloads"), $env:USERPROFILE, $env:TEMP,
        $env:LOCALAPPDATA, $env:APPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)},
        $env:WINDIR, "C:\Users", "C:\ProgramData"
    ) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd("\") }
    foreach ($p in $largas) { if ($full -ieq $p) { return $false } }
    return $true
}

function Get-UniversalGameTweaks {
    param(
        [string]$ExeName,
        [string]$ExePath,
        [string]$GameDir,
        [string]$BackupSub,
        # javaw.exe (Minecraft oficial) e generico - qualquer app Java usa
        # esse mesmo nome. IFEO e indexado por NOME do executavel, nao pelo
        # caminho, entao ligar prioridade alta pra "javaw.exe" afetaria
        # QUALQUER programa Java na maquina, nao so o Minecraft. Por isso
        # esse ajuste some da lista quando o motor e chamado pro Minecraft.
        [switch]$SkipCpuPriority
    )

    if ($IFEO_BLOCKLIST -contains "$ExeName".ToLower()) { $SkipCpuPriority = $true }

    $ifeoKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$ExeName\PerfOptions"

    $tweaksBase = @(
        @{ Label        = "Desativar Game DVR"
            StatusCheck = { (Get-Reg $G_GAMECFG_KEY "GameDVR_Enabled") -eq 0 }.GetNewClosure()
            Apply       = {
                Backup-Key $G_GAMECFG_KEY "gameconfigstore" $BackupSub
                Backup-Key $G_GAMEDVR_KEY "gamedvr" $BackupSub
                Set-Reg $G_GAMECFG_KEY "GameDVR_Enabled" 0
                Set-Reg $G_GAMEDVR_KEY "AppCaptureEnabled" 0
            }.GetNewClosure()
        },
        @{ Label        = "Ativar Game Mode"
            StatusCheck = { (Get-Reg $G_GAMEBAR_KEY "AutoGameModeEnabled") -eq 1 }.GetNewClosure()
            Apply       = {
                Set-Reg $G_GAMEBAR_KEY "AllowAutoGameMode" 1
                Set-Reg $G_GAMEBAR_KEY "AutoGameModeEnabled" 1
            }.GetNewClosure()
        },
        @{ Label        = "Fullscreen exclusivo classico"
            StatusCheck = { (Get-Reg $G_GAMECFG_KEY "GameDVR_FSEBehaviorMode") -eq 2 }.GetNewClosure()
            Apply       = {
                Backup-Key $G_GAMECFG_KEY "gameconfigstore" $BackupSub
                Backup-Key $G_LAYERS_KEY "layers" $BackupSub
                Set-Reg $G_GAMECFG_KEY "GameDVR_FSEBehaviorMode" 2
                Set-Reg $G_GAMECFG_KEY "GameDVR_HonorUserFSEBehaviorMode" 1
                Set-Reg $G_GAMECFG_KEY "GameDVR_DXGIHonorFSEWindowsCompatible" 1
                if (Test-Path $ExePath) {
                    Set-Reg $G_LAYERS_KEY $ExePath "~ DISABLEDXMAXIMIZEDWINDOWEDMODE" "String"
                }
            }.GetNewClosure()
        },
        @{ Label        = "Ajustar MMCSS (rede/CPU p/ jogos)"
            StatusCheck = { (Get-Reg $G_MMCSS_KEY "SystemResponsiveness") -eq 0 }.GetNewClosure()
            Apply       = {
                Backup-Key $G_MMCSS_KEY "systemprofile" $BackupSub
                Set-Reg $G_MMCSS_KEY "NetworkThrottlingIndex" 0xffffffff
                Set-Reg $G_MMCSS_KEY "SystemResponsiveness" 0
                Set-Reg $G_GAMES_KEY "GPU Priority" 8
                Set-Reg $G_GAMES_KEY "Priority" 6
                Set-Reg $G_GAMES_KEY "Scheduling Category" "High" "String"
                Set-Reg $G_GAMES_KEY "SFIO Priority" "High" "String"
            }.GetNewClosure()
        },
        @{ Label        = "Excluir pasta do jogo do Defender"
            StatusCheck = { (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath -contains $GameDir }.GetNewClosure()
            Apply       = {
                if (-not (Test-PastaExclusaoSegura $GameDir)) {
                    [System.Windows.Forms.MessageBox]::Show("Pasta ampla demais pra excluir do Defender:`n$GameDir`nMove o jogo pra uma pasta so dele.", "FragBoost") | Out-Null
                    return
                }
                try { Add-MpPreference -ExclusionPath $GameDir -ErrorAction Stop } catch {}
            }.GetNewClosure()
        },
        @{ Label        = "Bloquear apps UWP em 2o plano"
            StatusCheck = { (Get-Reg $G_BGAPPS_KEY "GlobalUserDisabled") -eq 1 }.GetNewClosure()
            Apply       = {
                Backup-Key $G_BGAPPS_KEY "bgapps" $BackupSub
                Set-Reg $G_BGAPPS_KEY "GlobalUserDisabled" 1
            }.GetNewClosure()
        },
        @{ Label        = "Ultimate Performance (energia)"
            StatusCheck = { (powercfg /getactivescheme | Out-String) -match "Ultimate Performance" }.GetNewClosure()
            Apply       = {
                Save-PowerPlanOriginal $BackupSub
                $dupTxt = powercfg /duplicatescheme $ULTIMATE_GUID | Out-String
                $novoGuid = Get-Guid $dupTxt
                if ($novoGuid) { powercfg /setactive $novoGuid }
            }.GetNewClosure()
        },
        @{ Label        = "GPU Scheduling (HAGS)"
            StatusCheck = { (Get-Reg $G_GFXDRV_KEY "HwSchMode") -eq 2 }.GetNewClosure()
            Apply       = {
                Backup-Key $G_GFXDRV_KEY "graphicsdrivers" $BackupSub
                Set-Reg $G_GFXDRV_KEY "HwSchMode" 2
            }.GetNewClosure()
        },
        @{ Label        = "Desativar Nagle (rede)"
            StatusCheck = {
                $r = $false
                Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
                    $p = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($_.InterfaceGuid)"
                    if ((Get-Reg $p "TcpAckFrequency") -eq 1) { $r = $true }
                }
                $r
            }.GetNewClosure()
            Apply       = {
                Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
                    $guid = $_.InterfaceGuid
                    $ifPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
                    if (Test-Path $ifPath) {
                        Backup-Key $ifPath "nagle_$guid" $BackupSub
                        Set-Reg $ifPath "TcpAckFrequency" 1
                        Set-Reg $ifPath "TCPNoDelay" 1
                    }
                }
            }.GetNewClosure()
        }
    )

    if ($SkipCpuPriority) { return $tweaksBase }

    $cpuTweak = @{ Label = "Prioridade alta de CPU ($ExeName)"
        StatusCheck      = { (Get-Reg $ifeoKey "CpuPriorityClass") -eq 3 }.GetNewClosure()
        Apply            = {
            Backup-Key $ifeoKey "ifeo" $BackupSub
            Set-Reg $ifeoKey "CpuPriorityClass" 3
        }.GetNewClosure()
    }
    # Reinsere na posicao original (depois do MMCSS, antes da exclusao no
    # Defender) so pra manter a ordem da lista igual a de antes.
    return @($tweaksBase[0..3]) + $cpuTweak + @($tweaksBase[4..($tweaksBase.Count - 1)])
}

function Reset-UniversalGameDefaults {
    param(
        [string]$ExeName, [string]$ExePath, [string]$GameDir, [string]$BackupSub,
        [switch]$SkipCpuPriority
    )

    if ($IFEO_BLOCKLIST -contains "$ExeName".ToLower()) { $SkipCpuPriority = $true }

    # Defender e por pasta (nao e global), sai sempre
    try { Remove-MpPreference -ExclusionPath $GameDir -ErrorAction Stop } catch {}
    # tem original guardado: usa ele e nao chuta padrao
    if (Restore-Owner $BackupSub) { return }
    # daqui pra baixo: legado (aba que nunca passou pelo estado novo)

    $ifeoKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$ExeName\PerfOptions"

    Set-Reg $G_GAMECFG_KEY "GameDVR_Enabled" 1
    Remove-Reg $G_GAMECFG_KEY "GameDVR_FSEBehaviorMode"
    Remove-Reg $G_GAMECFG_KEY "GameDVR_HonorUserFSEBehaviorMode"
    Remove-Reg $G_GAMECFG_KEY "GameDVR_DXGIHonorFSEWindowsCompatible"
    Set-Reg $G_GAMEDVR_KEY "AppCaptureEnabled" 1
    if (Test-Path $ExePath) { Remove-Reg $G_LAYERS_KEY $ExePath }

    Set-Reg $G_MMCSS_KEY "NetworkThrottlingIndex" 10
    Set-Reg $G_MMCSS_KEY "SystemResponsiveness" 20
    Set-Reg $G_GAMES_KEY "Priority" 2
    Set-Reg $G_GAMES_KEY "Scheduling Category" "Medium" "String"
    Set-Reg $G_GAMES_KEY "SFIO Priority" "Normal" "String"

    if (-not $SkipCpuPriority) { Remove-Item -Path $ifeoKey -Recurse -ErrorAction SilentlyContinue }
    Remove-Reg $G_GFXDRV_KEY "HwSchMode"

    try { Remove-MpPreference -ExclusionPath $GameDir -ErrorAction Stop } catch {}

    Set-Reg $G_BGAPPS_KEY "GlobalUserDisabled" 0

    $guidSalvo = Get-SavedPowerPlan $BackupSub
    if ($guidSalvo) { powercfg /setactive $guidSalvo } else { powercfg /setactive SCHEME_BALANCED }

    Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $ifPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($_.InterfaceGuid)"
        Remove-Reg $ifPath "TcpAckFrequency"
        Remove-Reg $ifPath "TCPNoDelay"
    }
}

# ----------------------- VISUAL (tema compartilhado) -----------------------
# Mesma paleta/tipografia das versoes anteriores - identidade unica
# pra suite inteira.

$formWidth = 900
$formHeight = 640
$titleBarH = 30
$catBarH = 44
$contentWidth = $formWidth
$contentHeight = $formHeight - $titleBarH - $catBarH

$colorBg = [System.Drawing.Color]::FromArgb(255, 8, 8, 10)
$colorPanel = [System.Drawing.Color]::FromArgb(255, 18, 18, 21)
$colorCard = [System.Drawing.Color]::FromArgb(255, 22, 22, 26)
$colorAccent = [System.Drawing.Color]::FromArgb(255, 255, 70, 85)
$colorText = [System.Drawing.Color]::WhiteSmoke
$colorMuted = [System.Drawing.Color]::FromArgb(255, 150, 150, 155)
$colorOk = [System.Drawing.Color]::FromArgb(255, 90, 220, 130)
$colorSideSel = [System.Drawing.Color]::FromArgb(255, 38, 38, 46)
$colorBorder = [System.Drawing.Color]::FromArgb(255, 58, 58, 66)

$btnRadius = 6
$cardRadius = 8
$winRadius = 10

# Segoe UI Variable Text e a fonte nativa do Windows 11 - letras mais
# arredondadas e "macias" que a Segoe UI classica, sem precisar embutir
# arquivo de fonte nenhum (zero peso extra, zero licenca pra gerenciar).
# Se a fonte nao existir (Windows 10 sem update, por exemplo),
# InstalledFontCollection nao acha ela e cai pra "Segoe UI" sozinho.
function Get-SafeFontFamily {
    $prefer = "Segoe UI Variable Text"
    try {
        $coll = New-Object System.Drawing.Text.InstalledFontCollection
        if ($coll.Families.Name -contains $prefer) { return $prefer }
    }
    catch {}
    return "Segoe UI"
}
$fontFamilyName = Get-SafeFontFamily

$fontTitle = New-Object System.Drawing.Font($fontFamilyName, 16, [System.Drawing.FontStyle]::Bold)
$fontBtn = New-Object System.Drawing.Font($fontFamilyName, 9, [System.Drawing.FontStyle]::Bold)
$fontItem = New-Object System.Drawing.Font($fontFamilyName, 9)
$fontSmall = New-Object System.Drawing.Font($fontFamilyName, 8)
$fontMono = New-Object System.Drawing.Font("Consolas", 9)
$fontTileMono = New-Object System.Drawing.Font($fontFamilyName, 11, [System.Drawing.FontStyle]::Bold)

# ----------------------- CANTOS ARREDONDADOS (GDI+, anti-serrilhado) -----------------------
# WinForms nao tem "border-radius" pronto. Region sozinho (so recortar o
# controle num retangulo arredondado) fica serrilhado, sem anti-alias. Por
# isso todo elemento arredondado daqui pra frente e desenhado a mao no
# evento Paint (SmoothingMode AntiAlias) por cima de um preenchimento que
# "encaixa" na cor real do fundo do pai - assim o canto cortado nao deixa
# quina visivel.

function New-RoundedPath([int]$w, [int]$h, [int]$r) {
    $r2 = $r * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $r2, $r2, 180, 90)
    $path.AddArc(($w - $r2 - 1), 0, $r2, $r2, 270, 90)
    $path.AddArc(($w - $r2 - 1), ($h - $r2 - 1), $r2, $r2, 0, 90)
    $path.AddArc(0, ($h - $r2 - 1), $r2, $r2, 90, 90)
    $path.CloseFigure()
    return $path
}

# Painel "cartao" liso (substitui o GroupBox nativo, que desenha uma borda
# do jeito antigo do Windows). Cor de fundo entra arredondada, sem borda -
# so contraste de tom contra a pagina, mais moderno.
function New-CardPanel([int]$x, [int]$y, [int]$w, [int]$h, [System.Drawing.Color]$ParentBg, [System.Drawing.Color]$Fill) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.Size = New-Object System.Drawing.Size($w, $h)
    $p.BackColor = $ParentBg
    $p.Add_Paint({
            param($s, $e)
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $path = New-RoundedPath $s.Width $s.Height $cardRadius
            $brush = New-Object System.Drawing.SolidBrush($Fill)
            $e.Graphics.FillPath($brush, $path)
            $brush.Dispose(); $path.Dispose()
        }.GetNewClosure())
    return $p
}

# Arredonda a silhueta inteira de uma janela borderless (Region corta o
# formato; o contorno fino por cima e desenhado com anti-alias pra nao
# sobrar serrilhado na borda, que e o unico ponto onde Region sozinho fica
# feio). Os botoes de fechar/minimizar da barra de titulo continuam
# quadrados de proposito - e assim que o proprio Windows 11 desenha janela
# arredondada com botao de titulo reto, entao segue o padrao real do SO.
function Set-RoundedForm([System.Windows.Forms.Form]$f, [int]$radius) {
    $f.Add_Load({
            $path = New-RoundedPath $this.Width $this.Height $radius
            $this.Region = New-Object System.Drawing.Region($path)
            $path.Dispose()
        }.GetNewClosure())
    $f.Add_Paint({
            param($s, $e)
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $path = New-RoundedPath $s.Width $s.Height $radius
            $pen = New-Object System.Drawing.Pen($colorBorder, 1)
            $e.Graphics.DrawPath($pen, $path)
            $pen.Dispose(); $path.Dispose()
        }.GetNewClosure())
}

Add-Type -Name "WindowDrag" -Namespace "NativeMethods" -MemberDefinition '
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
'

function New-DragHandler([System.Windows.Forms.Form]$targetForm) {
    $sb = {
        [NativeMethods.WindowDrag]::ReleaseCapture() | Out-Null
        [NativeMethods.WindowDrag]::SendMessage($targetForm.Handle, 0xA1, 0x2, 0) | Out-Null
    }
    return $sb.GetNewClosure()
}

# Botao Flat + Paint customizado: o WinForms JA desenha o Text do botao
# antes de disparar o evento Paint. Se o handler desenhar o texto de novo,
# sai texto duplicado/borrado. Por isso todo handler comeca limpando a
# superficie com a cor de fundo (apaga o texto nativo) e desenha o
# rotulo uma unica vez, com quebra de linha e reticencias se nao couber.
function Clear-ButtonSurface($btn, $g) {
    $br = New-Object System.Drawing.SolidBrush($btn.BackColor)
    $g.FillRectangle($br, 0, 0, $btn.Width, $btn.Height)
    $br.Dispose()
}

function Write-ButtonLabel($btn, $g, [System.Drawing.Color]$color) {
    $F = [System.Windows.Forms.TextFormatFlags]
    $flags = $F::VerticalCenter -bor $F::WordBreak -bor $F::EndEllipsis -bor $F::NoPrefix
    $pad = 6
    if ($btn.TextAlign.ToString() -like "*Left") {
        $flags = $flags -bor $F::Left
        $pad = 14
    }
    else {
        $flags = $flags -bor $F::HorizontalCenter
    }
    $rect = New-Object System.Drawing.Rectangle($pad, 0, ($btn.Width - 2 * $pad), $btn.Height)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $btn.Text, $btn.Font, $rect, $color, $flags)
}

function New-ActionButton([string]$text, [int]$y, [int]$width = 150, [System.Drawing.Color]$ParentBg = $colorCard) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Font = $fontBtn
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $ParentBg
    $b.FlatAppearance.MouseOverBackColor = $ParentBg
    $b.FlatAppearance.MouseDownBackColor = $ParentBg
    $b.ForeColor = $colorText
    $b.Location = New-Object System.Drawing.Point(15, $y)
    $b.Size = New-Object System.Drawing.Size($width, 36)
    $b.Add_Paint({
            param($s, $e)
            Clear-ButtonSurface $s $e.Graphics
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $path = New-RoundedPath $s.Width $s.Height $btnRadius
            $pen = New-Object System.Drawing.Pen($colorAccent, 1)
            $e.Graphics.DrawPath($pen, $path)
            Write-ButtonLabel $s $e.Graphics $s.ForeColor
            $pen.Dispose(); $path.Dispose()
        })
    return $b
}

# ----------------------- CONSTRUTOR DE PAINEL "AJUSTES" (reutilizavel) -----------------------
# Usado por VALORANT, ROBLOX, CPU, OTIMIZACAO GERAL e cada jogo que o
# usuario adicionar na biblioteca - um layout so (acoes rapidas +
# checklist de ajustes + status + reverter) em vez de reescrever o
# WinForms cinco vezes.
#
# IMPORTANTE: como esta funcao roda de novo pra cada aba, todo
# scriptblock criado aqui dentro que so vai ser executado depois (clique
# de botao) usa .GetNewClosure() - senao perde a referencia a $Tweaks/
# $BackupSubDir assim que a funcao retornar.

function New-TweaksPanel {
    param(
        [int]$Width,
        [int]$Height,
        [array]$Tweaks,
        [array]$QuickActions,
        [scriptblock]$InfoLines,
        [string]$BackupSubDir,
        [scriptblock]$ResetDefaults,
        [string]$HeaderText,
        [bool]$ShowBackToGames = $true
    )

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($Width, $Height)
    $panel.BackColor = $colorBg

    $header = New-Object System.Windows.Forms.Label
    $header.Text = $HeaderText
    $header.Font = $fontTitle
    $header.ForeColor = $colorAccent
    $header.Location = New-Object System.Drawing.Point(0, 4)
    $header.Size = New-Object System.Drawing.Size($Width, 30)
    $header.TextAlign = "MiddleLeft"
    $header.Padding = New-Object System.Windows.Forms.Padding(15, 0, 0, 0)
    $panel.Controls.Add($header)

    if ($ShowBackToGames) {
        $lnkVoltar = New-Object System.Windows.Forms.LinkLabel
        $lnkVoltar.Text = "< JOGOS"
        $lnkVoltar.Font = $fontSmall
        $lnkVoltar.LinkColor = $colorMuted
        $lnkVoltar.ActiveLinkColor = $colorAccent
        $lnkVoltar.Location = New-Object System.Drawing.Point(($Width - 80), 12)
        $lnkVoltar.Size = New-Object System.Drawing.Size(70, 16)
        $lnkVoltar.TextAlign = "MiddleRight"
        $lnkVoltar.Add_Click({ Show-Tab "JOGOSGRID" })
        $panel.Controls.Add($lnkVoltar)
    }

    $leftW = 180
    $gbLeft = New-CardPanel 15 40 $leftW ($Height - 55) $colorBg $colorCard
    $panel.Controls.Add($gbLeft)

    $lblLeftHead = New-Object System.Windows.Forms.Label
    $lblLeftHead.Text = "ACOES RAPIDAS"
    $lblLeftHead.ForeColor = $colorMuted
    $lblLeftHead.Font = $fontBtn
    $lblLeftHead.Location = New-Object System.Drawing.Point(15, 10)
    $lblLeftHead.Size = New-Object System.Drawing.Size(($leftW - 24), 16)
    $gbLeft.Controls.Add($lblLeftHead)

    $y = 34
    foreach ($qa in $QuickActions) {
        $b = New-ActionButton $qa.Text $y 150 $colorCard
        $b.Add_Click($qa.OnClick)
        $gbLeft.Controls.Add($b)
        $y += 44
    }

    $btnStatus = New-ActionButton "STATUS" $y 150 $colorCard
    $gbLeft.Controls.Add($btnStatus)
    $y += 44

    $btnRevert = New-ActionButton "REVERTER" $y 150 $colorCard
    $gbLeft.Controls.Add($btnRevert)
    $y += 52

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Font = $fontSmall
    $lblInfo.ForeColor = $colorMuted
    $lblInfo.Location = New-Object System.Drawing.Point(15, $y)
    $lblInfo.Size = New-Object System.Drawing.Size(150, ($Height - 55 - $y - 10))
    $gbLeft.Controls.Add($lblInfo)

    $refreshInfo = {
        $linhas = & $InfoLines
        $lblInfo.Text = ($linhas -join "`n")
    }.GetNewClosure()
    & $refreshInfo

    $rightX = 15 + $leftW + 15
    $rightW = $Width - $rightX - 15
    $gbRight = New-CardPanel $rightX 40 $rightW ($Height - 55) $colorBg $colorCard
    $panel.Controls.Add($gbRight)

    $lblRightHead = New-Object System.Windows.Forms.Label
    $lblRightHead.Text = "AJUSTES"
    $lblRightHead.ForeColor = $colorMuted
    $lblRightHead.Font = $fontBtn
    $lblRightHead.Location = New-Object System.Drawing.Point(15, 10)
    $lblRightHead.Size = New-Object System.Drawing.Size(($rightW - 24), 16)
    $gbRight.Controls.Add($lblRightHead)

    $listH = $gbRight.Height - 80
    $listPanel = New-Object System.Windows.Forms.Panel
    $listPanel.Location = New-Object System.Drawing.Point(10, 32)
    $listPanel.Size = New-Object System.Drawing.Size(($rightW - 20), $listH)
    $listPanel.AutoScroll = $true
    $listPanel.BackColor = $colorCard
    $gbRight.Controls.Add($listPanel)

    $ty = 6
    foreach ($t in $Tweaks) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $t.Label
        $cb.Font = $fontItem
        $cb.ForeColor = $colorText
        $cb.Location = New-Object System.Drawing.Point(6, $ty)
        $cb.Size = New-Object System.Drawing.Size(($rightW - 50), 34)
        $cb.Checked = [bool](& $t.StatusCheck)
        $listPanel.Controls.Add($cb)
        $t.Control = $cb
        $ty += 38
    }

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = "APLICAR SELECIONADOS"
    $btnApply.Font = $fontBtn
    $btnApply.FlatStyle = "Flat"
    $btnApply.FlatAppearance.BorderSize = 0
    $btnApply.BackColor = $colorCard
    $btnApply.ForeColor = [System.Drawing.Color]::White
    $btnApply.Location = New-Object System.Drawing.Point(10, ($gbRight.Height - 42))
    $btnApply.Size = New-Object System.Drawing.Size(($rightW - 20), 36)
    $btnApply.Add_Paint({
            param($s, $e)
            Clear-ButtonSurface $s $e.Graphics
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $path = New-RoundedPath $s.Width $s.Height $btnRadius
            $brush = New-Object System.Drawing.SolidBrush($colorAccent)
            $e.Graphics.FillPath($brush, $path)
            Write-ButtonLabel $s $e.Graphics $s.ForeColor
            $brush.Dispose(); $path.Dispose()
        })
    $gbRight.Controls.Add($btnApply)

    $btnApply.Add_Click({
            $any = $false
            $global:FragOwner = $BackupSubDir
            $global:FragFalha = $false
            try {
                foreach ($t in $Tweaks) {
                    if ($t.Control.Checked) { & $t.Apply; $any = $true }
                }
            }
            finally {
                $global:FragOwner = $null
            }
            if ($global:FragFalha) {
                [System.Windows.Forms.MessageBox]::Show("Nao deu pra guardar o valor original de algum ajuste. Esse ajuste NAO foi aplicado. Confere permissao da pasta global_backup.", "FragBoost") | Out-Null
                return
            }
            if ($any) {
                [System.Windows.Forms.MessageBox]::Show("Ajustes aplicados. Reinicie o PC pra tudo valer.", "FragBoost") | Out-Null
            }
            else {
                [System.Windows.Forms.MessageBox]::Show("Nenhum ajuste selecionado.", "FragBoost") | Out-Null
            }
        }.GetNewClosure())

    $btnStatus.Add_Click({
            foreach ($t in $Tweaks) { $t.Control.Checked = [bool](& $t.StatusCheck) }
            & $refreshInfo

            $sf = New-Object System.Windows.Forms.Form
            $sf.Text = "Status"
            $sf.Size = New-Object System.Drawing.Size(440, 480)
            $sf.StartPosition = "CenterParent"
            $sf.FormBorderStyle = "None"
            $sf.BackColor = $colorBg
            $sf.ForeColor = $colorText
            Set-RoundedForm $sf $cardRadius

            $statusDrag = New-DragHandler $sf

            $bar = New-Object System.Windows.Forms.Panel
            $bar.Size = New-Object System.Drawing.Size(440, 30)
            $bar.BackColor = $colorPanel
            $bar.Add_MouseDown($statusDrag)
            $sf.Controls.Add($bar)

            $lblBar = New-Object System.Windows.Forms.Label
            $lblBar.Text = "STATUS - $HeaderText"
            $lblBar.Font = $fontBtn
            $lblBar.ForeColor = $colorMuted
            $lblBar.Location = New-Object System.Drawing.Point(12, 6)
            $lblBar.Size = New-Object System.Drawing.Size(320, 20)
            $lblBar.Add_MouseDown($statusDrag)
            $bar.Controls.Add($lblBar)

            $btnCloseStatus = New-Object System.Windows.Forms.Button
            $btnCloseStatus.Text = "X"
            $btnCloseStatus.FlatStyle = "Flat"
            $btnCloseStatus.FlatAppearance.BorderSize = 0
            $btnCloseStatus.BackColor = $colorAccent
            $btnCloseStatus.ForeColor = [System.Drawing.Color]::White
            $btnCloseStatus.Size = New-Object System.Drawing.Size(30, 30)
            $btnCloseStatus.Location = New-Object System.Drawing.Point(410, 0)
            $btnCloseStatus.Add_Click({ $sf.Close() }.GetNewClosure())
            $bar.Controls.Add($btnCloseStatus)

            $listBox = New-Object System.Windows.Forms.Panel
            $listBox.Location = New-Object System.Drawing.Point(15, 40)
            $listBox.Size = New-Object System.Drawing.Size(410, 340)
            $listBox.AutoScroll = $true
            $sf.Controls.Add($listBox)

            $sy = 0
            foreach ($t in $Tweaks) {
                $ativo = [bool](& $t.StatusCheck)

                $lbl = New-Object System.Windows.Forms.Label
                $lbl.Text = $t.Label
                $lbl.Font = $fontItem
                $lbl.ForeColor = $colorText
                $lbl.Location = New-Object System.Drawing.Point(0, $sy)
                $lbl.Size = New-Object System.Drawing.Size(280, 30)
                $listBox.Controls.Add($lbl)

                $tag = New-Object System.Windows.Forms.Label
                $tag.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
                $tag.TextAlign = "MiddleRight"
                $tag.Location = New-Object System.Drawing.Point(285, $sy)
                $tag.Size = New-Object System.Drawing.Size(100, 20)
                if ($ativo) { $tag.Text = "ATIVO"; $tag.ForeColor = $colorOk }
                else { $tag.Text = "INATIVO"; $tag.ForeColor = $colorMuted }
                $listBox.Controls.Add($tag)

                $sy += 34
            }

            $infoY = 390
            foreach ($linha in (& $InfoLines)) {
                $l = New-Object System.Windows.Forms.Label
                $l.Text = $linha
                $l.Font = $fontItem
                $l.ForeColor = $colorMuted
                $l.Location = New-Object System.Drawing.Point(15, $infoY)
                $l.Size = New-Object System.Drawing.Size(410, 20)
                $sf.Controls.Add($l)
                $infoY += 20
            }

            $sf.ShowDialog() | Out-Null
        }.GetNewClosure())

    $btnRevert.Add_Click({
            $r = [System.Windows.Forms.MessageBox]::Show(
                "Sim = restaurar backup exato de antes.`nNao = resetar pro padrao aproximado do Windows.",
                "Reverter", "YesNoCancel")

            $bdir = Join-Path $BackupRoot $BackupSubDir

            if ($r -eq "Yes") {
                if (Restore-Owner $BackupSubDir) {
                    foreach ($t in $Tweaks) { $t.Control.Checked = [bool](& $t.StatusCheck) }
                    & $refreshInfo
                    [System.Windows.Forms.MessageBox]::Show("Valores originais restaurados. Reinicie o PC.", "Reverter") | Out-Null
                }
                elseif (Test-Path $bdir) {
                    # legado: aba que so passou pela versao antiga
                    Get-ChildItem -Path $bdir -Filter "*.reg" | ForEach-Object { reg.exe import "$($_.FullName)" *> $null }
                    $guidSalvo = Get-SavedPowerPlan $BackupSubDir
                    if ($guidSalvo) { powercfg /setactive $guidSalvo }
                    foreach ($t in $Tweaks) { $t.Control.Checked = [bool](& $t.StatusCheck) }
                    & $refreshInfo
                    [System.Windows.Forms.MessageBox]::Show("Backup restaurado. Reinicie o PC.", "Reverter") | Out-Null
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("Nenhum backup encontrado.", "Reverter") | Out-Null
                }
            }
            elseif ($r -eq "No") {
                if ($ResetDefaults) {
                    & $ResetDefaults
                    foreach ($t in $Tweaks) { $t.Control.Checked = [bool](& $t.StatusCheck) }
                    & $refreshInfo
                    [System.Windows.Forms.MessageBox]::Show("Resetado pro padrao aproximado. Reinicie o PC.", "Reverter") | Out-Null
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("Sem reset padrao definido pra esta aba - use Sim pra restaurar do backup.", "Reverter") | Out-Null
                }
            }
        }.GetNewClosure())

    return $panel
}

# ----------------------- ACAO "BOOST AGORA" (compartilhada) -----------------------
# Mesma logica do botao BOOST AGORA do Valorant Otimizador original,
# parametrizada por nome de processo - usada por Valorant, Roblox e
# qualquer jogo adicionado na biblioteca.

function New-BoostAction([string]$procName, [string]$backupSub) {
    return {
        $msgLines = @()
        $proc = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($proc) {
            try { $proc.PriorityClass = "High"; $msgLines += "Prioridade do processo elevada" } catch {}
        }
        else {
            $msgLines += "Jogo nao esta rodando agora"
        }

        Save-PowerPlanOriginal $backupSub
        powercfg /setactive SCHEME_MIN | Out-Null
        $msgLines += "Plano de energia: Alto desempenho"

        $rodando = @()
        foreach ($nome in $BG_HOGS) { if (Get-Process -Name $nome -ErrorAction SilentlyContinue) { $rodando += $nome } }
        if ($rodando.Count -gt 0) {
            $lista = $rodando -join ", "
            $r = [System.Windows.Forms.MessageBox]::Show("Fechar estes processos? $lista", "Boost agora", "YesNo")
            if ($r -eq "Yes") {
                foreach ($nome in $rodando) { Stop-Process -Name $nome -Force -ErrorAction SilentlyContinue }
                $msgLines += "Processos fechados: $lista"
            }
        }

        $trimLog = Invoke-WorkingSetTrim
        foreach ($linha in $trimLog) {
            if ($linha.Text) { $msgLines += $linha.Text }
        }

        ipconfig /flushdns | Out-Null
        $msgLines += "Cache de DNS limpo"
        [System.Windows.Forms.MessageBox]::Show(($msgLines -join "`n"), "Boost agora") | Out-Null
    }.GetNewClosure()
}

# ----------------------- ABA: VALORANT -----------------------
# Config salvo > metadata da Riot (product_install_root, mais confiavel
# que assumir disco/pasta padrao) > "C:\Riot Games" como ultimo recurso.
# Sem popup automatico se nao achar - a aba so mostra "nao encontrado" e
# quem localiza manualmente (pelo card na grade) e o usuario, quando quiser.

$RiotDir = $Cfg.RiotDir
$ValExe = Join-Path $RiotDir $RelValorantExe
if (-not (Test-Path $ValExe)) {
    $riotRoot = Find-RiotProductRoot "valorant.live"
    if ($riotRoot) {
        $RiotDir = $riotRoot
        $ValExe = Join-Path $RiotDir $RelValorantExe
        $Cfg.RiotDir = $RiotDir
        Save-Config $Cfg
    }
}
$ValExeName = "VALORANT-Win64-Shipping.exe"

$ValorantTweaks = Get-UniversalGameTweaks -ExeName $ValExeName -ExePath $ValExe -GameDir $RiotDir -BackupSub "valorant_backup"

$valorantInfo = {
    $achou = if (Test-Path $ValExe) { "VALORANT encontrado" } else { "VALORANT nao encontrado" }
    $defAtivo = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath -contains $RiotDir
    $defStatus = if ($defAtivo) { "Defender: pasta excluida" } else { "Defender: sem exclusao" }
    @($achou, $defStatus)
}

$valorantQuickActions = @(
    @{ Text = "BOOST AGORA"; OnClick = (New-BoostAction "VALORANT-Win64-Shipping" "valorant_backup") }
)

$PanelValorant = New-TweaksPanel -Width $contentWidth -Height $contentHeight `
    -Tweaks $ValorantTweaks -QuickActions $valorantQuickActions -InfoLines $valorantInfo `
    -BackupSubDir "valorant_backup" `
    -ResetDefaults ({ Reset-UniversalGameDefaults -ExeName $ValExeName -ExePath $ValExe -GameDir $RiotDir -BackupSub "valorant_backup" }.GetNewClosure()) `
    -HeaderText "VALORANT"

# ----------------------- ABA: ROBLOX -----------------------
# Mesmo motor universal, agora apontado pro executavel do Roblox -
# proximo jogo da biblioteca, como pedido.

$RobloxDir = $Cfg.RobloxDir
$RbxExe = Find-RobloxExe $RobloxDir
if (-not $RbxExe) { $RbxExe = Join-Path $RobloxDir "RobloxPlayerBeta.exe" }
$RbxExeName = "RobloxPlayerBeta.exe"

$RobloxTweaks = Get-UniversalGameTweaks -ExeName $RbxExeName -ExePath $RbxExe -GameDir $RobloxDir -BackupSub "roblox_backup"

$robloxInfo = {
    $achou = if (Test-Path $RbxExe) { "Roblox encontrado" } else { "Roblox nao encontrado" }
    $defAtivo = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath -contains $RobloxDir
    $defStatus = if ($defAtivo) { "Defender: pasta excluida" } else { "Defender: sem exclusao" }
    @($achou, $defStatus)
}

$robloxQuickActions = @(
    @{ Text = "BOOST AGORA"; OnClick = (New-BoostAction "RobloxPlayerBeta" "roblox_backup") }
)

$PanelRoblox = New-TweaksPanel -Width $contentWidth -Height $contentHeight `
    -Tweaks $RobloxTweaks -QuickActions $robloxQuickActions -InfoLines $robloxInfo `
    -BackupSubDir "roblox_backup" `
    -ResetDefaults ({ Reset-UniversalGameDefaults -ExeName $RbxExeName -ExePath $RbxExe -GameDir $RobloxDir -BackupSub "roblox_backup" }.GetNewClosure()) `
    -HeaderText "ROBLOX"

# ----------------------- ABA: MINECRAFT -----------------------
# .minecraft (%appdata%) e o padrao universal (launcher oficial, Forge,
# Fabric) pra assets/mods/saves - e o que vale excluir do Defender. O
# javaw.exe que roda o jogo e generico (QUALQUER app Java usa esse nome),
# entao o motor entra com -SkipCpuPriority: ligar prioridade de CPU via
# IFEO por nome afetaria todo programa Java da maquina, nao so o jogo.

$MinecraftDir = Join-Path $env:APPDATA ".minecraft"
$McJavaw = $Cfg.MinecraftJavaw
if (-not $McJavaw -or -not (Test-Path $McJavaw)) { $McJavaw = Find-MinecraftJavaw $MinecraftDir }
if (-not $McJavaw) { $McJavaw = Join-Path $MinecraftDir "javaw.exe" }
$McExeName = "javaw.exe"

$MinecraftTweaks = Get-UniversalGameTweaks -ExeName $McExeName -ExePath $McJavaw -GameDir $MinecraftDir -BackupSub "minecraft_backup" -SkipCpuPriority

$minecraftInfo = {
    $achou = if (Test-Path $McJavaw) { "Executavel encontrado (javaw.exe)" } else { "Executavel nao encontrado" }
    $defAtivo = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath -contains $MinecraftDir
    $defStatus = if ($defAtivo) { "Defender: pasta excluida" } else { "Defender: sem exclusao" }
    @($achou, $defStatus, "Prioridade de CPU fica de fora (javaw.exe e nome generico)")
}

$minecraftRamAction = {
    $totalGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $sugestao = [math]::Max(2, [math]::Min($totalGB - 4, [math]::Floor($totalGB / 2)))
    [System.Windows.Forms.MessageBox]::Show(
        "RAM total detectada: ${totalGB}GB.`nSugestao de alocacao maxima (-Xmx): ${sugestao}GB.`n`nCola esse valor em: Launcher oficial > Instalacoes > editar > Mais opcoes > argumentos da JVM (-Xmx${sugestao}G).",
        "Sugestao de RAM") | Out-Null
}

# BOOST AGORA aqui sobe a prioridade so do processo javaw QUE JA ESTA
# RODANDO (temporario, so enquanto o jogo ta aberto) - bem mais seguro que
# a IFEO permanente que a gente evitou acima, mas ainda vale lembrar que
# afeta qualquer javaw.exe ativo no momento do clique, nao so o Minecraft.
$minecraftQuickActions = @(
    @{ Text = "BOOST AGORA"; OnClick = (New-BoostAction "javaw" "minecraft_backup") }
    @{ Text = "SUGERIR RAM IDEAL"; OnClick = $minecraftRamAction }
)

$PanelMinecraft = New-TweaksPanel -Width $contentWidth -Height $contentHeight `
    -Tweaks $MinecraftTweaks -QuickActions $minecraftQuickActions -InfoLines $minecraftInfo `
    -BackupSubDir "minecraft_backup" `
    -ResetDefaults ({ Reset-UniversalGameDefaults -ExeName $McExeName -ExePath $McJavaw -GameDir $MinecraftDir -BackupSub "minecraft_backup" -SkipCpuPriority }.GetNewClosure()) `
    -HeaderText "MINECRAFT"

# ----------------------- ABA: CS2 -----------------------
# Pasta na Steam nunca mudou de nome desde a era CS:GO. Exe unico
# (cs2.exe), sem risco de colisao - motor universal entra completo,
# prioridade de CPU inclusa.

$Cs2Dir = $Cfg.Cs2Dir
$Cs2Exe = if ($Cs2Dir) { Join-Path $Cs2Dir "game\bin\win64\cs2.exe" } else { $null }
if (-not $Cs2Exe -or -not (Test-Path $Cs2Exe)) {
    $achado = Find-Cs2Exe
    if ($achado) {
        $Cs2Dir = $achado.GameDir; $Cs2Exe = $achado.ExePath
        $Cfg.Cs2Dir = $Cs2Dir
        Save-Config $Cfg
    }
}
if (-not $Cs2Dir) { $Cs2Dir = "C:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive" }
if (-not $Cs2Exe) { $Cs2Exe = Join-Path $Cs2Dir "game\bin\win64\cs2.exe" }
$Cs2ExeName = "cs2.exe"

$Cs2Tweaks = Get-UniversalGameTweaks -ExeName $Cs2ExeName -ExePath $Cs2Exe -GameDir $Cs2Dir -BackupSub "cs2_backup"

$cs2Info = {
    $achou = if (Test-Path $Cs2Exe) { "CS2 encontrado" } else { "CS2 nao encontrado" }
    $defAtivo = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath -contains $Cs2Dir
    $defStatus = if ($defAtivo) { "Defender: pasta excluida" } else { "Defender: sem exclusao" }
    @($achou, $defStatus)
}

$cs2ShaderCacheAction = {
    $pastas = @(
        (Join-Path $env:LOCALAPPDATA "D3DSCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\DxCache")
    )
    $limpas = @()
    foreach ($p in $pastas) {
        if (Test-Path $p) {
            Remove-Item -Path (Join-Path $p "*") -Recurse -Force -ErrorAction SilentlyContinue
            $limpas += $p
        }
    }
    if ($limpas.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show("Cache de shaders limpo em:`n$($limpas -join "`n")`nO driver recompila sozinho na proxima execucao (pode dar uns segundos de engasgo so na primeira vez).", "Limpar cache de shaders") | Out-Null
    }
    else {
        [System.Windows.Forms.MessageBox]::Show("Nenhuma pasta de cache de shader encontrada.", "Limpar cache de shaders") | Out-Null
    }
}

$cs2QuickActions = @(
    @{ Text = "BOOST AGORA"; OnClick = (New-BoostAction "cs2" "cs2_backup") }
    @{ Text = "LIMPAR CACHE DE SHADERS"; OnClick = $cs2ShaderCacheAction }
)

$PanelCs2 = New-TweaksPanel -Width $contentWidth -Height $contentHeight `
    -Tweaks $Cs2Tweaks -QuickActions $cs2QuickActions -InfoLines $cs2Info `
    -BackupSubDir "cs2_backup" `
    -ResetDefaults ({ Reset-UniversalGameDefaults -ExeName $Cs2ExeName -ExePath $Cs2Exe -GameDir $Cs2Dir -BackupSub "cs2_backup" }.GetNewClosure()) `
    -HeaderText "CS2"

# ----------------------- ABA: GTA V -----------------------
# GTA V hoje sao DOIS jogos separados na Steam (Legacy e Enhanced), com
# exe diferente - guarda qual foi achado (GtaExeName) pra nao reconsultar
# isso toda vez. Alem do motor universal, ganha um ajuste extra de
# prioridade de E/S (IoPriority via IFEO): mundo aberto sofre bastante com
# streaming de asset, entao prioridade de disco alta ajuda mais aqui do
# que num mapa pequeno tipo CS2.

$GtaDir = $Cfg.GtaDir
$GtaExeName = $Cfg.GtaExeName
$GtaExe = if ($GtaDir -and $GtaExeName) { Join-Path $GtaDir $GtaExeName } else { $null }
if (-not $GtaExe -or -not (Test-Path $GtaExe)) {
    $achado = Find-GtaExe
    if ($achado) {
        $GtaDir = $achado.GameDir; $GtaExe = $achado.ExePath; $GtaExeName = $achado.ExeName
        $Cfg.GtaDir = $GtaDir; $Cfg.GtaExeName = $GtaExeName
        Save-Config $Cfg
    }
}
if (-not $GtaDir) { $GtaDir = "C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto V" }
if (-not $GtaExeName) { $GtaExeName = "GTA5.exe" }
if (-not $GtaExe) { $GtaExe = Join-Path $GtaDir $GtaExeName }

$GtaTweaks = Get-UniversalGameTweaks -ExeName $GtaExeName -ExePath $GtaExe -GameDir $GtaDir -BackupSub "gta_backup"
$gtaIfeoKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$GtaExeName\PerfOptions"
$GtaTweaks += @{ Label = "Prioridade de E/S alta (streaming de mundo aberto)"
    StatusCheck        = { (Get-Reg $gtaIfeoKey "IoPriority") -eq 3 }.GetNewClosure()
    Apply              = {
        Backup-Key $gtaIfeoKey "ifeo" "gta_backup"
        Set-Reg $gtaIfeoKey "IoPriority" 3
    }.GetNewClosure()
}

$gtaInfo = {
    $achou = if (Test-Path $GtaExe) { "GTA V encontrado ($GtaExeName)" } else { "GTA V nao encontrado" }
    $defAtivo = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath -contains $GtaDir
    $defStatus = if ($defAtivo) { "Defender: pasta excluida" } else { "Defender: sem exclusao" }
    @($achou, $defStatus)
}

$gtaQuickActions = @(
    @{ Text = "BOOST AGORA"; OnClick = (New-BoostAction ([IO.Path]::GetFileNameWithoutExtension($GtaExeName)) "gta_backup") }
)

$PanelGta = New-TweaksPanel -Width $contentWidth -Height $contentHeight `
    -Tweaks $GtaTweaks -QuickActions $gtaQuickActions -InfoLines $gtaInfo `
    -BackupSubDir "gta_backup" `
    -ResetDefaults ({ Reset-UniversalGameDefaults -ExeName $GtaExeName -ExePath $GtaExe -GameDir $GtaDir -BackupSub "gta_backup" }.GetNewClosure()) `
    -HeaderText "GTA V"

# ----------------------- ABA: WARFRAME -----------------------
# Motor universal completo (Warframe.x64.exe e exe unico, sem colisao).
# Ajuste extra: limpar o cache de shader/textura do proprio motor
# (Cache.Windows, dentro de Downloaded\Public) - resolve boa parte dos
# engasgos que sobram depois de update de driver ou de patch do jogo.

$WarframeDir = $Cfg.WarframeDir
$WfExe = if ($WarframeDir) { Join-Path $WarframeDir "Downloaded\Public\Warframe.x64.exe" } else { $null }
if (-not $WfExe -or -not (Test-Path $WfExe)) {
    $achado = Find-WarframeExe
    if ($achado) {
        $WarframeDir = $achado.GameDir; $WfExe = $achado.ExePath
        $Cfg.WarframeDir = $WarframeDir
        Save-Config $Cfg
    }
}
if (-not $WarframeDir) { $WarframeDir = "C:\Program Files (x86)\Steam\steamapps\common\Warframe" }
if (-not $WfExe) { $WfExe = Join-Path $WarframeDir "Downloaded\Public\Warframe.x64.exe" }
$WfExeName = "Warframe.x64.exe"

$WarframeTweaks = Get-UniversalGameTweaks -ExeName $WfExeName -ExePath $WfExe -GameDir $WarframeDir -BackupSub "warframe_backup"

$warframeInfo = {
    $achou = if (Test-Path $WfExe) { "Warframe encontrado" } else { "Warframe nao encontrado" }
    $defAtivo = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath -contains $WarframeDir
    $defStatus = if ($defAtivo) { "Defender: pasta excluida" } else { "Defender: sem exclusao" }
    @($achou, $defStatus)
}

$warframeCacheAction = {
    $cache = Join-Path $WarframeDir "Downloaded\Public\Cache.Windows"
    if (Test-Path $cache) {
        Remove-Item -Path (Join-Path $cache "*") -Recurse -Force -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show("Cache do motor limpo. O launcher reconstroi sozinho na proxima verificacao de arquivos.", "Limpar cache") | Out-Null
    }
    else {
        [System.Windows.Forms.MessageBox]::Show("Pasta de cache nao encontrada (Cache.Windows).", "Limpar cache") | Out-Null
    }
}.GetNewClosure()

$warframeQuickActions = @(
    @{ Text = "BOOST AGORA"; OnClick = (New-BoostAction "Warframe.x64" "warframe_backup") }
    @{ Text = "LIMPAR CACHE DO MOTOR"; OnClick = $warframeCacheAction }
)

$PanelWarframe = New-TweaksPanel -Width $contentWidth -Height $contentHeight `
    -Tweaks $WarframeTweaks -QuickActions $warframeQuickActions -InfoLines $warframeInfo `
    -BackupSubDir "warframe_backup" `
    -ResetDefaults ({ Reset-UniversalGameDefaults -ExeName $WfExeName -ExePath $WfExe -GameDir $WarframeDir -BackupSub "warframe_backup" }.GetNewClosure()) `
    -HeaderText "WARFRAME"

# ----------------------- ABA: DAYZ -----------------------
# Motor universal completo + prioridade de E/S alta (mesmo motivo do GTA
# V - streaming de terreno aberto). A DayZ roda com BattlEye: os ajustes
# aqui mexem so em registro (prioridade/IFEO), nunca no processo do jogo
# em tempo real - e a mesma tecnica que ferramentas tipo Process Lasso
# usam ha anos sem bloqueio do anticheat, mas fica registrado por
# transparencia.

$DayzDir = $Cfg.DayzDir
$DayzExe = if ($DayzDir) { Join-Path $DayzDir "DayZ_x64.exe" } else { $null }
if (-not $DayzExe -or -not (Test-Path $DayzExe)) {
    $achado = Find-DayzExe
    if ($achado) {
        $DayzDir = $achado.GameDir; $DayzExe = $achado.ExePath
        $Cfg.DayzDir = $DayzDir
        Save-Config $Cfg
    }
}
if (-not $DayzDir) { $DayzDir = "C:\Program Files (x86)\Steam\steamapps\common\DayZ" }
if (-not $DayzExe) { $DayzExe = Join-Path $DayzDir "DayZ_x64.exe" }
$DayzExeName = "DayZ_x64.exe"

$DayzTweaks = Get-UniversalGameTweaks -ExeName $DayzExeName -ExePath $DayzExe -GameDir $DayzDir -BackupSub "dayz_backup"
$dayzIfeoKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$DayzExeName\PerfOptions"
$DayzTweaks += @{ Label = "Prioridade de E/S alta (streaming de terreno)"
    StatusCheck         = { (Get-Reg $dayzIfeoKey "IoPriority") -eq 3 }.GetNewClosure()
    Apply               = {
        Backup-Key $dayzIfeoKey "ifeo" "dayz_backup"
        Set-Reg $dayzIfeoKey "IoPriority" 3
    }.GetNewClosure()
}

$dayzInfo = {
    $achou = if (Test-Path $DayzExe) { "DayZ encontrado" } else { "DayZ nao encontrado" }
    $defAtivo = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath -contains $DayzDir
    $defStatus = if ($defAtivo) { "Defender: pasta excluida" } else { "Defender: sem exclusao" }
    @($achou, $defStatus, "Usa BattlEye - ajustes daqui sao so registro, nada injeta no processo")
}

$dayzQuickActions = @(
    @{ Text = "BOOST AGORA"; OnClick = (New-BoostAction "DayZ_x64" "dayz_backup") }
)

$PanelDayz = New-TweaksPanel -Width $contentWidth -Height $contentHeight `
    -Tweaks $DayzTweaks -QuickActions $dayzQuickActions -InfoLines $dayzInfo `
    -BackupSubDir "dayz_backup" `
    -ResetDefaults ({ Reset-UniversalGameDefaults -ExeName $DayzExeName -ExePath $DayzExe -GameDir $DayzDir -BackupSub "dayz_backup" }.GetNewClosure()) `
    -HeaderText "DAYZ"

# ----------------------- ABA: CPU -----------------------
# Copiado do Otimizador-de-CPU-GUI.ps1 original - ajustes de sistema,
# nao dependem de nenhum jogo especifico.

$CPU_PRIORITY_KEY = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
$CPU_POWERTHROTTLE_KEY = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
$CPU_ALTO_DESEMPENHO_GUID = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

$SERVICOS_STRESS = @(
    @{ Nome = "SysMain"; Descricao = "Superfetch" },
    @{ Nome = "DiagTrack"; Descricao = "Telemetria da Microsoft" },
    @{ Nome = "WSearch"; Descricao = "Indexacao de busca do Windows" }
)

$ProcessosProtegidos = @("System", "Idle", "csrss", "wininit", "services", "lsass", "winlogon", "smss", "svchost", "Registry", "Memory Compression")

$CpuTweaks = @(
    @{ Label        = "Desempenho Maximo (energia + core parking)"
        StatusCheck = {
            $t = (powercfg /getactivescheme | Out-String)
            ($t -match "Ultimate Performance") -or ($t -match [regex]::Escape($CPU_ALTO_DESEMPENHO_GUID))
        }
        Apply       = {
            Save-PowerPlanOriginal "cpu_backup"
            $guidAlvo = $null
            $planos = (powercfg /list | Out-String)
            if ($planos -match "([0-9a-fA-F-]{36})\s*\(Ultimate Performance\)") { $guidAlvo = $Matches[1] }
            if (-not $guidAlvo) {
                $dupTxt = (powercfg /duplicatescheme $ULTIMATE_GUID | Out-String)
                $guidAlvo = Get-Guid $dupTxt
            }
            if (-not $guidAlvo) { $guidAlvo = $CPU_ALTO_DESEMPENHO_GUID }

            powercfg /setactive $guidAlvo
            powercfg -setacvalueindex $guidAlvo SUB_PROCESSOR CPMINCORES 100
            powercfg -setacvalueindex $guidAlvo SUB_PROCESSOR CPMAXCORES 100
            powercfg -setdcvalueindex $guidAlvo SUB_PROCESSOR CPMINCORES 100
            powercfg -setdcvalueindex $guidAlvo SUB_PROCESSOR CPMAXCORES 100
            powercfg -S $guidAlvo
        }
    },
    @{ Label        = "Prioridade de foreground (Win32PrioritySeparation)"
        StatusCheck = { (Get-Reg $CPU_PRIORITY_KEY "Win32PrioritySeparation") -eq 38 }
        Apply       = {
            Backup-Key $CPU_PRIORITY_KEY "prioritycontrol" "cpu_backup"
            Set-Reg $CPU_PRIORITY_KEY "Win32PrioritySeparation" 38
        }
    },
    @{ Label        = "MMCSS sem reserva de CPU (SystemResponsiveness)"
        StatusCheck = { (Get-Reg $G_MMCSS_KEY "SystemResponsiveness") -eq 0 }
        Apply       = {
            Backup-Key $G_MMCSS_KEY "systemprofile" "cpu_backup"
            Set-Reg $G_MMCSS_KEY "SystemResponsiveness" 0
        }
    },
    @{ Label        = "Power Throttling off + clock travado 100%"
        StatusCheck = { (Get-Reg $CPU_POWERTHROTTLE_KEY "PowerThrottlingOff") -eq 1 }
        Apply       = {
            Save-PowerPlanOriginal "cpu_backup"
            Backup-Key $CPU_POWERTHROTTLE_KEY "powerthrottling" "cpu_backup"
            Set-Reg $CPU_POWERTHROTTLE_KEY "PowerThrottlingOff" 1
            $g = Get-GuidAtivo
            if ($g) {
                powercfg -setacvalueindex $g SUB_PROCESSOR PROCTHROTTLEMAX 100
                powercfg -setacvalueindex $g SUB_PROCESSOR PROCTHROTTLEMIN 100
                powercfg -setdcvalueindex $g SUB_PROCESSOR PROCTHROTTLEMAX 100
                powercfg -setdcvalueindex $g SUB_PROCESSOR PROCTHROTTLEMIN 100
                powercfg -S $g
            }
        }
    },
    @{ Label        = "Servicos em 2o plano desativados (SysMain/DiagTrack/WSearch)"
        StatusCheck = {
            $todos = $true
            foreach ($s in $SERVICOS_STRESS) {
                $svc = Get-Service -Name $s.Nome -ErrorAction SilentlyContinue
                if (-not $svc -or $svc.StartType -ne "Disabled") { $todos = $false }
            }
            $todos
        }
        Apply       = {
            foreach ($s in $SERVICOS_STRESS) {
                $svc = Get-Service -Name $s.Nome -ErrorAction SilentlyContinue
                if (-not $svc) { continue }
                $svcKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Nome)"
                if (-not (Save-RegOriginal $svcKey "Start" $global:FragOwner)) { $global:FragFalha = $true; continue }
                Save-RegOriginal $svcKey "DelayedAutostart" $global:FragOwner | Out-Null
                Backup-Key $svcKey "svc_$($s.Nome)" "cpu_backup"
                if ($svc.Status -eq "Running") { Stop-Service -Name $s.Nome -Force -ErrorAction SilentlyContinue }
                Set-Service -Name $s.Nome -StartupType Disabled -ErrorAction SilentlyContinue
            }
        }
    }
)

function Reset-CpuDefaults {
    if (Restore-Owner "cpu_backup") { return }
    Set-Reg $CPU_PRIORITY_KEY "Win32PrioritySeparation" 2
    Set-Reg $G_MMCSS_KEY "SystemResponsiveness" 20
    Remove-Reg $CPU_POWERTHROTTLE_KEY "PowerThrottlingOff"

    $guidSalvo = Get-SavedPowerPlan "cpu_backup"
    if ($guidSalvo) { powercfg /setactive $guidSalvo } else { powercfg /setactive SCHEME_BALANCED }

    foreach ($s in $SERVICOS_STRESS) {
        $svc = Get-Service -Name $s.Nome -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service -Name $s.Nome -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name $s.Nome -ErrorAction SilentlyContinue
        }
    }
}

function Show-ProcessCleanupWindow {
    $pf = New-Object System.Windows.Forms.Form
    $pf.Text = "Limpeza de processos"
    $pf.Size = New-Object System.Drawing.Size(460, 480)
    $pf.StartPosition = "CenterScreen"
    $pf.FormBorderStyle = "None"
    $pf.BackColor = $colorBg
    $pf.ForeColor = $colorText
    Set-RoundedForm $pf $cardRadius

    $pDrag = New-DragHandler $pf

    $pBar = New-Object System.Windows.Forms.Panel
    $pBar.Size = New-Object System.Drawing.Size(460, 30)
    $pBar.BackColor = $colorPanel
    $pBar.Add_MouseDown($pDrag)
    $pf.Controls.Add($pBar)

    $pLbl = New-Object System.Windows.Forms.Label
    $pLbl.Text = "LIMPEZA DE PROCESSOS"
    $pLbl.Font = $fontBtn
    $pLbl.ForeColor = $colorMuted
    $pLbl.Location = New-Object System.Drawing.Point(12, 6)
    $pLbl.Size = New-Object System.Drawing.Size(300, 20)
    $pLbl.Add_MouseDown($pDrag)
    $pBar.Controls.Add($pLbl)

    $pClose = New-Object System.Windows.Forms.Button
    $pClose.Text = "X"
    $pClose.FlatStyle = "Flat"
    $pClose.FlatAppearance.BorderSize = 0
    $pClose.BackColor = $colorAccent
    $pClose.ForeColor = [System.Drawing.Color]::White
    $pClose.Size = New-Object System.Drawing.Size(30, 30)
    $pClose.Location = New-Object System.Drawing.Point(430, 0)
    $pClose.Add_Click({ $pf.Close() }.GetNewClosure())
    $pBar.Controls.Add($pClose)

    $pHeader = New-Object System.Windows.Forms.Label
    $pHeader.Text = "TOP CONSUMIDORES DE CPU"
    $pHeader.Font = $fontBtn
    $pHeader.ForeColor = $colorAccent
    $pHeader.Location = New-Object System.Drawing.Point(15, 40)
    $pHeader.Size = New-Object System.Drawing.Size(300, 20)
    $pf.Controls.Add($pHeader)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"
    $lv.CheckBoxes = $true
    $lv.FullRowSelect = $true
    $lv.GridLines = $false
    $lv.BackColor = $colorPanel
    $lv.ForeColor = $colorText
    $lv.Font = $fontItem
    $lv.Location = New-Object System.Drawing.Point(15, 66)
    $lv.Size = New-Object System.Drawing.Size(415, 300)
    $lv.Columns.Add("Processo", 160) | Out-Null
    $lv.Columns.Add("PID", 60) | Out-Null
    $lv.Columns.Add("CPU (s)", 90) | Out-Null
    $lv.Columns.Add("RAM (MB)", 95) | Out-Null
    $pf.Controls.Add($lv)

    $processos = Get-Process |
    Where-Object { $_.CPU -gt 0 -and ($ProcessosProtegidos -notcontains $_.ProcessName) } |
    Sort-Object CPU -Descending |
    Select-Object -First 20

    foreach ($p in $processos) {
        $item = New-Object System.Windows.Forms.ListViewItem($p.ProcessName)
        $item.SubItems.Add("$($p.Id)") | Out-Null
        $item.SubItems.Add(("{0:N1}" -f $p.CPU)) | Out-Null
        $item.SubItems.Add(("{0:N1}" -f ($p.WorkingSet64 / 1MB))) | Out-Null
        $item.Tag = $p.Id
        $lv.Items.Add($item) | Out-Null
    }

    $btnKill = New-Object System.Windows.Forms.Button
    $btnKill.Text = "ENCERRAR SELECIONADOS"
    $btnKill.Font = $fontBtn
    $btnKill.FlatStyle = "Flat"
    $btnKill.FlatAppearance.BorderSize = 0
    $btnKill.BackColor = $colorBg
    $btnKill.ForeColor = [System.Drawing.Color]::White
    $btnKill.Location = New-Object System.Drawing.Point(15, 378)
    $btnKill.Size = New-Object System.Drawing.Size(415, 36)
    $btnKill.Add_Paint({
            param($s, $e)
            Clear-ButtonSurface $s $e.Graphics
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $path = New-RoundedPath $s.Width $s.Height $btnRadius
            $brush = New-Object System.Drawing.SolidBrush($colorAccent)
            $e.Graphics.FillPath($brush, $path)
            Write-ButtonLabel $s $e.Graphics $s.ForeColor
            $brush.Dispose(); $path.Dispose()
        })
    $btnKill.Add_Click({
            $mortos = @()
            foreach ($item in $lv.CheckedItems) {
                try {
                    Stop-Process -Id $item.Tag -Force -ErrorAction Stop
                    $mortos += $item.Text
                }
                catch {}
            }
            if ($mortos.Count -gt 0) {
                [System.Windows.Forms.MessageBox]::Show("Encerrado: $($mortos -join ', ')", "Limpeza de processos") | Out-Null
            }
            else {
                [System.Windows.Forms.MessageBox]::Show("Nenhum processo selecionado.", "Limpeza de processos") | Out-Null
            }
            $pf.Close()
        }.GetNewClosure())
    $pf.Controls.Add($btnKill)

    $pNote = New-Object System.Windows.Forms.Label
    $pNote.Text = "Processo critico do sistema fica de fora da lista."
    $pNote.Font = $fontSmall
    $pNote.ForeColor = $colorMuted
    $pNote.Location = New-Object System.Drawing.Point(15, 420)
    $pNote.Size = New-Object System.Drawing.Size(415, 20)
    $pf.Controls.Add($pNote)

    $pf.ShowDialog() | Out-Null
}

$cpuInfo = {
    $nucleos = [Environment]::ProcessorCount
    @("Nucleos logicos: $nucleos")
}

$cpuQuickActions = @(
    @{ Text = "LIMPAR PROCESSOS"; OnClick = { Show-ProcessCleanupWindow } }
)

$PanelCpu = New-TweaksPanel -Width $contentWidth -Height $contentHeight `
    -Tweaks $CpuTweaks -QuickActions $cpuQuickActions -InfoLines $cpuInfo `
    -BackupSubDir "cpu_backup" -ResetDefaults { Reset-CpuDefaults } `
    -HeaderText "CPU" -ShowBackToGames $false

# ----------------------- CONSTRUTOR DE PAINEL "FERRAMENTAS" (acao unica) -----------------------
# Usado pela aba RAM: ferramentas que rodam uma vez e mostram
# resultado, sem StatusCheck/Aplicar (nao sao liga/desliga
# persistente como os ajustes de jogo/CPU).

function New-ActionsPanel {
    param(
        [int]$Width,
        [int]$Height,
        [array]$Tools,
        [scriptblock]$InfoLines,
        [string]$HeaderText
    )

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($Width, $Height)
    $panel.BackColor = $colorBg

    $header = New-Object System.Windows.Forms.Label
    $header.Text = $HeaderText
    $header.Font = $fontTitle
    $header.ForeColor = $colorAccent
    $header.Location = New-Object System.Drawing.Point(0, 4)
    $header.Size = New-Object System.Drawing.Size($Width, 30)
    $header.Padding = New-Object System.Windows.Forms.Padding(15, 0, 0, 0)
    $panel.Controls.Add($header)

    $leftW = 270
    $gbLeft = New-CardPanel 15 40 $leftW ($Height - 55) $colorBg $colorCard
    $panel.Controls.Add($gbLeft)

    $lblLeftHead = New-Object System.Windows.Forms.Label
    $lblLeftHead.Text = "FERRAMENTAS"
    $lblLeftHead.ForeColor = $colorMuted
    $lblLeftHead.Font = $fontBtn
    $lblLeftHead.Location = New-Object System.Drawing.Point(15, 10)
    $lblLeftHead.Size = New-Object System.Drawing.Size(($leftW - 24), 16)
    $gbLeft.Controls.Add($lblLeftHead)

    $rightX = 15 + $leftW + 15
    $rightW = $Width - $rightX - 15
    $gbRight = New-CardPanel $rightX 40 $rightW ($Height - 55) $colorBg $colorCard
    $panel.Controls.Add($gbRight)

    $lblRightHead = New-Object System.Windows.Forms.Label
    $lblRightHead.Text = "RESULTADO"
    $lblRightHead.ForeColor = $colorMuted
    $lblRightHead.Font = $fontBtn
    $lblRightHead.Location = New-Object System.Drawing.Point(15, 10)
    $lblRightHead.Size = New-Object System.Drawing.Size(($rightW - 24), 16)
    $gbRight.Controls.Add($lblRightHead)

    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Location = New-Object System.Drawing.Point(10, 32)
    $rtb.Size = New-Object System.Drawing.Size(($rightW - 20), ($gbRight.Height - 42))
    $rtb.BackColor = $colorCard
    $rtb.ForeColor = $colorText
    $rtb.Font = $fontMono
    $rtb.BorderStyle = "None"
    $rtb.ReadOnly = $true
    $gbRight.Controls.Add($rtb)

    $appendLog = {
        param($linhas)
        foreach ($l in $linhas) {
            $rtb.SelectionStart = $rtb.TextLength
            $rtb.SelectionLength = 0
            $rtb.SelectionColor = $l.Color
            $rtb.AppendText("$($l.Text)`n")
        }
        $rtb.ScrollToCaret()
    }.GetNewClosure()

    $y = 34
    foreach ($tool in $Tools) {
        $b = New-ActionButton $tool.Label $y ($leftW - 30)
        $b.Height = 44
        $b.TextAlign = "MiddleLeft"
        $b.Add_Click({
                $rtb.Clear()
                $resultado = & $tool.Action
                & $appendLog $resultado
                $cancelado = ($resultado.Count -gt 0) -and ($resultado[-1].Text -eq "Cancelado.")
                if (-not $cancelado) {
                    [System.Windows.Forms.MessageBox]::Show("Feito.", "FragBoost") | Out-Null
                }
            }.GetNewClosure())
        $gbLeft.Controls.Add($b)
        $y += 52
    }

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Font = $fontSmall
    $lblInfo.ForeColor = $colorMuted
    $lblInfo.Location = New-Object System.Drawing.Point(15, $y)
    $lblInfo.Size = New-Object System.Drawing.Size(($leftW - 30), 90)
    $lblInfo.Text = ((& $InfoLines) -join "`n")
    $gbLeft.Controls.Add($lblInfo)

    return $panel
}

# ----------------------- ABA: RAM -----------------------
# Mesma logica do RamBoost.ps1 original (Clear-StandbyList,
# Invoke-WorkingSetTrim, Stop-BackgroundHelpers, etc) - so troca
# Write-Host por linhas de log devolvidas pra tela, ja que agora e
# painel grafico e nao console.

function Get-TopRamProcesses {
    $rows = Get-Process | Sort-Object WS -Descending | Select-Object -First 15 ProcessName, Id,
    @{ Name = 'RAM_MB'; Expression = { [math]::Round($_.WS / 1MB, 1) } }
    $log = @(@{ Text = ("{0,-24}{1,-8}{2,10}" -f "PROCESSO", "PID", "RAM(MB)"); Color = $colorMuted })
    foreach ($r in $rows) {
        $log += @{ Text = ("{0,-24}{1,-8}{2,10}" -f $r.ProcessName, $r.Id, $r.RAM_MB); Color = $colorText }
    }
    return $log
}

function Clear-StandbyList {
    $log = @(@{ Text = "Limpando memoria em cache do sistema (standby list)..."; Color = $colorText })
    try {
        if (-not ("RamBoost.MemPurge" -as [type])) {
            Add-Type -Namespace RamBoost -Name MemPurge -MemberDefinition @'
[DllImport("ntdll.dll")]
public static extern int NtSetSystemInformation(int infoClass, IntPtr info, int infoLength);

[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool LookupPrivilegeValue(string systemName, string name, out long luid);

[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool AdjustTokenPrivileges(IntPtr tokenHandle, bool disableAll, ref TOKEN_PRIVILEGES newState, int bufferLength, IntPtr previousState, IntPtr returnLength);

[StructLayout(LayoutKind.Sequential, Pack = 4)]
public struct TOKEN_PRIVILEGES {
    public int PrivilegeCount;
    public long Luid;
    public int Attributes;
}

public static bool EnablePrivilege(string name) {
    IntPtr token;
    if (!OpenProcessToken(System.Diagnostics.Process.GetCurrentProcess().Handle, 0x28, out token)) return false;
    long luid;
    if (!LookupPrivilegeValue(null, name, out luid)) return false;
    TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
    tp.PrivilegeCount = 1;
    tp.Luid = luid;
    tp.Attributes = 0x2;
    bool ok = AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    if (!ok) return false;
    return Marshal.GetLastWin32Error() == 0;
}

public static int PurgeStandbyList() {
    int command = 4;
    IntPtr buf = Marshal.AllocHGlobal(sizeof(int));
    Marshal.WriteInt32(buf, command);
    int status = NtSetSystemInformation(80, buf, sizeof(int));
    Marshal.FreeHGlobal(buf);
    return status;
}
'@ -ErrorAction Stop
        }

        $p1 = [RamBoost.MemPurge]::EnablePrivilege("SeProfileSingleProcessPrivilege")
        $p2 = [RamBoost.MemPurge]::EnablePrivilege("SeIncreaseQuotaPrivilege")

        $status = [RamBoost.MemPurge]::PurgeStandbyList()
        if ($status -eq 0) {
            $log += @{ Text = " - cache liberado, sobrou mais memoria livre pro trim usar."; Color = $colorOk }
        }
        elseif (-not ($p1 -or $p2)) {
            $log += @{ Text = " - conta nao tem o privilegio necessario habilitado (mesmo como admin). Codigo: $status"; Color = $colorMuted }
        }
        else {
            $log += @{ Text = " - nao consegui liberar (precisa administrador). Codigo: $status"; Color = $colorMuted }
        }
    }
    catch {
        $log += @{ Text = " - falha ao limpar cache do sistema: $($_.Exception.Message)"; Color = $colorMuted }
        $log += @{ Text = " - seguindo pro trim de working set mesmo assim."; Color = $colorMuted }
    }
    return $log
}

function Invoke-WorkingSetTrim {
    $log = @()
    $log += Clear-StandbyList
    $log += @{ Text = ""; Color = $colorText }
    $log += @{ Text = "Compactando working set de todos os processos..."; Color = $colorText }
    $log += @{ Text = "(forca cada processo a devolver pagina ociosa. Se continuar ativo, a RAM sobe de novo rapido.)"; Color = $colorMuted }

    $ok = 0; $falha = 0
    foreach ($p in Get-Process) {
        try { $p.MinWorkingSet = $p.MinWorkingSet; $ok++ } catch { $falha++ }
    }
    $log += @{ Text = "Trim concluido: $ok processo(s) compactado(s), $falha ignorado(s) sem permissao."; Color = $colorOk }
    return $log
}

function Stop-BackgroundHelpers {
    function Stop-HelperByName([string]$ExeName) {
        $proc = Get-Process -Name ($ExeName -replace '\.exe$', '') -ErrorAction SilentlyContinue
        if ($proc) {
            $proc | Stop-Process -Force -ErrorAction SilentlyContinue
            return @{ Text = " - $ExeName finalizado"; Color = $colorOk }
        }
        else {
            return @{ Text = " - $ExeName nao estava rodando"; Color = $colorMuted }
        }
    }

    $log = @(@{ Text = "Matando processos de fundo do Discord/Spotify..."; Color = $colorText })
    $log += Stop-HelperByName "SpotifyWebHelper.exe"
    $log += Stop-HelperByName "Spotify.UpdateService.exe"

    $achouDiscord = $false
    Get-CimInstance Win32_Process -Filter "Name='Update.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -like '*Discord*' } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        $achouDiscord = $true
    }
    if ($achouDiscord) { $log += @{ Text = " - Discord Update.exe finalizado"; Color = $colorOk } }

    $log += Stop-HelperByName "plugin-container.exe"
    $log += @{ Text = "Discord, Spotify e Firefox continuam abertos, so morreu processo de apoio."; Color = $colorMuted }
    return $log
}

function Clear-SystemCache {
    $log = @(@{ Text = "Limpando temporarios, cache DNS, prefetch, thumbnails..."; Color = $colorText })
    Remove-Item -Path (Join-Path $env:TEMP '*') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'C:\Windows\Prefetch\*' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer\thumbcache_*.db') -Force -ErrorAction SilentlyContinue
    ipconfig /flushdns | Out-Null
    $log += @{ Text = "Limpeza concluida. (Prefetch pode falhar sem admin, sem problema.)"; Color = $colorOk }
    return $log
}

function Restart-Explorer {
    $log = @(@{ Text = "Reiniciando o Explorer.exe..."; Color = $colorText })
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Start-Process explorer.exe
    $log += @{ Text = "Feito."; Color = $colorOk }
    return $log
}

function Close-HeavyApps {
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Isso fecha Firefox, Discord e Spotify AGORA, sem salvar nada.`nAbas abertas no Firefox, mensagem nao enviada no Discord: perdido.",
        "Fechar apps pesados", "YesNo")
    if ($r -ne "Yes") { return @(@{ Text = "Cancelado."; Color = $colorMuted }) }
    foreach ($nome in "firefox", "Discord", "Spotify") {
        Stop-Process -Name $nome -Force -ErrorAction SilentlyContinue
    }
    return @(@{ Text = "Fechado."; Color = $colorOk })
}

$RamTools = @(
    @{ Label = "Ver top 15 processos que mais consomem RAM"; Action = { Get-TopRamProcesses } }
    @{ Label = "Limpar cache do sistema e compactar processos (working set trim)"; Action = { Invoke-WorkingSetTrim } }
    @{ Label = "Matar processos de fundo do Discord/Spotify (nao fecha o app)"; Action = { Stop-BackgroundHelpers } }
    @{ Label = "Limpar temporarios, cache DNS, prefetch, thumbnails"; Action = { Clear-SystemCache } }
    @{ Label = "Reiniciar o Explorer.exe (libera RAM do shell)"; Action = { Restart-Explorer } }
    @{ Label = "Fechar Firefox, Discord e Spotify de vez"; Action = { Close-HeavyApps } }
)

$ramInfo = {
    @("Firefox/Discord/Spotify sao", "multi-processo por natureza -", "fechar aba ajuda mais que", "qualquer limpador de RAM.")
}

$PanelRam = New-ActionsPanel -Width $contentWidth -Height $contentHeight -Tools $RamTools -InfoLines $ramInfo -HeaderText "RAM"

# ----------------------- BIBLIOTECA: JOGOS ADICIONADOS PELO USUARIO -----------------------
# Constroi (ou reconstroi, ao carregar de novo) a aba de um jogo que
# entrou na biblioteca via "OTIMIZACAO GERAL". Mesma logica pra um
# jogo recem-adicionado ou um jogo salvo de uma sessao anterior -
# $SaveToConfig controla se grava no config.json (nao grava de novo
# se ja veio de la).

function Add-CustomGameTab {
    param(
        [string]$Nome,
        [string]$ExeName,
        [string]$ExePath,
        [string]$GameDir,
        [string]$Slug,
        [bool]$SaveToConfig
    )

    $backupSub = "custom_backup\$Slug"
    $tweaks = Get-UniversalGameTweaks -ExeName $ExeName -ExePath $ExePath -GameDir $GameDir -BackupSub $backupSub

    $infoBlock = {
        $achou = if (Test-Path $ExePath) { "Executavel encontrado" } else { "Executavel nao encontrado" }
        @($achou)
    }.GetNewClosure()

    $removerAction = {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "Remover '$Nome' da biblioteca do FragBoost?`n(so tira da lista - nao desinstala nada e nao reverte ajustes ja aplicados)",
            "Remover jogo", "YesNo")
        if ($r -eq "Yes") {
            $Cfg.CustomGames = @($Cfg.CustomGames | Where-Object { $_.Slug -ne $Slug })
            Save-Config $Cfg
            $contentHost.Controls.Remove($TabPanels[$Slug])
            $TabPanels.Remove($Slug)
            $idx = 0
            while ($idx -lt $GameEntries.Count) {
                if ($GameEntries[$idx].Slug -eq $Slug) { $GameEntries.RemoveAt($idx) } else { $idx++ }
            }
            Rebuild-GameGrid
            Show-Tab "JOGOSGRID"
        }
    }.GetNewClosure()

    $procName = [IO.Path]::GetFileNameWithoutExtension($ExeName)
    $quickActions = @(
        @{ Text = "BOOST AGORA"; OnClick = (New-BoostAction $procName $backupSub) }
        @{ Text = "REMOVER JOGO"; OnClick = $removerAction }
    )

    $resetAction = { Reset-UniversalGameDefaults -ExeName $ExeName -ExePath $ExePath -GameDir $GameDir -BackupSub $backupSub }.GetNewClosure()

    $panel = New-TweaksPanel -Width $contentWidth -Height $contentHeight `
        -Tweaks $tweaks -QuickActions $quickActions -InfoLines $infoBlock `
        -BackupSubDir $backupSub -ResetDefaults $resetAction -HeaderText $Nome.ToUpper()

    $panel.Location = New-Object System.Drawing.Point(0, 0)
    $panel.Visible = $false
    $contentHost.Controls.Add($panel)
    $TabPanels[$Slug] = $panel

    $mono = ($Nome.Trim() + "??").Substring(0, 2).ToUpper()
    $GameEntries.Add(@{
            Slug = $Slug; Nome = $Nome.ToUpper(); ExePath = $ExePath; Mono = $mono
            Found = (Test-Path $ExePath); LocateKind = "file"
            OnLocate = {
                param($p)
                foreach ($g in $Cfg.CustomGames) { if ($g.Slug -eq $Slug) { $g.ExePath = $p } }
                Save-Config $Cfg
            }.GetNewClosure()
        })

    if ($SaveToConfig) {
        $Cfg.CustomGames = @($Cfg.CustomGames) + [PSCustomObject]@{
            Nome = $Nome; ExeName = $ExeName; ExePath = $ExePath; Dir = $GameDir; Slug = $Slug
        }
        Save-Config $Cfg
    }

    return $panel
}

# ----------------------- ICONE (base64 embutido, mesma ideia do config.json: grava do lado do script) -----------------------
# O .ico inteiro (todos os tamanhos, 16 a 256px) vai embutido em base64 pra
# o app continuar sendo um arquivo unico - nada de arquivo solto pra perder.
# So grava uma copia de verdade em disco (do lado do config.json) na hora de
# dar o icone pro atalho da area de trabalho, que exige um arquivo real.
$FragBoostIconBase64 = "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"

# System.Drawing.Icon le mal .ico com quadros PNG (icone sai borrado/quebrado),
# entao dentro do app o icone vem de um PNG comum decodificado como Bitmap.
$FragBoostPngBase64 = "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"

function Get-FragBoostBitmap([int]$Size) {
    try {
        $bytes = [Convert]::FromBase64String($FragBoostPngBase64)
        $ms = New-Object System.IO.MemoryStream(, $bytes)
        $src = New-Object System.Drawing.Bitmap($ms)
        $dst = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($dst)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($src, 0, 0, $Size, $Size)
        $g.Dispose(); $src.Dispose(); $ms.Dispose()
        return $dst
    }
    catch { return $null }
}

try {
    $iconBytes = [Convert]::FromBase64String($FragBoostIconBase64)
    if (-not (Test-Path $IconFile) -or (Get-Item $IconFile).Length -ne $iconBytes.Length) {
        [IO.File]::WriteAllBytes($IconFile, $iconBytes)
    }
}
catch {}

# ----------------------- JANELA PRINCIPAL -----------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "FragBoost"
$form.Size = New-Object System.Drawing.Size($formWidth, $formHeight)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "None"
$form.BackColor = $colorBg
$form.ForeColor = $colorText
Set-RoundedForm $form $winRadius

$formBmp = Get-FragBoostBitmap 64
if ($formBmp) { $form.Icon = [System.Drawing.Icon]::FromHandle($formBmp.GetHicon()) }

$dragHandler = New-DragHandler $form

$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Location = New-Object System.Drawing.Point(0, 0)
$titleBar.Size = New-Object System.Drawing.Size($formWidth, $titleBarH)
$titleBar.BackColor = $colorPanel
$titleBar.Add_MouseDown($dragHandler)
$form.Controls.Add($titleBar)

$picTitleIcon = New-Object System.Windows.Forms.PictureBox
$picTitleIcon.SizeMode = "Zoom"
$picTitleIcon.BackColor = [System.Drawing.Color]::Transparent
$picTitleIcon.Location = New-Object System.Drawing.Point(10, 4)
$picTitleIcon.Size = New-Object System.Drawing.Size(22, 22)
$headerBmp = Get-FragBoostBitmap 40
if ($headerBmp) { $picTitleIcon.Image = $headerBmp }
$picTitleIcon.Add_MouseDown($dragHandler)
$titleBar.Controls.Add($picTitleIcon)

$lblTitleBar = New-Object System.Windows.Forms.Label
$lblTitleBar.Text = "FRAGBOOST"
$lblTitleBar.ForeColor = $colorMuted
$lblTitleBar.Font = $fontBtn
$lblTitleBar.Location = New-Object System.Drawing.Point(38, 6)
$lblTitleBar.Size = New-Object System.Drawing.Size(300, 20)
$lblTitleBar.Add_MouseDown($dragHandler)
$titleBar.Controls.Add($lblTitleBar)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "X"
$btnClose.FlatStyle = "Flat"
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.BackColor = $colorAccent
$btnClose.ForeColor = [System.Drawing.Color]::White
$btnClose.Size = New-Object System.Drawing.Size(30, 30)
$btnClose.Location = New-Object System.Drawing.Point(($formWidth - 30), 0)
$btnClose.Add_Click({ $form.Close() })
$titleBar.Controls.Add($btnClose)

$btnMin = New-Object System.Windows.Forms.Button
$btnMin.Text = "-"
$btnMin.FlatStyle = "Flat"
$btnMin.FlatAppearance.BorderSize = 0
$btnMin.BackColor = $colorPanel
$btnMin.ForeColor = $colorText
$btnMin.Size = New-Object System.Drawing.Size(30, 30)
$btnMin.Location = New-Object System.Drawing.Point(($formWidth - 60), 0)
$btnMin.Add_Click({ $form.WindowState = "Minimized" })
$titleBar.Controls.Add($btnMin)

# ----------------------- BARRA DE CATEGORIAS (horizontal) -----------------------

$catBar = New-Object System.Windows.Forms.FlowLayoutPanel
$catBar.FlowDirection = "LeftToRight"
$catBar.WrapContents = $false
$catBar.Location = New-Object System.Drawing.Point(0, $titleBarH)
$catBar.Size = New-Object System.Drawing.Size($formWidth, $catBarH)
$catBar.BackColor = $colorPanel
$catBar.Padding = New-Object System.Windows.Forms.Padding(10, 6, 0, 0)
$form.Controls.Add($catBar)

# ----------------------- AREA DE CONTEUDO -----------------------

$contentHost = New-Object System.Windows.Forms.Panel
$contentHost.Location = New-Object System.Drawing.Point(0, ($titleBarH + $catBarH))
$contentHost.Size = New-Object System.Drawing.Size($contentWidth, $contentHeight)
$contentHost.BackColor = $colorBg
$form.Controls.Add($contentHost)

$TabPanels = @{}
$CategoryButtons = @{}
$GameEntries = New-Object System.Collections.Generic.List[object]

function Show-Tab([string]$key) {
    foreach ($k in @($TabPanels.Keys)) { $TabPanels[$k].Visible = ($k -eq $key) }
    $catAtiva = if ($key -eq "CPU") { "CPU" } elseif ($key -eq "RAM") { "RAM" } elseif ($key -eq "SISTEMA") { "SISTEMA" } else { "JOGOS" }
    foreach ($k in @($CategoryButtons.Keys)) {
        $CategoryButtons[$k].BackColor = if ($k -eq $catAtiva) { $colorSideSel } else { $colorPanel }
    }
}

function New-CategoryButton([string]$text, [System.Windows.Forms.FlowLayoutPanel]$parent) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Font = $fontBtn
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $colorPanel
    $b.ForeColor = $colorText
    $tsz = [System.Windows.Forms.TextRenderer]::MeasureText($text, $fontBtn)
    $b.Size = New-Object System.Drawing.Size(($tsz.Width + 34), 32)
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
    # Mesma logica das abas antigas: so desenha o bloco arredondado quando
    # selecionado (BackColor == colorSideSel, trocado pelo Show-Tab); sem
    # selecao, o desenho nativo do Flat ja basta.
    $b.Add_Paint({
            param($s, $e)
            if ($s.BackColor -ne $colorSideSel) { return }
            Clear-ButtonSurface $s $e.Graphics
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $path = New-RoundedPath $s.Width $s.Height $btnRadius
            $brush = New-Object System.Drawing.SolidBrush($colorSideSel)
            $e.Graphics.FillPath($brush, $path)
            Write-ButtonLabel $s $e.Graphics $s.ForeColor
            $brush.Dispose(); $path.Dispose()
        }.GetNewClosure())
    $parent.Controls.Add($b)
    return $b
}

# Icone de verdade direto do executavel (o mesmo que o Explorer mostra) -
# API nativa do .NET, sem hook nem script externo, sem risco de licenca
# porque le do proprio .exe que ja esta instalado na maquina do usuario.
function Get-ExeIcon([string]$exePath) {
    if (-not $exePath -or -not (Test-Path $exePath)) { return $null }
    try {
        $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
        if ($ico) {
            $bmp = $ico.ToBitmap()
            $ico.Dispose()
            return $bmp
        }
    }
    catch {}
    return $null
}

# Um "card" de jogo na grade (estilo biblioteca do Adrenalin/NVIDIA App):
# caixa arredondada no topo com o icone real do jogo (sigla de 2 letras se
# nao achar o exe), nome e status embaixo. Jogo nao encontrado fica
# esmaecido com link pra localizar na mao (sem popup automatico).
# Os textos usam BackColor = cor do card - o fundo padrao (preto da pagina)
# fazia faixas escuras por cima do card.
function New-GameTile([hashtable]$Entry, [System.Windows.Forms.FlowLayoutPanel]$Parent) {
    $achado = [bool]$Entry.Found
    $altura = if ($achado) { 106 } else { 126 }

    $tile = New-Object System.Windows.Forms.Panel
    $tile.Size = New-Object System.Drawing.Size(112, $altura)
    $tile.Margin = New-Object System.Windows.Forms.Padding(7)
    $tile.BackColor = $colorBg
    $tile.Add_Paint({
            param($s, $e)
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $path = New-RoundedPath $s.Width $s.Height $cardRadius
            $brush = New-Object System.Drawing.SolidBrush($colorCard)
            $e.Graphics.FillPath($brush, $path)
            $brush.Dispose(); $path.Dispose()
        })

    $icone = if ($achado) { Get-ExeIcon $Entry.ExePath } else { $null }

    $iconBox = New-Object System.Windows.Forms.Panel
    $iconBox.Location = New-Object System.Drawing.Point(10, 10)
    $iconBox.Size = New-Object System.Drawing.Size(92, 42)
    $iconBox.BackColor = $colorCard
    $iconBox.Tag = @{
        Icon = $icone
        Mono = [string]$Entry.Mono
        Fill = if ($achado) { [System.Drawing.Color]::FromArgb(255, 42, 42, 50) } else { [System.Drawing.Color]::FromArgb(255, 28, 28, 33) }
        Text = if ($achado) { $colorText } else { [System.Drawing.Color]::FromArgb(255, 78, 78, 86) }
    }
    $iconBox.Add_Paint({
            param($s, $e)
            $d = $s.Tag
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $path = New-RoundedPath $s.Width $s.Height 8
            $brush = New-Object System.Drawing.SolidBrush($d.Fill)
            $g.FillPath($brush, $path)
            $brush.Dispose(); $path.Dispose()
            if ($d.Icon) {
                $sz = 30
                $ix = [int](($s.Width - $sz) / 2)
                $iy = [int](($s.Height - $sz) / 2)
                $ipath = New-Object System.Drawing.Drawing2D.GraphicsPath
                $ipath.AddPath((New-RoundedPath $sz $sz 6), $false)
                $m = New-Object System.Drawing.Drawing2D.Matrix
                $m.Translate($ix, $iy)
                $ipath.Transform($m)
                $g.SetClip($ipath)
                $g.DrawImage($d.Icon, $ix, $iy, $sz, $sz)
                $g.ResetClip()
                $m.Dispose(); $ipath.Dispose()
            }
            else {
                $F = [System.Windows.Forms.TextFormatFlags]
                $rect = New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)
                [System.Windows.Forms.TextRenderer]::DrawText($g, $d.Mono, $fontTileMono, $rect, $d.Text, ($F::HorizontalCenter -bor $F::VerticalCenter -bor $F::NoPrefix))
            }
        })
    $tile.Controls.Add($iconBox)

    $lblNome = New-Object System.Windows.Forms.Label
    $lblNome.Text = $Entry.Nome
    $lblNome.Font = New-Object System.Drawing.Font($fontFamilyName, 8.5, [System.Drawing.FontStyle]::Bold)
    $lblNome.ForeColor = if ($achado) { $colorText } else { [System.Drawing.Color]::FromArgb(255, 120, 120, 128) }
    $lblNome.BackColor = $colorCard
    $lblNome.TextAlign = "MiddleCenter"
    $lblNome.AutoEllipsis = $true
    $lblNome.Location = New-Object System.Drawing.Point(4, 58)
    $lblNome.Size = New-Object System.Drawing.Size(104, 17)
    $tile.Controls.Add($lblNome)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = if ($achado) { "DETECTADO" } else { "NAO ENCONTRADO" }
    $lblStatus.Font = New-Object System.Drawing.Font($fontFamilyName, 7.5)
    $lblStatus.ForeColor = if ($achado) { $colorOk } else { $colorMuted }
    $lblStatus.BackColor = $colorCard
    $lblStatus.TextAlign = "MiddleCenter"
    $lblStatus.Location = New-Object System.Drawing.Point(4, 76)
    $lblStatus.Size = New-Object System.Drawing.Size(104, 15)
    $tile.Controls.Add($lblStatus)

    if ($achado) {
        $tile.Cursor = [System.Windows.Forms.Cursors]::Hand
        $clickAlvo = { Show-Tab $Entry.Slug }.GetNewClosure()
        foreach ($ctrl in @($tile, $iconBox, $lblNome, $lblStatus)) { $ctrl.Add_Click($clickAlvo) }
    }
    else {
        $lnkLocalizar = New-Object System.Windows.Forms.LinkLabel
        $lnkLocalizar.Text = "localizar manualmente"
        $lnkLocalizar.Font = New-Object System.Drawing.Font($fontFamilyName, 7.5)
        $lnkLocalizar.LinkColor = $colorAccent
        $lnkLocalizar.ActiveLinkColor = $colorAccent
        $lnkLocalizar.BackColor = $colorCard
        $lnkLocalizar.TextAlign = "MiddleCenter"
        $lnkLocalizar.Location = New-Object System.Drawing.Point(4, 96)
        $lnkLocalizar.Size = New-Object System.Drawing.Size(104, 22)
        $lnkLocalizar.Add_Click({
                if ($Entry.LocateKind -eq "file") {
                    $ofd = New-Object System.Windows.Forms.OpenFileDialog
                    $ofd.Filter = "Executavel (*.exe)|*.exe"
                    $ofd.Title = "Localizar $($Entry.Nome)"
                    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        & $Entry.OnLocate $ofd.FileName
                        [System.Windows.Forms.MessageBox]::Show("Localizado e salvo. Reinicie o FragBoost pra aplicar.", "Localizar jogo") | Out-Null
                    }
                }
                else {
                    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
                    $fbd.Description = "Selecione a pasta de instalacao de $($Entry.Nome)"
                    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        & $Entry.OnLocate $fbd.SelectedPath
                        [System.Windows.Forms.MessageBox]::Show("Localizado e salvo. Reinicie o FragBoost pra aplicar.", "Localizar jogo") | Out-Null
                    }
                }
            }.GetNewClosure())
        $tile.Controls.Add($lnkLocalizar)
    }

    $Parent.Controls.Add($tile)
}

function New-GameGridPanel {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($contentWidth, $contentHeight)
    $panel.BackColor = $colorBg

    $header = New-Object System.Windows.Forms.Label
    $header.Text = "JOGOS"
    $header.Font = $fontTitle
    $header.ForeColor = $colorAccent
    $header.Location = New-Object System.Drawing.Point(15, 4)
    $header.Size = New-Object System.Drawing.Size(300, 30)
    $panel.Controls.Add($header)

    $grid = New-Object System.Windows.Forms.FlowLayoutPanel
    $grid.FlowDirection = "LeftToRight"
    $grid.WrapContents = $true
    $grid.AutoScroll = $true
    $grid.Location = New-Object System.Drawing.Point(10, 40)
    $grid.Size = New-Object System.Drawing.Size(($contentWidth - 20), ($contentHeight - 50))
    $grid.BackColor = $colorBg
    $panel.Controls.Add($grid)

    foreach ($entry in $GameEntries) { New-GameTile $entry $grid }

    $tileAdd = New-Object System.Windows.Forms.Panel
    $tileAdd.Size = New-Object System.Drawing.Size(112, 126)
    $tileAdd.Margin = New-Object System.Windows.Forms.Padding(7)
    $tileAdd.BackColor = $colorBg
    $tileAdd.Cursor = [System.Windows.Forms.Cursors]::Hand
    $tileAdd.Add_Paint({
            param($s, $e)
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $path = New-RoundedPath $s.Width $s.Height $cardRadius
            $pen = New-Object System.Drawing.Pen($colorBorder, 1)
            $pen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
            $e.Graphics.DrawPath($pen, $path)
            $pen.Dispose(); $path.Dispose()
        })
    $lblPlus = New-Object System.Windows.Forms.Label
    $lblPlus.Text = "+"
    $lblPlus.Font = New-Object System.Drawing.Font($fontFamilyName, 20, [System.Drawing.FontStyle]::Bold)
    $lblPlus.ForeColor = $colorAccent
    $lblPlus.TextAlign = "MiddleCenter"
    $lblPlus.BackColor = $colorBg
    $lblPlus.Location = New-Object System.Drawing.Point(0, 28)
    $lblPlus.Size = New-Object System.Drawing.Size(112, 36)
    $tileAdd.Controls.Add($lblPlus)
    $lblAdd = New-Object System.Windows.Forms.Label
    $lblAdd.Text = "ADICIONAR JOGO"
    $lblAdd.Font = New-Object System.Drawing.Font($fontFamilyName, 7.5, [System.Drawing.FontStyle]::Bold)
    $lblAdd.ForeColor = $colorAccent
    $lblAdd.TextAlign = "MiddleCenter"
    $lblAdd.BackColor = $colorBg
    $lblAdd.Location = New-Object System.Drawing.Point(21, 68)
    $lblAdd.Size = New-Object System.Drawing.Size(70, 32)
    $tileAdd.Controls.Add($lblAdd)
    $clickAdd = { Show-Tab "GERAL" }
    $tileAdd.Add_Click($clickAdd); $lblPlus.Add_Click($clickAdd); $lblAdd.Add_Click($clickAdd)
    $grid.Controls.Add($tileAdd)

    return $panel
}

function Rebuild-GameGrid {
    if ($TabPanels.ContainsKey("JOGOSGRID")) {
        $antigo = $TabPanels["JOGOSGRID"]
        $contentHost.Controls.Remove($antigo)
        $TabPanels.Remove("JOGOSGRID")
        $antigo.Dispose()
    }
    $novo = New-GameGridPanel
    $novo.Location = New-Object System.Drawing.Point(0, 0)
    $novo.Visible = $false
    $contentHost.Controls.Add($novo)
    $TabPanels["JOGOSGRID"] = $novo
}

function New-SistemaPanel {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($contentWidth, $contentHeight)
    $panel.BackColor = $colorBg

    $header = New-Object System.Windows.Forms.Label
    $header.Text = "SISTEMA"
    $header.Font = $fontTitle
    $header.ForeColor = $colorAccent
    $header.Location = New-Object System.Drawing.Point(15, 4)
    $header.Size = New-Object System.Drawing.Size(300, 30)
    $panel.Controls.Add($header)

    $card = New-CardPanel 15 44 300 190 $colorBg $colorCard
    $panel.Controls.Add($card)

    $lblHead = New-Object System.Windows.Forms.Label
    $lblHead.Text = "INICIALIZACAO"
    $lblHead.ForeColor = $colorMuted
    $lblHead.Font = $fontBtn
    $lblHead.Location = New-Object System.Drawing.Point(15, 10)
    $lblHead.Size = New-Object System.Drawing.Size(270, 16)
    $card.Controls.Add($lblHead)

    $btnAtalhoGlobal = New-ActionButton $(if (Test-AtalhoInstalado) { "REMOVER ATALHO" } else { "CRIAR ATALHO" }) 34 270 $colorCard
    $btnAtalhoGlobal.Add_Click({
            if (Test-AtalhoInstalado) {
                $r = [System.Windows.Forms.MessageBox]::Show("Atalho sem UAC ja instalado. Remover?", "Atalho", "YesNo")
                if ($r -eq "Yes") {
                    Remove-Atalho
                    $btnAtalhoGlobal.Text = "CRIAR ATALHO"
                    [System.Windows.Forms.MessageBox]::Show("Atalho removido.", "Atalho") | Out-Null
                }
            }
            else {
                $r = [System.Windows.Forms.MessageBox]::Show(
                    "Cria um atalho na area de trabalho que abre o FragBoost inteiro direto como admin, sem pedir UAC de novo. Criar agora?",
                    "Atalho", "YesNo")
                if ($r -eq "Yes") {
                    New-Atalho
                    $btnAtalhoGlobal.Text = "REMOVER ATALHO"
                    [System.Windows.Forms.MessageBox]::Show("Atalho criado na area de trabalho.", "Atalho") | Out-Null
                }
            }
        }.GetNewClosure())
    $card.Controls.Add($btnAtalhoGlobal)

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Font = $fontSmall
    $lblInfo.ForeColor = $colorMuted
    $lblInfo.Location = New-Object System.Drawing.Point(15, 82)
    $lblInfo.Size = New-Object System.Drawing.Size(270, 90)
    $nucleosInfo = [Environment]::ProcessorCount
    $lblInfo.Text = "Administrador: sim`nNucleos logicos: $nucleosInfo"
    $card.Controls.Add($lblInfo)

    return $panel
}

$PanelValorant.Location = New-Object System.Drawing.Point(0, 0)
$contentHost.Controls.Add($PanelValorant)
$TabPanels["VALORANT"] = $PanelValorant
$GameEntries.Add(@{
        Slug = "VALORANT"; Nome = "VALORANT"; ExePath = $ValExe; Mono = "VA"
        Found = (Test-Path $ValExe); LocateKind = "folder"
        OnLocate = { param($p) $Cfg.RiotDir = $p; Save-Config $Cfg }.GetNewClosure()
    })

$PanelRoblox.Location = New-Object System.Drawing.Point(0, 0)
$contentHost.Controls.Add($PanelRoblox)
$TabPanels["ROBLOX"] = $PanelRoblox
$GameEntries.Add(@{
        Slug = "ROBLOX"; Nome = "ROBLOX"; ExePath = $RbxExe; Mono = "RB"
        Found = (Test-Path $RbxExe); LocateKind = "folder"
        OnLocate = { param($p) $Cfg.RobloxDir = $p; Save-Config $Cfg }.GetNewClosure()
    })

$PanelMinecraft.Location = New-Object System.Drawing.Point(0, 0)
$contentHost.Controls.Add($PanelMinecraft)
$TabPanels["MINECRAFT"] = $PanelMinecraft
$GameEntries.Add(@{
        Slug = "MINECRAFT"; Nome = "MINECRAFT"; ExePath = $McJavaw; Mono = "MC"
        Found = (Test-Path $McJavaw); LocateKind = "file"
        OnLocate = { param($p) $Cfg.MinecraftJavaw = $p; Save-Config $Cfg }.GetNewClosure()
    })

$PanelCs2.Location = New-Object System.Drawing.Point(0, 0)
$contentHost.Controls.Add($PanelCs2)
$TabPanels["CS2"] = $PanelCs2
$GameEntries.Add(@{
        Slug = "CS2"; Nome = "CS2"; ExePath = $Cs2Exe; Mono = "CS"
        Found = (Test-Path $Cs2Exe); LocateKind = "folder"
        OnLocate = { param($p) $Cfg.Cs2Dir = $p; Save-Config $Cfg }.GetNewClosure()
    })

$PanelGta.Location = New-Object System.Drawing.Point(0, 0)
$contentHost.Controls.Add($PanelGta)
$TabPanels["GTAV"] = $PanelGta
$GameEntries.Add(@{
        Slug = "GTAV"; Nome = "GTA V"; ExePath = $GtaExe; Mono = "GT"
        Found = (Test-Path $GtaExe); LocateKind = "folder"
        OnLocate = {
            param($p)
            $Cfg.GtaDir = $p
            $Cfg.GtaExeName = if (Test-Path (Join-Path $p "GTA5_Enhanced.exe")) { "GTA5_Enhanced.exe" } else { "GTA5.exe" }
            Save-Config $Cfg
        }.GetNewClosure()
    })

$PanelWarframe.Location = New-Object System.Drawing.Point(0, 0)
$contentHost.Controls.Add($PanelWarframe)
$TabPanels["WARFRAME"] = $PanelWarframe
$GameEntries.Add(@{
        Slug = "WARFRAME"; Nome = "WARFRAME"; ExePath = $WfExe; Mono = "WF"
        Found = (Test-Path $WfExe); LocateKind = "folder"
        OnLocate = { param($p) $Cfg.WarframeDir = $p; Save-Config $Cfg }.GetNewClosure()
    })

$PanelDayz.Location = New-Object System.Drawing.Point(0, 0)
$contentHost.Controls.Add($PanelDayz)
$TabPanels["DAYZ"] = $PanelDayz
$GameEntries.Add(@{
        Slug = "DAYZ"; Nome = "DAYZ"; ExePath = $DayzExe; Mono = "DZ"
        Found = (Test-Path $DayzExe); LocateKind = "folder"
        OnLocate = { param($p) $Cfg.DayzDir = $p; Save-Config $Cfg }.GetNewClosure()
    })

$PanelCpu.Location = New-Object System.Drawing.Point(0, 0)
$contentHost.Controls.Add($PanelCpu)
$TabPanels["CPU"] = $PanelCpu

$PanelRam.Location = New-Object System.Drawing.Point(0, 0)
$contentHost.Controls.Add($PanelRam)
$TabPanels["RAM"] = $PanelRam

# ----------------------- ABA: OTIMIZACAO GERAL (adicionar jogo novo) -----------------------
# Ponto de entrada da biblioteca: usuario escolhe o executavel de um
# jogo que ainda nao esta na lista, e a partir dai ele ganha aba
# propria e permanente com as otimizacoes universais, igual Valorant
# e Roblox.

$panelGeral = New-Object System.Windows.Forms.Panel
$panelGeral.Size = New-Object System.Drawing.Size($contentWidth, $contentHeight)
$panelGeral.BackColor = $colorBg
$panelGeral.Location = New-Object System.Drawing.Point(0, 0)

$geralHeader = New-Object System.Windows.Forms.Label
$geralHeader.Text = "OTIMIZACAO GERAL"
$geralHeader.Font = $fontTitle
$geralHeader.ForeColor = $colorAccent
$geralHeader.Location = New-Object System.Drawing.Point(15, 4)
$geralHeader.Size = New-Object System.Drawing.Size(($contentWidth - 30), 30)
$panelGeral.Controls.Add($geralHeader)

$lnkVoltarGeral = New-Object System.Windows.Forms.LinkLabel
$lnkVoltarGeral.Text = "< JOGOS"
$lnkVoltarGeral.Font = $fontSmall
$lnkVoltarGeral.LinkColor = $colorMuted
$lnkVoltarGeral.ActiveLinkColor = $colorAccent
$lnkVoltarGeral.Location = New-Object System.Drawing.Point(($contentWidth - 95), 12)
$lnkVoltarGeral.Size = New-Object System.Drawing.Size(70, 16)
$lnkVoltarGeral.TextAlign = "MiddleRight"
$lnkVoltarGeral.Add_Click({ Show-Tab "JOGOSGRID" })
$panelGeral.Controls.Add($lnkVoltarGeral)

$geralDesc = New-Object System.Windows.Forms.Label
$geralDesc.Text = "Escolha o executavel de outro jogo (que ainda nao esta na biblioteca) pra aplicar nele o mesmo conjunto de otimizacoes universais do Valorant/Roblox: prioridade de CPU, Game DVR, HAGS, MMCSS, exclusao no Defender, energia e rede.`nDepois de adicionado, o jogo ganha aba propria e permanente na BIBLIOTECA, ao lado dos outros."
$geralDesc.Font = $fontItem
$geralDesc.ForeColor = $colorMuted
$geralDesc.Location = New-Object System.Drawing.Point(15, 40)
$geralDesc.Size = New-Object System.Drawing.Size(($contentWidth - 30), 60)
$panelGeral.Controls.Add($geralDesc)

$gbAdd = New-CardPanel 15 110 ($contentWidth - 30) 200 $colorBg $colorCard
$panelGeral.Controls.Add($gbAdd)

$lblAddHead = New-Object System.Windows.Forms.Label
$lblAddHead.Text = "ADICIONAR JOGO A BIBLIOTECA"
$lblAddHead.ForeColor = $colorMuted
$lblAddHead.Font = $fontBtn
$lblAddHead.Location = New-Object System.Drawing.Point(15, 10)
$lblAddHead.Size = New-Object System.Drawing.Size(($contentWidth - 60), 16)
$gbAdd.Controls.Add($lblAddHead)

$lblNome = New-Object System.Windows.Forms.Label
$lblNome.Text = "Nome do jogo:"
$lblNome.Font = $fontItem
$lblNome.ForeColor = $colorText
$lblNome.Location = New-Object System.Drawing.Point(15, 30)
$lblNome.Size = New-Object System.Drawing.Size(150, 22)
$gbAdd.Controls.Add($lblNome)

$txtNomeJogo = New-Object System.Windows.Forms.TextBox
$txtNomeJogo.Font = $fontItem
$txtNomeJogo.BackColor = $colorCard
$txtNomeJogo.ForeColor = $colorText
$txtNomeJogo.BorderStyle = "FixedSingle"
$txtNomeJogo.Location = New-Object System.Drawing.Point(15, 54)
$txtNomeJogo.Size = New-Object System.Drawing.Size(300, 26)
$gbAdd.Controls.Add($txtNomeJogo)

$btnEscolherExe = New-Object System.Windows.Forms.Button
$btnEscolherExe.Text = "SELECIONAR EXECUTAVEL (.EXE)"
$btnEscolherExe.Font = $fontBtn
$btnEscolherExe.FlatStyle = "Flat"
$btnEscolherExe.FlatAppearance.BorderSize = 0
$btnEscolherExe.BackColor = $colorCard
$btnEscolherExe.ForeColor = $colorText
$btnEscolherExe.Location = New-Object System.Drawing.Point(15, 96)
$btnEscolherExe.Size = New-Object System.Drawing.Size(260, 36)
$btnEscolherExe.Add_Paint({
        param($s, $e)
        Clear-ButtonSurface $s $e.Graphics
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $path = New-RoundedPath $s.Width $s.Height $btnRadius
        $pen = New-Object System.Drawing.Pen($colorAccent, 1)
        $e.Graphics.DrawPath($pen, $path)
        Write-ButtonLabel $s $e.Graphics $s.ForeColor
        $pen.Dispose(); $path.Dispose()
    })
$gbAdd.Controls.Add($btnEscolherExe)

$lblExeEscolhido = New-Object System.Windows.Forms.Label
$lblExeEscolhido.Text = "(nenhum executavel selecionado)"
$lblExeEscolhido.Font = $fontSmall
$lblExeEscolhido.ForeColor = $colorMuted
$lblExeEscolhido.Location = New-Object System.Drawing.Point(15, 138)
$lblExeEscolhido.Size = New-Object System.Drawing.Size(($contentWidth - 60), 20)
$gbAdd.Controls.Add($lblExeEscolhido)

$btnAdicionarJogo = New-Object System.Windows.Forms.Button
$btnAdicionarJogo.Text = "ADICIONAR A BIBLIOTECA"
$btnAdicionarJogo.Font = $fontBtn
$btnAdicionarJogo.FlatStyle = "Flat"
$btnAdicionarJogo.FlatAppearance.BorderSize = 0
$btnAdicionarJogo.BackColor = $colorCard
$btnAdicionarJogo.ForeColor = [System.Drawing.Color]::White
$btnAdicionarJogo.Location = New-Object System.Drawing.Point(15, 164)
$btnAdicionarJogo.Size = New-Object System.Drawing.Size(260, 30)
$btnAdicionarJogo.Add_Paint({
        param($s, $e)
        Clear-ButtonSurface $s $e.Graphics
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $path = New-RoundedPath $s.Width $s.Height $btnRadius
        $brush = New-Object System.Drawing.SolidBrush($colorAccent)
        $e.Graphics.FillPath($brush, $path)
        Write-ButtonLabel $s $e.Graphics $s.ForeColor
        $brush.Dispose(); $path.Dispose()
    })
$gbAdd.Controls.Add($btnAdicionarJogo)

$script:GeralExePath = $null

$btnEscolherExe.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "Executavel (*.exe)|*.exe"
        $ofd.Title = "Selecionar executavel do jogo"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:GeralExePath = $ofd.FileName
            $lblExeEscolhido.Text = $ofd.FileName
            $lblExeEscolhido.ForeColor = $colorText
        }
    })

$btnAdicionarJogo.Add_Click({
        $nome = $txtNomeJogo.Text.Trim()
        if (-not $nome) {
            [System.Windows.Forms.MessageBox]::Show("Digite um nome pro jogo.", "FragBoost") | Out-Null
            return
        }
        if (-not $script:GeralExePath -or -not (Test-Path $script:GeralExePath)) {
            [System.Windows.Forms.MessageBox]::Show("Selecione um executavel (.exe) valido.", "FragBoost") | Out-Null
            return
        }

        $baseSlug = Get-GameSlug $nome
        $slug = $baseSlug
        $n = 2
        while ($TabPanels.ContainsKey($slug)) { $slug = "${baseSlug}_$n"; $n++ }

        $exeName = Split-Path -Leaf $script:GeralExePath
        $gameDir = Split-Path -Parent $script:GeralExePath

        Add-CustomGameTab -Nome $nome -ExeName $exeName -ExePath $script:GeralExePath -GameDir $gameDir -Slug $slug -SaveToConfig $true
        Rebuild-GameGrid

        $txtNomeJogo.Text = ""
        $lblExeEscolhido.Text = "(nenhum executavel selecionado)"
        $lblExeEscolhido.ForeColor = $colorMuted
        $script:GeralExePath = $null

        Show-Tab $slug
    })

$contentHost.Controls.Add($panelGeral)
$TabPanels["GERAL"] = $panelGeral

# ----------------------- CARREGAR JOGOS SALVOS (sessoes anteriores) -----------------------

foreach ($g in $Cfg.CustomGames) {
    if (-not $g.Slug -or $TabPanels.ContainsKey($g.Slug)) { continue }
    Add-CustomGameTab -Nome $g.Nome -ExeName $g.ExeName -ExePath $g.ExePath -GameDir $g.Dir -Slug $g.Slug -SaveToConfig $false
}

# ----------------------- GRADE DE JOGOS + BARRA DE CATEGORIAS -----------------------
# Monta por ultimo, depois que $GameEntries ja tem TODOS os jogos (fixos +
# customizados carregados acima) - assim a grade nasce completa, sem
# precisar reconstruir nada na primeira exibicao.

$PanelJogosGrid = New-GameGridPanel
$PanelJogosGrid.Location = New-Object System.Drawing.Point(0, 0)
$contentHost.Controls.Add($PanelJogosGrid)
$TabPanels["JOGOSGRID"] = $PanelJogosGrid

$PanelSistema = New-SistemaPanel
$PanelSistema.Location = New-Object System.Drawing.Point(0, 0)
$contentHost.Controls.Add($PanelSistema)
$TabPanels["SISTEMA"] = $PanelSistema

$btnCatJogos = New-CategoryButton "JOGOS" $catBar
$btnCatJogos.Add_Click({ Show-Tab "JOGOSGRID" })
$CategoryButtons["JOGOS"] = $btnCatJogos

$btnCatCpu = New-CategoryButton "CPU" $catBar
$btnCatCpu.Add_Click({ Show-Tab "CPU" })
$CategoryButtons["CPU"] = $btnCatCpu

$btnCatRam = New-CategoryButton "RAM" $catBar
$btnCatRam.Add_Click({ Show-Tab "RAM" })
$CategoryButtons["RAM"] = $btnCatRam

$btnCatSistema = New-CategoryButton "SISTEMA" $catBar
$btnCatSistema.Add_Click({ Show-Tab "SISTEMA" })
$CategoryButtons["SISTEMA"] = $btnCatSistema

# ----------------------- INICIO -----------------------

Show-Tab "JOGOSGRID"

[System.Windows.Forms.Application]::Run($form)
