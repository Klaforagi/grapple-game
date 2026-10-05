# Grapple game

Rojo source for the grapple, ragdoll, and HUD systems. Sync this project into your existing Studio place; the gun model and optional sounds remain Studio assets.

The equipped tool must match `GrappleConfig.toolName` (default: `Grapple Gun`). Its `FirePoint` attachment is used when present; otherwise one is created at the Handle. Gun parts are made massless and non-colliding when used.

The server creates the required RemoteEvents and ropes. No prefab GUI or RopeConstraint template is required. The new `GrappleHUD` is created on the client and persists across respawns. The old `StarterGui > Grapple Gun` GUI and its embedded LocalScripts are automatically disabled; you can delete that GUI after syncing. Keep the tool itself. Old calls to `LengthenClient.Init` or `StruggleSystemClient.Init` forward to the new HUD without using their supplied frames.

The RagdollService supports classic Motor6D rigs and upgraded R15 AnimationConstraint rigs. It reuses upgraded avatars' native sockets and creates sockets for classic joints. It enters the passive Physics state, disables humanoid state evaluation and automatic GettingUp, and restores them on recovery. Each client enforces the released limb joints without writing assembly velocities every frame. The separate camera anchor smooths the local view. The old Server/Client/Shared component implementation is unused. A voluntary ragdoll survives release from a grapple.

Player grapples use a real RopeConstraint between both HumanoidRootParts. Q/E changes its maximum separation directly; the winch is disabled. The server explicitly assigns the victim's root and ragdoll assemblies to the grappler. `GrappleVictim.client.lua` receives `GrappleVictimState`, disables the victim's PlayerModule controls, clears movement/jump input, and enters Physics. Replicated attributes also cover initialization and streaming order. The HUD's independent struggle inputs remain available on keyboard and touch.

On release, the server destroys the rope immediately and keeps the current simulator and victim control lock for `playerOwnershipReleaseDelay` (default 0.2 seconds). It then returns ownership to the victim before releasing the lock. Release preserves airborne position and velocity; it does not snap to a server pose or zero momentum. Character/session IDs prevent old release callbacks and remote messages from interfering with recapture or respawn. Death, removal, voluntary ragdolls, and bomb stuns retain their own cleanup rules. The settling delay is tunable, not an acknowledgement that every client received a final physics packet.

Connected grapples have no timeout. Release, escape, unequip, death, or leaving disconnects them. The server validates firing, length requests, and struggle inputs; client-owned physics remains client-simulated. Giving the grappler ownership removes the victim's connection from the simulation path, but cannot remove the grappler's own latency or observer interpolation.

The HUD sits at the bottom left. X switches player/wall target mode while the gun is equipped. Mouse and touch firing share a deduplicated input path and are independent of movement. Camera zoom no longer causes valid shots to be rejected.

The grapple code leaves number-key handling to Roblox's normal Backpack controls; actually unequipping the gun releases the grapple. Automatically ragdolled victims resume Roblox's normal GettingUp behavior after the ownership handoff. Character collision groups prevent inter-player/self collisions while the body retains floor collisions; the invisible root stays non-colliding and gun decorations are massless.

Mouse aiming uses raw viewport coordinates without adding the top-bar inset. Ragdoll recovery is immediate when you are not grappled; the 0.5-second cooldown starts when you get up and prevents re-entering ragdoll during that window.

## Verification

Build with `rojo build default.project.json -o <temporary-path>.rbxlx`.

The regression harness runs the actual config, ragdoll module, tool controller, victim LocalScript, and server scripts against mocked Roblox APIs. It covers both player directions, classic/upgraded avatar joints, delayed ownership restoration, momentum preservation, recapture/stale events, control restoration and respawn, physical rope setup, escape validation, voluntary ragdolls, disconnects, indefinite connections, zoomed-camera shots, duplicate X requests, mouse/touch firing, and bomb behavior. It does not simulate Roblox physics or render the HUD.

With the official Luau CLI installed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1 -LuauPath <path-to-luau.exe>
```

In Studio, use a three-player test (grappler, victim, observer) and inspect the server view too. Enable Network owners visualization: the connected mechanism should use the grappler's color; the victim should return to its own color after detaching and settling. Add simulated replication lag and repeat with touch emulation, R6, and R15. Drag while walking/jumping, tap/hold Q and E, release in mid-air, immediately recapture, struggle free, toggle R before capture, trigger a bomb stun, and die/reset/disconnect either participant. Confirm that observers see continuous movement, airborne release keeps momentum, floor collisions work, struggle buttons remain usable, and victim movement returns after release/respawn.

Tune rope length increments, minimum separation, and `playerOwnershipReleaseDelay` in `GrappleConfig.lua`. Sync all changed source files through Rojo; the RemoteEvent and victim LocalScript need no manual Studio setup.
