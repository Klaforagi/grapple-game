# Grapple game

Rojo source for the grapple, ragdoll, and HUD systems. Sync this project into your existing Studio place; the gun model and optional sounds remain Studio assets.

The equipped tool must match `GrappleConfig.toolName` (default: `Grapple Gun`). Its `FirePoint` attachment is used when present; otherwise one is created at the Handle. Gun parts are made massless and non-colliding when used.

Bombs detonate 3.5 seconds after throwing and play `ReplicatedStorage/Sounds/Explode` at the blast position. The held sphere is hidden and disabled until the six-second throw cooldown finishes, including when unequipped. Projectiles permanently ignore the thrower's character, accessories, and equipment for their lifetime (including parts added or reparented after throwing). Other tools and non-colliding effects/camera parts are not sticky surfaces.

`bombLaunchHeight = 75` and `bombLaunchDistance = 85` specify the target flight in studs. Edge hits taper to 70% of those values; directly underneath launches vertically. These are unobstructed ballistic targets measured above/from the impact position, so walls, ceilings, ropes, and collisions can change the actual flight. Blasts remove their sticky weld, detach grapple ropes, ragdoll the target, then apply one mass-scaled correction impulse per assembly on the next Heartbeat. The correction replaces existing launch velocity rather than stacking it. Ownership remains on the server briefly through the launch. Bomb-created ragdolls automatically recover after five seconds; repeated hits restart stun, and voluntary ragdolls remain voluntary.

The server creates the required RemoteEvents and ropes. No prefab GUI or RopeConstraint template is required. The new `GrappleHUD` is created on the client and persists across respawns. The old `StarterGui > Grapple Gun` GUI and its embedded LocalScripts are automatically disabled; you can delete that GUI after syncing. Keep the tool itself. Old calls to `LengthenClient.Init` or `StruggleSystemClient.Init` forward to the new HUD without using their supplied frames.

The RagdollService supports classic Motor6D rigs and upgraded R15 AnimationConstraint rigs. It reuses upgraded avatars' native sockets and creates sockets for classic joints. While ragdolled, the animated root joint is disabled and a fixed weld holds the HumanoidRootPart to the torso. Physical attachment frames use C0/C1 rather than the non-replicated animation Transform. Body parts retain mass, the root receives the highest root priority, and passive sockets receive light friction to help them settle. Original joint, mass, priority, and native socket friction settings return on recovery.

The server alone changes joint and collision layout. Clients suppress humanoid state evaluation and automatic GettingUp, enter Physics, and manage the local camera/controls; they do not rewrite joints, collision flags, or assembly velocities. The separate camera anchor filters resting motion with a 0.75-stud deadzone and stays within 1.25 studs of the root during movement, so fast falls cannot outrun camera smoothing. This affects only the camera subject, not fall speed or physics. The old Server/Client/Shared component implementation is unused. A voluntary ragdoll survives release from a grapple.

Player grapples use a real RopeConstraint between both HumanoidRootParts. Q/E changes its maximum separation directly; the winch is disabled. The server explicitly assigns the victim's root and ragdoll assemblies to the grappler. `GrappleVictim.client.lua` receives `GrappleVictimState`, disables the victim's PlayerModule controls, clears movement/jump input, and enters Physics. Replicated attributes also cover initialization and streaming order. The HUD's independent struggle inputs remain available on keyboard and touch.

Ragdoll ownership is checked on the next Heartbeat after joints change, then every 0.25 seconds while active. Only automatic or incorrectly owned assemblies are reassigned. Grappled victims stay with the grappler through the release delay; standalone player ragdolls stay with their own player, and NPC ragdolls stay on the server. Bomb impulses reserve server ownership for 0.3 seconds after launch, which the same ownership check honors. No behavior depends on player join order.

