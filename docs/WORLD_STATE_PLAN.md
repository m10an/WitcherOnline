# White Orchard shared-world plan

Prepared 2026-11-03 from the local source at `dce3311` and the primary sources linked below. This is a proposed implementation plan, not a claim that the game hooks or world modifications have been verified in-game.

## Recommendation

Start with an empty White Orchard sandbox. Every accepted player loads the same world content, spawns at a configured safe location, and automatically joins one shared party. The Java server owns the world identity, membership, spawn policy, time, and weather. Keep the existing player movement and appearance replication initially.

Make the shared world an explicit server object, separate from the party UI. The current party system follows a player's local state; automatically joining everyone to the first player would inherit that player's save, loading, and disconnection problems. A stable server-owned party can expose the same membership to the UI without making a player the world authority.

The first deliverable is an empty, consistent multiplayer world with reliable joining and recovery. Add one controlled entity only after that works. Full engine simulation, NPC AI, combat authority, persistent characters, and campaign quest synchronization are later work.

## What exists in this checkout

| Evidence | Consequence for this work |
| --- | --- |
| `server/src/WitcherServer.java:531`, `handleMessage()` | A recognized update packet creates a session. There is no explicit versioned join/load/ready exchange. The server can accept a client-requested unused player ID. |
| `server/src/PlayerSession.java` | Stores identity, endpoint, last-seen time, and opaque update chunks. There is no world or authoritative party model. |
| `server/src/WitcherServer.java:799`, `broadcastLoop()` | Cached updates are broadcast to all endpoints every approximately 100 ms; movement is forwarded immediately. New world control messages need their own handling. |
| `local/client.ws:815`, `updateWorldSync()` | Time and weather come from the followed party player. NPCs, quest progress, doors, loot, and general world changes are not replicated. |
| `local/client.ws:1405`, `joinParty()` | Membership is local state referring to another username, rather than a server-owned party ID. A player cannot follow themselves. |
| `local/anno.ws:1199`, `WO_RefreshCompanionHud()` | The existing companion HUD exposes two player slots. One large party needs a separate roster or a limited HUD display. This is a presentation limit, not evidence of a two-member networking limit. |
| `local/anno.ws:18`, `OnSpawned()` | Starts the multiplayer tick on player spawn. World travel also causes lifecycle callbacks, so adding unconditional teleportation here would risk repeated transfers. |
| `local/client.ws:7204`, `mpghosts_teleport()` | Existing same-world teleport and cross-world scheduling calls are useful starting points. The safe White Orchard transform and completion conditions still need measurement. |
| `client/dllmain.cpp:748`, `client/NativeBridge.h`, `local/client.ws:5537` | Accepted packet opcodes and script dispatch are explicit. Server-originated world messages need end-to-end changes in Java, C++, the bridge queue, and WitcherScript. |
| `client/NativeBridge.cpp:76`, `PushInbound()` | Realtime messages can replace pending messages, and a full inbound queue evicts its oldest entry. Join/spawn commands cannot rely on this queue for guaranteed application. |
| `local/client.ws:2994`, `WO_PumpTransport()` | Script transport pumping returns while not in game. Native heartbeats and a resume path must work through loading; bootstrap cannot wait on a script pump that loading prevents. |
| `server/src/WitcherServer.java:50` | Sessions expire after five seconds without updates. Loading must not be treated as an ordinary player disappearance. |

Paths beginning with `local/` above are under `witcher/mods/modWitcherOnline/content/scripts/`.

## Findings from existing implementations

These are architectural references, not compatible replacement servers or proof that their game hooks exist in Witcher 3.

