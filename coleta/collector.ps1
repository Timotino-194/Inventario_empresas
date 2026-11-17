# ==============================================================================
# AGENTE DE COLETA DE INVENTARIO DE TI (WMI / CIM)
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ------------------------------------------------------------------------------
# 1. CONFIGURACAO DE ROTAS (Fallback Automatico: Rede Local -> Cloudflare)
# ------------------------------------------------------------------------------
$LocalHostName = "SERVIDOR-TI" # Nome ou IP da maquina servidora na LAN (ex: "192.168.1.100")
$CloudflareUrl = "LINK CLOUDFARE AQUI" # URL do Tunel Cloudflare

# Resolve endereco local
if ($env:COMPUTERNAME -eq $LocalHostName) {
    $TargetLocal = "127.0.0.1"
} else {
    $ResolvedIp = (Resolve-DnsName -Name $LocalHostName -Type A -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    $TargetLocal = if ($ResolvedIp) { $ResolvedIp } else { $LocalHostName }
}

$UrlLocal   = "http://${TargetLocal}:5000/api/specs"
$UrlExterna = "$($CloudflareUrl.TrimEnd('/'))/api/specs"

# Testa se a porta 5000 responde na rede local (timeout de 2 segundos)
$ServerUrl = $UrlExterna
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $conn = $tcp.BeginConnect($TargetLocal, 5000, $null, $null)
    if ($conn.AsyncWaitHandle.WaitOne(2000, $false) -and $tcp.Connected) {
        $ServerUrl = $UrlLocal
        Write-Host "[REDE] Servidor local detectado ($TargetLocal)." -ForegroundColor Green
    }
    $tcp.Close()
} catch {
    # Segue silenciosamente para a rota externa
}

if ($ServerUrl -eq $UrlExterna) {
    Write-Host "[REDE] Servidor local inacessivel. Usando rota externa Cloudflare..." -ForegroundColor Yellow
}

Write-Host "Coletando especificacoes de hardware e todos os discos..." -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 2. COLETA DE SISTEMA, HARDWARE E REDE
# ------------------------------------------------------------------------------
$Hostname = $env:COMPUTERNAME

# Sistema Operacional e Uptime
$OS        = Get-CimInstance Win32_OperatingSystem
$Sistema   = $OS.Caption -replace "Microsoft ", ""
$UptimeSpan = (Get-Date) - $OS.LastBootUpTime
$UptimeDias = [int]$UptimeSpan.TotalDays
$UptimeStr  = "$($UptimeSpan.Days)d $($UptimeSpan.Hours)h $($UptimeSpan.Minutes)m"

# Processador e Placa-Mae
$CPU       = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
$BoardInfo = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
$PlacaMae  = "$($BoardInfo.Manufacturer) $($BoardInfo.Product)".Trim()

# Memoria RAM
$RamTotalGB = [math]::Round($OS.TotalVisibleMemorySize / 1MB, 1)
$RamLivreGB = [math]::Round($OS.FreePhysicalMemory / 1MB, 1)
$RamUsadaGB = [math]::Round($RamTotalGB - $RamLivreGB, 1)
$RamUsoPct  = [int][math]::Round(($RamUsadaGB / $RamTotalGB) * 100, 0)
$RamDetalhe = "$RamUsadaGB GB / $RamTotalGB GB"

# IP Local (Prioriza interface com Gateway padrao ativo)
$IpLocal = (
    Get-NetIPConfiguration |
    Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq "Up" } |
    Select-Object -First 1
).IPv4Address.IPAddress

if (-not $IpLocal) {
    $IpLocal = (
        Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notmatch "^(127\.|169\.254\.)" } |
        Select-Object -First 1
    ).IPAddress
}
if (-not $IpLocal) { $IpLocal = "Nao identificado" }

# Impressora Padrao
$ImpPadrao = (Get-CimInstance Win32_Printer | Where-Object { $_.Default -eq $true } | Select-Object -First 1).Name
if (-not $ImpPadrao) { $ImpPadrao = "Nenhuma" }

# ------------------------------------------------------------------------------
# 3. COLETA DE ARMAZENAMENTO (MULTIPLOS DISCOS) E S.M.A.R.T.
# ------------------------------------------------------------------------------
$DiscosFixos   = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
$ListaDiscos   = @()
$MaiorUsoDisco = 0

