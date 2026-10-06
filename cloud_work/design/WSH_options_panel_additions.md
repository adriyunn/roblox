Written by Cloud (session roblox-9d) on 2026-10-06 without access to the project files;
every line number, key name and existing-code claim below comes from the team's transcripts and must be checked by Dev2 (OptionsPanel, CameraAF, CameraController) and Dev1 (InputController) against the real files.

# WS-H: options panel additions (camera sensitivity, invert Y, field of view, hold-to-toggle reel)

**Decision.** Four new rows under the existing fishing-sensitivity row, each a number or a bool in a new
`C.Options` config block with its default and range, each read in exactly one place (CameraAF `addLook` for
sensitivity and invert, CameraController for FOV, InputController for hold-to-toggle). Values live as attributes on
the LocalPlayer for this session; SaveData persists them later. FOV applies to the Walk and Aim beats only; every other
beat keeps its own pinned FOV. Whether FOV ships in F1 at all is ruling 1.

## 1. What exists

`Fishing/Client/OptionsPanel.lua` (25,111 / 1827080053 in the README table) with one row, the fishing sensitivity,
driven by the `WSH_FishSensitivity_config.patch.txt` keys in `C.Feedback` (WordAgent, rev 2 after Dev2's review), and
the `OptionsPanel_sandbox_driver.client.lua` throwaway for a Play session. The panel has a row builder for a slider with
a readout and, if the sensitivity row is the only one, probably no toggle yet. New rows reuse the builder; a toggle
builder is the one new widget.

## 2. Config: new block `C.Options` in `Fishing/FishingConfig.lua`

Defaults and ranges together so the panel clamps from config and no number lives in the panel code:

```lua
C.Options = {
	-- camera look (CameraAF.addLook): yaw per px = OrbitBaseDegPerPx x sensitivity; pitch the same x invert sign
	OrbitBaseDegPerPx  = 0.044,                                            -- WSG4b's base, moved here from the CameraAF constant
	MouseSensitivity   = { Default = 1.0, Min = 0.5, Max = 2.0, Step = 0.05 },
	TouchSensitivity   = { Default = 1.0, Min = 0.5, Max = 2.0, Step = 0.05 }, -- row shown only when UserInputService.TouchEnabled
	GamepadSensitivity = { Default = 1.0, Min = 0.5, Max = 2.0, Step = 0.05 }, -- row shown only when UserInputService.GamepadEnabled
	InvertY            = { Default = false },                              -- one switch for every device
	-- camera field of view, Walk and Aim beats only (section 4.2)
	FieldOfViewDeg     = { Default = 70, Min = 60, Max = 90, Step = 1 },
	-- input
	HoldToToggleReel   = { Default = false },                              -- a tap toggles the reel instead of a hold (WSI_touch_gamepad.md section 6)
}
```

Attribute names on the LocalPlayer, one per key, prefix `Opt`: `OptMouseSensitivity`, `OptTouchSensitivity`,
`OptGamepadSensitivity`, `OptInvertY`, `OptFieldOfViewDeg`, `OptHoldToToggleReel`. The existing fishing sensitivity
keeps whatever it uses today; it is not moved in this patch (a later WS-R row can fold it into `C.Options`).

## 3. Where each value is read

| Row | Reader | What changes there |
|---|---|---|
| Mouse/Touch/Gamepad sensitivity | `CameraAF.addLook(dx, dy)` | `local sens = Options.get("MouseSensitivity")` (or the device's, from InputMap's active profile); `yaw += dx * OrbitBaseDegPerPx * sens`. Today's constant 0.044 becomes `C.Options.OrbitBaseDegPerPx x 1.0`, byte-identical output at the default |
| Invert Y | `CameraAF.addLook` | `pitchRate = invert and -1 or 1`; `pitch += dy * OrbitBaseDegPerPx * sens * pitchRate`. Pitch clamps unchanged |
| Field of view | `CameraController` on entering the Walk or Aim beat | `camera.FieldOfView = Options.get("FieldOfViewDeg")` on entering those two beats only. The Caught beat (CaughtCamera, `C.CameraAF.Caught`) and the chase/HookFollow/orbit/Reset beats keep setting their own FOV as they do today; leaving them back to Walk re-applies the option |
| Hold-to-toggle reel | `InputController` (through InputMap when WS-I lands) | the hold handler: when on, a press toggles the reel state; off on any state change out of the reel states and on cancel. The wire is unchanged (the same hold on/off messages) |

`Options` is a tiny client module (`Fishing/Client/Options.lua`, new, 60 lines): `get(key)` returns the attribute or
the config default, clamped to the config range; `set(key, value)` clamps, writes the attribute and fires
`Options.changed(key)`. CameraAF reads on every `addLook` (an attribute read is cheap) or caches on `changed`; Dev2's
call.

## 4. Behaviour rules

4.1 Sensitivity is per device, invert is global. A player who switches from mouse to a controller keeps invert and gets
the controller's sensitivity.

4.2 FOV and the beats. The camera beats pin FOV per beat (the Caught beat frames the fish by the rig's body ratio;
a user FOV there would crop the head again, the R1 seed from CONTEXT). So the option is applied only when the Walk or
Aim beat starts and never while another beat runs. In the Aim beat the aim marker's apparent size changes with FOV; the
marker is a 3D selector so it scales with the world, nothing to do. If the Aim beat's framing (the shoulder, the rod)
looks wrong at 60 or 90 in Studio, the row's range tightens before anything else is done.

4.3 Hold-to-toggle never applies to the hook set: in HookWindow a press is a press. It applies to the reel in
Presenting, Retrieving, Inspected and Hooked.

4.4 Reset to defaults: one button at the bottom of the panel writes every `C.Options` default back.

## 5. Persistence

- Now: the attributes in section 2 on the LocalPlayer. They survive the session, respawns and state changes; they do
  not survive leaving the game. Client-set attributes do not replicate to the server, and nothing on the server needs
  them.
- Later: `cloud_work/src/Fishing/Server/SaveData.lua` (a cloud draft written in parallel; check it is in the
  checkout) owns a per-player save with an `options` sub-table. The client sends the changed key through one
  `SetOption(key, value)` message (new FishingNet name, Dev3's wire gate), the server clamps against `C.Options` again
  and stores; on join the server sends the saved table and the client writes the attributes. Nothing in the panel
  changes for that step; only `Options.set` gains a send.

## 6. The panel rows (in the existing panel's style)

Below the fishing-sensitivity row, same width, same label column, same readout font:

| Row | Control | Readout | Shown when |
|---|---|---|---|
| Camera sensitivity (mouse) | slider 0.5..2.0 step 0.05 | `1.00x` | always |
| Camera sensitivity (touch) | slider | `1.00x` | `UserInputService.TouchEnabled` |
| Camera sensitivity (gamepad) | slider | `1.00x` | `UserInputService.GamepadEnabled` |
| Invert look (up/down) | toggle | `Off` / `On` | always |
| Field of view | slider 60..90 step 1 | `70°` | always (ruling 1 may hide it in F1) |
| Reel: hold or tap to toggle | toggle | `Hold` / `Toggle` | always |
| Reset to defaults | button | | always |

A slider drag writes through `Options.set` live (the camera reacts while the panel is open, so the player can feel the
number); the toggle writes on release.

## 7. PARITY

Reference (R1 lists its settings screen; Dev3 checks the row): a sensitivity and an invert switch are the common ones;
FOV is not a reference control because the reference pins its camera per beat as we do. We: the same two, plus FOV for
Walk/Aim and the hold-to-toggle reel (an accessibility row with no reference equivalent). Difference: ours only; the
camera beats are unchanged.

## 8. Rulings needed (Coordinator)

1. FOV in F1 or R1. Proposal: R1. It is not in the F1 acceptance, it touches CameraController's beat entries, and the
   Aim framing at 60/90 needs a Studio look. The three cheap rows (sensitivity, invert, hold-to-toggle) go in F1 if Dev2
   has the slot, else all four wait.
2. `OrbitBaseDegPerPx` moves from CameraAF's constant into `C.Options` (byte-identical output at 1.0). Confirm.
3. One global invert (proposal) vs per device.
4. The `SetOption` wire message waits for SaveData; no net change in this patch. Confirm.

## 9. Acceptance tests

Offline (`tests/wsa/options_test.luau`, Luau CLI; CameraRigAF is pure enough to replay):
- Sensitivity: 100 px of dx at 1.0 -> 4.4 deg of yaw (the WSG4b base); at 2.0 -> 8.8 deg; at 0.5 -> 2.2 deg.
- Invert: 100 px of dy at invert off -> pitch -4.4 deg (or whatever today's sign is); invert on -> +4.4 deg; the clamp
  still holds at both ends.
- Clamp: `Options.set("MouseSensitivity", 3.0)` reads back 2.0; `set("FieldOfViewDeg", 10)` reads back 60.
- FOV and beats: a beat replay Walk -> Aim -> Flight -> ... -> Caught -> Walk with `FieldOfViewDeg = 90`: FOV is 90 in
  Walk and Aim, the Caught beat's own value in Caught, 90 again back in Walk. Negative control: a mutant that applies
  the option in every beat makes the Caught row FAIL.
- Hold-to-toggle: tap, tap -> on, off; on then a transition to CatchScene -> off; exactly two hold messages.
- Byte identity: with every option at its default, the CameraRigAF replay trace equals the pre-patch trace.
Studio (sandbox, the `OptionsPanel_sandbox_driver` extended): each row moves the camera or the reel as labelled;
Reset returns every readout to its default; the Caught beat looks the same at FOV 60 and 90.

## 10. Who does what

- Dev2: `Fishing/Client/OptionsPanel.lua` (rows, the toggle builder, Reset), `Fishing/Client/Options.lua` (new),
  `Fishing/Client/CameraAF.lua` (`addLook`), `Fishing/Client/CameraController.lua` (Walk/Aim FOV), the sandbox driver,
  `tests/wsa/options_test.luau`.
- Dev1: `Fishing/Client/InputController.lua` hold-to-toggle (or in InputMap under WS-I); reviews the CameraAF change.
- WordAgent: `patches/WSH_FishingConfig_options.patch.txt` (the `C.Options` block), README rows; Dev2 reviews, it is
  his block.
- Dev3: PARITY_CHECKLIST row; the `SetOption` wire gate when SaveData lands.
- Coordinator: section 8.
