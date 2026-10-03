param([Parameter(Mandatory = $true)][string]$LuauPath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sources = @{
    config = 'src/ReplicatedStorage/GrappleConfig.lua'
    ragdoll = 'src/ReplicatedStorage/Modules/RagdollService/init.lua'
    server = 'src/ServerScriptService/GrappleHandler.server.lua'
    tool = 'src/ReplicatedStorage/Modules/GrappleToolClient.lua'
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
