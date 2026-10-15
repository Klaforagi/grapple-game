param([Parameter(Mandatory = $true)][string]$LuauPath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sources = @{
    cosmeticCatalog = 'src/ReplicatedStorage/Modules/CosmeticCatalog.lua'
    cosmeticTransaction = 'src/ReplicatedStorage/Modules/CosmeticTransaction.lua'
    cosmeticTests = 'tests/cosmetics.luau'
    cosmeticRollServer = 'src/ServerScriptService/CosmeticRolls.server.lua'
    cosmeticRollTests = 'tests/cosmeticrolls.luau'
    cosmeticPersistence = 'src/ServerScriptService/CosmeticPersistence.server.lua'
    cosmeticPersistenceTests = 'tests/cosmeticpersistence.luau'
    cosmeticFocus = 'src/ReplicatedStorage/Modules/CosmeticScreenFocus.lua'
    cosmeticFocusTests = 'tests/cosmeticfocus.luau'
    cosmeticSales = 'src/ServerScriptService/CosmeticSales.server.lua'
    cosmeticSaleTests = 'tests/cosmeticsales.luau'
    mobileFlopButton = 'src/ReplicatedStorage/Modules/MobileFlopButton.lua'
    mobileFlopTests = 'tests/mobileflop.luau'
    flopMotion = 'src/ReplicatedStorage/Modules/FlopMotion.lua'
    flopTests = 'tests/flop.luau'
    itemColors = 'src/ReplicatedStorage/ItemColors.lua'
    coins = 'src/ServerScriptService/Coins.server.lua'
    coinTests = 'tests/coins.luau'
    mapCoins = 'src/ServerScriptService/MapCoins.server.lua'
    mapCoinTests = 'tests/mapcoins.luau'
    upgrades = 'src/ReplicatedStorage/Modules/UpgradeCatalog.lua'
    upgradeServer = 'src/ServerScriptService/Upgrades.server.lua'
    upgradeTests = 'tests/upgrades.luau'
    playedTime = 'src/ServerScriptService/PlayedTimeLeaderboard.server.lua'
    playedTimeClient = 'src/StarterPlayer/StarterPlayerScripts/PlayedTimeLeaderboard.client.lua'
    playedTimeTests = 'tests/playedtime.luau'
    killsServer = 'src/ServerScriptService/Kills.server.lua'
    killsBoardClient = 'src/StarterPlayer/StarterPlayerScripts/KillsLeaderboard.client.lua'
    killsBoardTests = 'tests/killsboard.luau'
    coinsBoardClient = 'src/StarterPlayer/StarterPlayerScripts/CoinsLeaderboard.client.lua'
    coinsBoardTests = 'tests/coinsboard.luau'
    config = 'src/ReplicatedStorage/GrappleConfig.lua'
    ragdoll = 'src/ReplicatedStorage/Modules/RagdollService/init.lua'
    server = 'src/ServerScriptService/GrappleHandler.server.lua'
    tool = 'src/ReplicatedStorage/Modules/GrappleToolClient.lua'
    toolSetup = 'src/ReplicatedStorage/Modules/GrappleToolSetup.lua'
    ragdollToolClient = 'src/ReplicatedStorage/Modules/RagdollToolClient.lua'
    lifecycle = 'src/ServerScriptService/PlayerCollisions&Ragdolls.server.lua'
    bombPhysics = 'src/ReplicatedStorage/Modules/BombPhysics.lua'
    bombs = 'src/ServerScriptService/Bombs.server.lua'
    victimClient = 'src/StarterPlayer/StarterPlayerScripts/GrappleVictim.client.lua'
    bombClient = 'src/StarterPlayer/StarterPlayerScripts/BombClient.client.lua'
    capsules = 'src/ServerScriptService/Capsules.server.lua'
    capsulePrompts = 'src/StarterPlayer/StarterPlayerScripts/CapsulePrompts.client.lua'
    capsuleTests = 'tests/capsules.luau'
    rigRespawn = 'src/ServerScriptService/RigRespawn.server.lua'
    rigRespawnTests = 'tests/rigrespawn.luau'
    killCredit = 'src/ReplicatedStorage/Modules/KillCredit.lua'
    killTests = 'tests/kills.luau'
    hourly = 'src/ReplicatedStorage/Modules/HourlyRewards.lua'
    hourlyTests = 'tests/hourly.luau'
}
$bundle = 'local sources = {}' + [Environment]::NewLine
foreach ($key in $sources.Keys) {
    $source = [IO.File]::ReadAllText((Join-Path $projectRoot $sources[$key]))
    $bundle += 'sources.' + $key + ' = [====[' + $source + ']====]' + [Environment]::NewLine
}
$harness = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'regression.luau'))
$bundle += 'local test = (function()' + [Environment]::NewLine + $harness + [Environment]::NewLine + 'end)()' + [Environment]::NewLine + 'test(sources)'
$tempFile = Join-Path ([IO.Path]::GetTempPath()) ('grapple-regression-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [IO.File]::WriteAllText($tempFile, $bundle, [Text.UTF8Encoding]::new($false))
    & $LuauPath $tempFile
    if ($LASTEXITCODE -ne 0) { throw 'Grapple regression tests failed.' }
} finally {
    Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
}

$adminSources = @{
    adminList = 'src/ServerScriptService/AdminList.lua'
    admin = 'src/ServerScriptService/Admin.server.lua'
    noclip = 'src/ReplicatedStorage/Modules/AdminNoclipMotion.lua'
}
$adminBundle = 'local sources = {}' + [Environment]::NewLine
foreach ($key in $adminSources.Keys) {
    $source = [IO.File]::ReadAllText((Join-Path $projectRoot $adminSources[$key]))
    $adminBundle += 'sources.' + $key + ' = [====[' + $source + ']====]' + [Environment]::NewLine
}
$adminHarness = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'admin.luau'))
$adminBundle += 'local test = (function()' + [Environment]::NewLine + $adminHarness + [Environment]::NewLine + 'end)()' + [Environment]::NewLine + 'test(sources)'
$adminFile = Join-Path ([IO.Path]::GetTempPath()) ('grapple-admin-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [IO.File]::WriteAllText($adminFile, $adminBundle, [Text.UTF8Encoding]::new($false))
    & $LuauPath $adminFile
    if ($LASTEXITCODE -ne 0) { throw 'Grapple admin tests failed.' }
} finally {
    Remove-Item -LiteralPath $adminFile -ErrorAction SilentlyContinue
}