foreach ($d in $DiscosFixos) {
    if ($d.Size -gt 0) {
        $TotalGB = [math]::Round($d.Size / 1GB, 0)
        $LivreGB = [math]::Round($d.FreeSpace / 1GB, 0)
        $UsadoGB = $TotalGB - $LivreGB
        $PctUso  = [int][math]::Round(($UsadoGB / $TotalGB) * 100, 0)

        if ($PctUso -gt $MaiorUsoDisco) { $MaiorUsoDisco = $PctUso }
        $ListaDiscos += "$($d.DeviceID) $UsadoGB/$TotalGB GB ($PctUso%)"
    }
}
$DiscoDetalhe = if ($ListaDiscos.Count -gt 0) { $ListaDiscos -join " | " } else { "Sem disco" }

# Status S.M.A.R.T. dos discos fisicos
$SmartStatus = "Healthy"
try {
    $PhysicalDisks = Get-PhysicalDisk -ErrorAction Stop
    $Unhealthy = $PhysicalDisks | Where-Object { $_.HealthStatus -ne "Healthy" }
    if ($Unhealthy) {
        $SmartStatus = ($Unhealthy.HealthStatus | Select-Object -Unique) -join ", "
    }
} catch {
    $WmiDisks = Get-CimInstance Win32_DiskDrive
    $BadWmi   = $WmiDisks | Where-Object { $_.Status -ne "OK" }
    if ($BadWmi) { $SmartStatus = "Alerta S.M.A.R.T." }
}

# ------------------------------------------------------------------------------
# 4. MOTOR DE DIAGNOSTICO PREVENTIVO
# ------------------------------------------------------------------------------
$NivelAlerta = "OK"
$Motivos     = @()

if ($SmartStatus -ne "Healthy" -and $SmartStatus -ne "OK") {
    $NivelAlerta = "CRITICO"
    $Motivos += "Falha S.M.A.R.T. ($SmartStatus)"
}

if ($MaiorUsoDisco -ge 90) {
    $NivelAlerta = "CRITICO"
    $Motivos += "Disco critico ($MaiorUsoDisco%)"
} elseif ($MaiorUsoDisco -ge 80) {
    if ($NivelAlerta -ne "CRITICO") { $NivelAlerta = "AVISO" }
    $Motivos += "Disco cheio ($MaiorUsoDisco%)"
}

if ($RamUsoPct -ge 90) {
    if ($NivelAlerta -ne "CRITICO") { $NivelAlerta = "AVISO" }
    $Motivos += "RAM saturada ($RamUsoPct%)"
}

if ($UptimeDias -ge 15) {
    if ($NivelAlerta -ne "CRITICO") { $NivelAlerta = "AVISO" }
    $Motivos += "Fadiga de Uptime (${UptimeDias}d sem reiniciar)"
}

$Diagnostico = if ($Motivos.Count -gt 0) { $Motivos -join " | " } else { "Operacao normal" }

# ------------------------------------------------------------------------------
# 5. ENVIO DO PAYLOAD JSON PARA A API FLASK
# ------------------------------------------------------------------------------
$PayloadObj = @{
    hostname          = $Hostname
    sistema           = $Sistema
    ip_local          = $IpLocal
    impressora_padrao = $ImpPadrao
    processador       = $CPU
    placa_mae         = $PlacaMae
    uptime            = $UptimeStr
    ram_uso_pct       = $RamUsoPct
    ram_detalhe       = $RamDetalhe
    disco_uso_pct     = $MaiorUsoDisco
    disco_detalhe     = $DiscoDetalhe
    smart_status      = $SmartStatus
    nivel_alerta      = $NivelAlerta
    diagnostico       = $Diagnostico
}

$JsonBody  = $PayloadObj | ConvertTo-Json -Depth 3 -Compress
$Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonBody)

try {
    $Response = Invoke-RestMethod -Uri $ServerUrl -Method Post -Body $Utf8Bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 10
    Write-Host "[OK] Dados de $Hostname enviados com sucesso para $ServerUrl!" -ForegroundColor Green
} catch {
    Write-Host "[ERRO] Falha ao conectar em $ServerUrl. Verifique se o servidor Flask ou o Tunel Cloudflare esta ativo." -ForegroundColor Red
    Write-Host "Detalhe: $($_.Exception.Message)" -ForegroundColor Yellow
}