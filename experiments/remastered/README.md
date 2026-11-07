# Remastered relay probe

This standalone script mod checks whether Remastered can load the Witcher Online native client, send a movement packet to the existing Java relay, and read the echoed packet. It uses the game's area name directly. Use a separate test save for the probe.

1. Install the [Witcher Native Bridge runtime](https://www.nexusmods.com/witcher3/mods/13743?tab=files) for your exact game patch. The Remastered download is labeled 5.01c. Use the ASI loader and plugin locations documented for that runtime.
2. Build the repository's Release x64 client. Deploy `WitcherOnlineClient.asi` using the runtime's ASI loader. Before starting the game, set `ServerIP` to `127.0.0.1` in `bin\WitcherOnline\config.xml` and set the port to match the local Java server.
3. Copy `modWitcherOnlineRemasteredProbe` into the game's `mods` folder. Disable the legacy Witcher Online script package while running this probe so the compiler only sees one set of native declarations.
4. Start the Java server, load a test save, and run `wo_remastered_probe()` in the developer console. Run `wo_remastered_status()` once the server logs your username. A HUD message with the assigned player ID and current area confirms the round trip.

The probe's script imports three functions from the native client. Its other calls come from the Remastered base scripts, so the test setup needs no Custom Player Characters, Chill Out, Shared Imports, or Script Merger. The probe displays the relay result only. The sandbox's remote player rendering, spawn policy, party and world state come after the round trip is verified in-game.
