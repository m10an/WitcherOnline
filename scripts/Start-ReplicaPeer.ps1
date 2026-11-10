<#
.SYNOPSIS
Simulate a second movement client circling a connected player for a local test.
.EXAMPLE
.\scripts\Start-ReplicaPeer.ps1 -FollowPlayer Developer -DurationSeconds 60
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_]{2,16}$')]
    [string] $Username = 'ReplicaTest',
    [ValidatePattern('^[A-Za-z0-9_]{2,16}$')]
    [string] $FollowPlayer = 'Developer',
    [string] $ServerAddress = '127.0.0.1',
    [ValidateRange(1, 65535)]
    [int] $Port = 40000,
    [ValidateRange(1, 3600)]
    [int] $DurationSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Username -ieq $FollowPlayer) {
    throw 'The test peer needs a different username from the player being followed.'
}
$culture = [Globalization.CultureInfo]::InvariantCulture
$socket = [Net.Sockets.UdpClient]::new()
$clock = [Diagnostics.Stopwatch]::StartNew()
$sequence = 0
$origin = $null
$lastPlayerUpdate = -100.0
$announced = $false

try {
    $socket.Connect($ServerAddress, $Port)
    Write-Host "Following $FollowPlayer as $Username for $DurationSeconds seconds. Enable wo_remastered_start() in the game."
    while ($clock.Elapsed.TotalSeconds -lt $DurationSeconds) {
        # Register before the player starts sending. The hidden area prevents an origin spawn.
        $fields = @('0', '0', '0', '1', '0', '0', 'WO_TestWaiting')
        for ($read = 0; $read -lt 128 -and $socket.Available -gt 0; $read++) {
            [Net.IPEndPoint] $sender = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
            $message = [Text.Encoding]::UTF8.GetString($socket.Receive([ref] $sender))
            $parts = $message.Split([char] 9)
            if ($parts[0] -eq 'ERROR' -or $parts[0] -eq 'KICK') {
                throw "Server rejected test peer: $message"
            }
            if ($parts.Count -ne 11 -or $parts[0] -ne 'MOVE' -or $parts[2] -ine $FollowPlayer) {
                continue
            }
            $origin = @(
                [double]::Parse($parts[4], $culture),
                [double]::Parse($parts[5], $culture),
                [double]::Parse($parts[6], $culture),
                $parts[10]
            )
            $lastPlayerUpdate = $clock.Elapsed.TotalSeconds
        }
        if ($null -ne $origin -and $clock.Elapsed.TotalSeconds - $lastPlayerUpdate -lt 3) {
            $angle = $clock.Elapsed.TotalSeconds * 0.6
            $fields = @(
                ($origin[0] + 3 * [Math]::Cos($angle)).ToString('F4', $culture),
                ($origin[1] + 3 * [Math]::Sin($angle)).ToString('F4', $culture),
                $origin[2].ToString('F4', $culture),
                '1',
                (-$angle * 180 / [Math]::PI).ToString('F4', $culture),
                '1',
                $origin[3]
            )
            if (-not $announced) {
                Write-Host "Received player movement in $($origin[3]). Sending a replica three metres away."
                $announced = $true
            }
        }
        $sequence++
        $packet = [Text.Encoding]::UTF8.GetBytes((@('MOVE', '0', $Username, $sequence.ToString($culture)) + $fields -join [char] 9))
        [void] $socket.Send($packet, $packet.Length)
        Start-Sleep -Milliseconds 50
    }
}
finally {
    $socket.Dispose()
    Write-Host 'Test peer stopped. Its replica should disappear within five seconds of the last update.'
}