| Implementation | Verified behavior | Application here |
| --- | --- | --- |
| [Skyrim Together architecture](https://wiki.tiltedphoques.com/tilted-online/technical-documentation/overview) and [CharacterService source](https://github.com/tiltedphoques/TiltedEvolution/blob/54b3a858e228dc8807ed65bc3f9ac3c3f81b610d/Code/server/Services/CharacterService.cpp) | Clients simulate owned actors; the server coordinates replication. The inspected source includes actor serialization, ownership transfer, range filtering, and ownership epochs that reject stale claims/releases. | For later NPCs, use server entity IDs and one designated simulation owner, with explicit handoff generations. Owning state does not require Java to run the original game AI. |
| [TES3MP logicHandler](https://github.com/TES3MP/CoreScripts/blob/b0a77a64e6caa0b4f8e1d9ae95d49115461fd107/scripts/logicHandler.lua) and [cell model](https://github.com/TES3MP/CoreScripts/blob/b0a77a64e6caa0b4f8e1d9ae95d49115461fd107/scripts/cell/base.lua) | Server scripts maintain world/cell records, allocate object identities, send stored spawn/deletion/actor data, and choose replacement cell authorities when visitors leave. | Store canonical state independently of currently loaded client actors. A late join or stream reload must receive current state, including removals. |
| [Colyseus state synchronization](https://docs.colyseus.io/state) and [rooms](https://docs.colyseus.io/room) | Rooms contain clients and shared state. Clients receive initial state on joining, then updates; server handlers mutate canonical state. | Use a world instance, baseline snapshot, and revisioned updates. Borrow the model while keeping Java and the existing native integration. |
| [w3m server](https://github.com/momo5502/w3m/blob/7d196df7ba9eed227f38f1c2a9cb1d26d374f785/src/server/server.cpp) | The inspected server validates a protocol identifier, challenges client identity, caches authenticated player states, and periodically broadcasts them. | A Witcher-specific example for explicit protocol/identity boundaries. This source is not a ready-made authoritative NPC world implementation. |
| [Witcher3-Multiplayer README](https://github.com/werasik2aa/Witcher3-Multiplayer/blob/main/README.md) | The author describes NPC-by-ID synchronization as partial and buggy. The local project credits this implementation. | Useful historical reference; its stated NPC status is insufficient to base the new world system on. |

CDPR's [monster encounter guide](https://cdprojektred.atlassian.net/wiki/spaces/W3REDkit/pages/6326170/HOW-TO%2BCreate%2Ba%2Bmonster%2Bencounter) distinguishes area-based encounters from quest communities, and describes spawning when a player enters an encounter area. Its [encounter debugging guide](https://cdprojektred.atlassian.net/wiki/spaces/W3REDkit/pages/43810840/HOW-TO%2BFind%2Band%2Bdebug%2Bencounters) explains how to locate spawn trees, including prologue content, and inspect spawned counts. Therefore, a one-time deletion of visible NPCs would not establish an empty world. The exact suppression mechanism remains to be proven.

## Required preparation: prove the empty world first

1. Establish a reproducible development build and two-client test setup. Confirm supported game version, native bridge runtime, mod dependencies, JDK 17+, Visual Studio v143/Windows SDK, and asset packaging tools. `java`, `javac`, and `msbuild` were not found on this session's PATH; that does not establish whether they are installed elsewhere. The client project currently has a hard-coded GOG output directory; use a configurable staging/deploy path. The asset rebuild pipeline and bridge runtime implementation are not supplied by this checkout.
2. Create a dedicated multiplayer test-save/profile with a documented quest/fact baseline. Retain original personal saves separately. Teleporting two arbitrary saves to the same coordinates does not make their world layers, doors, or quest-driven actors agree. A common baseline is a development control; the sandbox must also prevent campaign systems from changing it while connected.
3. Inspect White Orchard in REDkit. Inventory encounters, quest communities, scripted spawners, wildlife, mounts, placed actors, quest triggers, and mutable interactables. Preserve terrain, buildings, collision, navigation, lighting, and other static scenery.
4. Prove a packaged sandbox override of the original summer White Orchard: suppress population sources and campaign activation in scope, then handle already-loaded/saved actors. Do not assume a particular disabling API exists. Keep a runtime audit of disallowed actors as a backstop, not a per-frame destroy-all-NPC loop. Remote players are themselves `CNewNPC` subclasses and must be explicitly preserved.
5. Verify suppression after moving across streaming boundaries, waiting through day/night changes, reloading the test save, and reconnecting. Count disallowed actors and record their source when any appear. Test in the packaged game as well as REDkit.

Decision gate: proceed with the original White Orchard only if this is reproducible. If campaign/spawn isolation cannot be achieved reliably, use a dedicated sandbox world based on White Orchard's environment, with a distinct resource path. Review asset reuse, cooking, travel, and navigation in that spike before choosing the fallback. The server protocol uses a world resource ID plus content revision so either approach fits.

The scope is zero unmanaged gameplay actors and zero enabled unmanaged world mutations. Doors, containers, destructibles, pickups, boats, horses, and quest triggers need to be frozen, disabled, or explicitly supported; removing enemies alone does not remove these sources of divergence. Cosmetic local effects can remain if they do not affect gameplay.

## First milestone: empty shared White Orchard

### Server state and authority

Keep one Java process and add a small typed model:

```text
WorldInstance
  worldInstanceId, serverEpoch, worldResourceId, contentRevision
  worldRevision, spawnPolicy, timePolicy, weatherPolicy
  members: playerId -> session/readiness state
  sharedParty: partyId + member player IDs
  entities: empty registry reserved for the next milestone

PlayerSession
  server-assigned playerId, session token, connection generation
  worldInstanceId, partyId, join phase, last native heartbeat
  last acknowledged control sequence / applied world revision
```

Use one owner thread/event loop for world mutations; receive and cleanup workers enqueue commands, and broadcasters consume immutable snapshots. A concurrent map alone does not make multi-field world transitions atomic. Start with a 10 Hz world/control update budget, independently of movement forwarding, and measure before changing rates.

| State | Initial authority |
| --- | --- |
| World/resource/content version, membership, admission, spawn and return point | Server |
| Party membership | Server; all accepted players assigned automatically |
| Time/weather | Server; fixed noon and one verified weather preset initially; admin changes produce versioned state |
| Player transforms and appearance | Existing client replication, gated by readiness and checked for valid values and allowed area |
| NPC AI, damage, loot, economy and campaign progress | Outside this milestone; related world interactions remain disabled |

The server keeps its world when the first player or all players leave. A process restart resets this development world to configuration and produces a new `serverEpoch`; old sessions and packets cannot resurrect earlier state. Persistent storage is unnecessary until there is state worth preserving.

### Join and travel contract

Suggested logical messages and ordering; field encoding is specified during implementation:

```mermaid
sequenceDiagram
    participant C as Client/native + scripts
    participant S as Java world server
    C->>S: HELLO(protocolVersion, contentRevision, joinNonce)
    S-->>C: WELCOME(playerId, sessionToken, serverEpoch, world/party IDs)
    S-->>C: PREPARE_WORLD(loadId, resource, spawn transform, policy)
    Note over C: Load world, enforce sandbox, wait for usable player
    C->>S: WORLD_LOADED(loadId, resource, contentRevision)
    S-->>C: WORLD_SNAPSHOT(snapshotId, revision R, world + roster)
    Note over C: Apply baseline and spawn; acknowledge after application
    C->>S: READY(loadId, snapshotId, appliedRevision R)
    S-->>C: ENTER_WORLD + changes after R
    Note over C,S: Publish movement only after ENTER_WORLD
```

Assign party membership during admission, and publish active presence only after readiness. The roster may distinguish loading members from active members. Bootstrap messages must reach scripts before ordinary in-game pumping, using an explicit load/resume hook. Teleport only once per load/admission operation, not on every `OnSpawned` callback or heartbeat. Use nearby tested spawn offsets so simultaneous arrivals do not overlap.

During snapshot creation/application, queue changes after revision R and replay them in order before activating the client; if that buffer expires or overflows, send a newer snapshot. Reject older revisions and wrong epochs/generations. Readiness is tied to a specific load and snapshot, so an acknowledgment from an earlier transfer cannot activate a later one.

Use a native heartbeat independent of script/gameplay updates. For an initial private test, propose one heartbeat per second, a configurable 30-second heartbeat timeout, and a separate configurable 120-second world-load deadline. Validate these against actual load times. On resuming after a pause or game reload, revalidate the world and resynchronize before publishing movement. Fresh admission or reconnect returns to the configured spawn for this milestone.

Remain inside the allowed White Orchard area; gate fast travel/world changes and return a ready client that exits the allowed world or boundary to a safe point. During connection loss, suspend shared interactions and presence. Recovery performs a fresh baseline exchange. End the sandbox session through an explicit path that reloads the dedicated save/profile, so session overrides do not silently become campaign state.

### Transport and validation

Keep the current UDP path for movement. Add a small reliable control channel over the existing connection for admission, world preparation, baseline, membership, and activation: message IDs, acknowledgments, bounded retransmission/backoff, duplicate suppression, and explicit timeout/resync. Keep unrelated control operations from being blocked indefinitely by a missing old packet. This is not a general transport rewrite.

Receipt by C++ is not proof that WitcherScript applied a command. Use application acknowledgments for the load/snapshot/ready transitions. Give control messages a bounded queue that never silently coalesces or evicts unapplied commands; on overflow, fail/resync the session. Movement can keep latest-value replacement.

Version the protocol and content contract. Admit only compatible clients to this mode; legacy update packets must not bypass admission. Issue player IDs and unpredictable session tokens on the server, validate every accepted packet against the current session/generation, and reject clients attempting to set server-owned world or membership fields. Tokens bind sessions; they are not a substitute for a future account identity system.

Define packet size/count/rate limits, field schemas, numeric bounds and finite-coordinate checks, sequence wrap behavior, and rejection reasons. Keep datagrams within a conservative configured budget (start around 1200 bytes total application datagram size and verify on the target network). Chunk snapshots with IDs, bounded sizes, reassembly timeouts, and a content checksum; never rely on one large UDP packet or unbounded buffering. Carry initial player presentation data through versioned roster/baseline chunks, then reuse existing player presentation updates after activation.

### Automatic party behavior

Create one stable party ID owned by `WorldInstance`, and assign every admitted player to it, including the first player. Derive the party list/UI from replicated server membership. Do not create a fake server player or pass a nonexistent username to the existing `joinParty()` path.

Bypass the old player-following time/weather and dialogue behavior in this sandbox mode, and gate manual join/leave-party controls. There is no player leader whose departure resets the world. Keep the existing two-slot companion display as a limited view or hide it in favor of a simple roster/count; the server's membership has no corresponding two-slot limit.

### Acceptance criteria

- Two clients beginning in different regions arrive at the configured summer White Orchard spawn, see each other, and report identical world/content IDs and party membership.
- A third, late-joining client receives the current roster, time, weather, and world revision; it never changes the server to its local save's settings.
- Leaving and re-entering streamed areas, reloading, and reconnecting do not reintroduce unmanaged gameplay actors or enable excluded interactions. Record zero disallowed actors throughout a documented route and dwell test.
- Native heartbeats survive loading; no movement or shared actions are published until readiness. A failed world load ends with a clear error and no ghost session.
- The first player disconnects; the remaining players' membership, time, and weather continue unchanged. Emptying the server does not reset its running world instance.
- Lost, duplicated, reordered, and delayed control packets cannot cause repeated teleports, duplicate membership, premature activation, or stale state application. A bounded retry failure gives a reconnect/resync outcome.
- A server restart rejects old packets/sessions and makes returning clients load a new baseline. Incompatible protocol/content and unauthorized control requests are rejected.
- Attempts to leave the supported region recover predictably. Disallowed gameplay NPC cleanup never removes remote-player ghosts.

Automate protocol/session tests with synthetic UDP clients and a packet-loss/reordering harness. Use in-game tests for world isolation, script compilation, transfer completion, and actual rendering. Log join phases, retries, load times, world revisions, invalid messages, active sessions, bandwidth, and disallowed actor counts so failures are diagnosable.

## Implementation order and reviewable increments

| Step | Work | Completion gate |
| --- | --- | --- |
| 0 | Build/deploy instructions, two-client baseline, REDkit isolation spike, spawn measurement | Packaged empty White Orchard proven; world resource and content version selected |
| 1 | Java `WorldInstance`, server-owned party, admission/session phases, versioned control codec and native bridge dispatch | Synthetic clients join, time out, retry and reconnect correctly; incompatible clients rejected |
| 2 | WitcherScript load/bootstrap, population policy, safe spawn, ready handshake and snapshot application | Two real clients enter the same empty world without loops or load deadlocks |
| 3 | Server time/weather application, roster, party UI adapter, travel guards and recovery | Third-client late join, first-player disconnect, loss/reorder and restart criteria pass |
| 4 | First shared static entity, after the empty-world milestone is accepted | One interaction is consistent for existing clients, late joiners and stream reloads |

Likely new Java classes are `WorldInstance`, `WorldState`, `SharedParty`, a control protocol codec, and a world/session coordinator. Extend `PlayerSession` and route accepted commands from `WitcherServer`. On the client, change `dllmain.cpp` packet handling, `NativeBridge.h/.cpp` dispatch and queue policy, and the `client.ws`/`anno.ws` lifecycle and party integration. Keep world-loading and sandbox policy in a small dedicated script module rather than adding all of it to the existing large `client.ws`. Track the cooked sandbox content and its authoring/build instructions alongside the code.

## Content roadmap after the first milestone

1. **One static object:** use a server-spawned test prop or a custom door with a single shared state. Add a stable server entity ID, template/content ID, world ID, transform, revision, and explicit spawn/despawn state. Clients request an interaction; the server validates it and publishes the result. Test duplicate requests, late joining and stream reload before adding rewards.
2. **One inert NPC:** replicate lifecycle and appearance with AI disabled. Map the same server entity ID to different local handles; prevent vanilla respawning and replica self-simulation.
3. **One moving NPC:** designate one loaded, ready client as simulation owner while the server retains canonical identity/lifecycle. Add ownership epochs and validated owner reports. On owner loss, freeze safely until another eligible client acknowledges ownership; if none is loaded, retain dormant canonical state. This is client-simulated AI, with its trust limits documented.
4. **One enemy encounter:** choose and implement damage authority, target selection, death, respawn and reward rules explicitly. Animation replication is insufficient to establish shared combat. Add persistent identity/storage and idempotent reward transactions before durable loot/economy is enabled.
5. **More content and population:** scope entity replication to loaded regions/cells and proximity, use deltas and budgets, measure bandwidth/server/client cost, then increase counts. The current all-to-all player broadcasting grows roughly with the square of player count; one party alone does not solve scale. Set a measured player/entity cap before public expansion.

The immediate next action is step 0: prove a reproducibly empty, packaged White Orchard and a safe multiplayer entry point. That resolves the largest unknown before committing to the cross-language server/client work.
