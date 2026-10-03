# Grapple game

Rojo source for the grapple, ragdoll, and HUD systems. Sync this project into your existing Studio place; the gun model and optional sounds remain Studio assets.

The equipped tool must match `GrappleConfig.toolName` (default: `Grapple Gun`). Its `FirePoint` attachment is used when present; otherwise one is created at the Handle. Gun parts are made massless and non-colliding when used.

The server creates the required RemoteEvents and ropes. No prefab GUI or RopeConstraint template is required. The new `GrappleHUD` is created on the client and persists across respawns. The old `StarterGui > Grapple Gun` GUI and its embedded LocalScripts are automatically disabled; you can delete that GUI after syncing. Keep the tool itself. Old calls to `LengthenClient.Init` or `StruggleSystemClient.Init` forward to the new HUD without using their supplied frames.

The RagdollService supports classic Motor6D rigs and upgraded R15 AnimationConstraint rigs. It reuses upgraded avatars' native sockets and creates sockets for classic joints. It enters the Ragdoll state and disables automatic GettingUp until release. Each client enforces the released limb joints for ragdolls it simulates. The old Server/Client/Shared component implementation is unused. A voluntary ragdoll survives release from a grapple.

Player dragging applies a limited horizontal pull to the victim; gravity keeps the body on the ground. The attacker temporarily simulates the victim's ragdoll assemblies, then ownership returns to the victim on release. Connected grapples have no timeout. Release, escape, unequip, death, or leaving still disconnects them. The server validates firing, length requests, and struggle inputs; Roblox client-owned physics is still client-simulated.

The HUD sits at the bottom left. X switches player/wall target mode while the gun is equipped. Mouse and touch firing share a deduplicated input path and are independent of movement. Camera zoom no longer causes valid shots to be rejected.

## Verification

Build with `rojo build default.project.json -o <temporary-path>.rbxlx`.

The regression harness runs the actual config, ragdoll module, tool controller, and grapple server script against mocked Roblox APIs. It covers both player directions, classic/upgraded avatar joints, restoring properties/ownership, grounded pull limits, escape validation, voluntary ragdolls, disconnects, indefinite connections, zoomed-camera shots, duplicate X requests, and mouse/touch firing. It does not simulate Roblox physics or render the HUD.

With the official Luau CLI installed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1 -LuauPath <path-to-luau.exe>
```

In Studio, use a two-player test and check both directions: drag while walking, tap/hold Q and E, click to release, mash Space/click to escape, toggle R before being grappled, and die/reset either character while connected. Repeat using R6 and R15. Confirm that controls recover, limbs bend, and the old GUI stays disabled. Test touch buttons in device emulation too.

Tune drag speed, force, responsiveness, and minimum separation in `GrappleConfig.lua`.
