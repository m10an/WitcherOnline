# Remastered movement client

This standalone script mod shares position, heading and movement speed through the existing Java relay. It renders other players as base-game Geralt NPC replicas. It uses Remastered area names and Witcher Native Bridge API 2. Use a separate test save.

1. Install the [Witcher Native Bridge runtime](https://www.nexusmods.com/witcher3/mods/13743?tab=files) for your exact game patch. The Remastered download is labeled 5.01c. Use the ASI loader and plugin locations documented for that runtime.
2. Build the repository's Release x64 client. Deploy `WitcherOnlineClient.asi` using the runtime's ASI loader. Before starting the game, set `ServerIP` to `127.0.0.1` in `bin\WitcherOnline\config.xml` and set the port to match the local Java server.
3. Copy `modWitcherOnlineRemasteredProbe` into the game's `mods` folder. Disable the legacy Witcher Online script package while running this probe so the compiler only sees one set of native declarations.
4. Start the Java server and load a test save. Run `wo_remastered_start()` in the developer console on each client, using a different username on each machine. Both clients must use the Remastered script package. Set `ServerIP` on the second machine to the server's LAN address.

Run `wo_remastered_status()` to see the visible replica count and the age of the last relay reply. Run `wo_remastered_stop()` to stop sending movement and remove all local replicas. Starting is manual after a new save is loaded. World travel clears replicas and resumes the timer when the local player spawns.

Movement is sent and applied approximately 20 times per second. Positions are smoothed, with large changes snapping to the new location. Replicas render within 150 metres in the same area, have no physical collision, and use nonpersistent entities. The client tracks at most 64 remote players and removes records after five seconds without fresh movement. Duplicate and older movement sequences are ignored, including at sequence rollover. Player appearance customization, combat, and the shared White Orchard spawn policy are separate milestones.

To test with one game installation, enable movement sharing, then run this from the repository root in another terminal:

```powershell
.\scripts\Start-ReplicaPeer.cmd -FollowPlayer Developer -DurationSeconds 60
```

The simulated `ReplicaTest` player follows a three-metre circle around the connected `Developer` player. Set `-FollowPlayer` to the username in your game configuration. When the peer exits, its replica expires after five seconds. This exercises the real relay and rendering path. A second game client is still needed to validate player-controlled movement in both directions.

The original `wo_remastered_probe()` command remains available for a single-packet relay check while movement sharing is stopped. The package uses three native imports and base-game scripts and assets. Its setup consists of this mod, the API 2 native client, and the matching bridge runtime with its ASI loader.