On release, the server destroys the rope immediately and keeps the current simulator and victim control lock for `playerOwnershipReleaseDelay` (default 0.2 seconds). It then returns ownership to the victim before releasing the lock. Release preserves airborne position and velocity; it does not snap to a server pose or zero momentum. Character/session IDs prevent old release callbacks and remote messages from interfering with recapture or respawn. Death, removal, voluntary ragdolls, and bomb stuns retain their own cleanup rules. The settling delay is tunable, not an acknowledgement that every client received a final physics packet.

Connected grapples have no timeout. Release, escape, unequip, death, or leaving disconnects them. The server validates firing, length requests, and struggle inputs; client-owned physics remains client-simulated. Giving the grappler ownership removes the victim's connection from the simulation path, but cannot remove the grappler's own latency or observer interpolation.

The HUD sits at the bottom left. X switches player/wall target mode while the gun is equipped. Mouse and touch firing share a deduplicated input path and are independent of movement. Camera zoom no longer causes valid shots to be rejected.

The grapple code leaves number-key handling to Roblox's normal Backpack controls; actually unequipping the gun releases the grapple. Automatically ragdolled victims resume Roblox's normal GettingUp behavior after the ownership handoff. Player collision is enabled by default, including while grappling and ragdolled. Set `playerCollisionsEnabled = false` in `GrappleConfig.lua` to restore pass-through for comparison, then restart the test. Per-character NoCollisionConstraints prevent a body's own limbs from colliding with each other. Bodies retain floor collisions; the invisible root stays non-colliding while alive and gun decorations are massless. Collision groups are configured by the server script; no manual Studio setup is needed.

Mouse aiming uses raw viewport coordinates without adding the top-bar inset. Ragdoll recovery is immediate when you are not grappled; the 0.5-second cooldown starts when you get up and prevents re-entering ragdoll during that window.

## Verification

Build with `rojo build default.project.json -o <temporary-path>.rbxlx`.

The regression harness runs the actual config, ragdoll module, tool controller, victim LocalScript, and server scripts against mocked Roblox APIs. It covers all 12 directed pairings of four players, delayed assembly splits and ownership drift, stable ownership without repeated writes, classic/upgraded rigid root replacement, observer isolation, delayed ownership restoration, momentum preservation, recapture/stale events, control restoration and respawn, physical rope setup, escape validation, voluntary ragdolls, disconnects, indefinite connections, zoomed-camera shots, duplicate X requests, mouse/touch firing, and bomb behavior. It does not simulate Roblox physics or render the HUD.

With the official Luau CLI installed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1 -LuauPath <path-to-luau.exe>
```

In Studio, use a three-player test (grappler, victim, observer) and inspect the server view too. Enable Network owners visualization: the connected mechanism should use the grappler's color; the victim should return to its own color after detaching and settling. Add simulated replication lag and repeat with touch emulation, R6, and R15. Drag while walking/jumping, tap/hold Q and E, release in mid-air, immediately recapture, struggle free, toggle R before capture, trigger a bomb stun, and die/reset/disconnect either participant. Confirm that observers see continuous movement, airborne release keeps momentum, floor collisions work, struggle buttons remain usable, and victim movement returns after release/respawn.

Tune rope length increments, minimum separation, and `playerOwnershipReleaseDelay` in `GrappleConfig.lua`. Sync all changed source files through Rojo; the RemoteEvent and victim LocalScript need no manual Studio setup.

For the Player1-only replication symptom, repeat with Player3 grappling Player1 and Player4 grappling Player2. In the server view, inspect the victim Humanoid's `RagdollExpectedOwner` (the intended player's UserId; 0 means server), `RagdollOwnershipRepairs` (cumulative corrected assembly assignments), and `RagdollOwnershipUnassigned` (assemblies that could not be assigned, e.g. anchored parts). Repairs should settle after the joint transition. Continuous growth suggests another script or repeated topology changes are undoing ownership. Compare Network owners visualization for the root **and limbs**, not only the HumanoidRootPart. Stop/restart the Studio test after syncing so every client loads the new module.
