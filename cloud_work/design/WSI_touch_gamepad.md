Written by Cloud (session roblox-9d) on 2026-10-06 without access to the project files;
every line number, key name and existing-code claim below comes from the team's transcripts and must be checked by Dev1 (InputController, CastGesture) and Dev2 (camera, AimMarker, OptionsPanel) against the real files.

# WS-I: touch and gamepad controls for the whole F1 loop

Status: DRAFT, FOR RULING (section 9). Net and state impact: none on the wire, no new state or action; the only
device-related value anywhere is an optional analytics attribute on the LocalPlayer (section 7).

**Decision.** One device layer, `Fishing/Client/InputMap.lua`, sits between raw input and the functions InputController
already calls for the mouse. It turns a thumbstick, a drag, a trigger or a gyro sample into the same calls the mouse
and W/A/S/D make today, in the same units. CastGesture, StateRules, FishingNet, RequestGuard, FishJudge and the
server do not learn that devices exist. Touch and gamepad are not in the F1 acceptance; this note is written so the
seam goes in with Dev1's #4 fix (the unclamped `lineM`) and the controls themselves are built in R1 unless the
Coordinator rules otherwise (ruling 1).

## 1. What F1 has today (mouse + keyboard) and what must stay true

- Mouse movement is the rod. CastGesture consumes a per-frame 2D delta stream (px per frame) and decides the cast
  with its own windows: AimEnd must precede the flick by less than 0.2 s, the velocity decays, the power comes from the
  flick. `tests/wsa/gesture_test.luau` pins that behaviour and its frame-rate independence.
- W/A/S/D turn the aim in the Aim beat (the WSA2b aim-turn gate: the keys turn instead of walking while Aiming).
- Mouse orbits the camera in the orbit beats at about 0.044 deg/px (CameraAF `addLook`).
- Mouse button 1: a press is the hook set in HookWindow; a hold is the reel/retrieve in Presenting, Retrieving,
  Inspected and Hooked; a click is catch-done in CatchScene.
- Cancel/reset and the Aim entry use InputController's current bindings (the transcripts do not name the keys; Dev1
  fills those two cells in the table below).
- Everything the server sees is a FishingNet v2 message checked by StateRules, counted by RequestGuard, timed by
  LatencyBudget. **That stays the only thing the server sees.**

## 2. The device layer

`InputMap` owns three profiles (`MouseKeyboard`, `Touch`, `Gamepad`) and the active one follows
`UserInputService:GetLastInputType()` through `LastInputTypeChanged` (a player who plugs in a controller mid-fight
switches on the first stick move; the hold state carries over). Each profile emits the same intents:

| Intent | Payload | Today's mouse/keyboard source | Who consumes it |
|---|---|---|---|
| `walk` | handled by Roblox's PlayerModule | W/A/S/D in Walking and Holding | ControlModule (unchanged) |
| `aimTurn` | yaw rate, pitch rate (deg/s) | W/A/S/D in Aiming through the aim-turn gate | InputController's aim turn |
| `rodDelta` | dx, dy (mouse-px equivalent), dt | mouse delta in Aiming | CastGesture's sample feed |
| `steer` | x in -1..1 | mouse X in Flight | InputController's steer |
| `orbit` | dx, dy (mouse-px equivalent) | mouse delta in the orbit beats | CameraAF `addLook` |
| `press` | client time stamp | mouse 1 InputBegan | InputController's press (HookWindow) |
| `hold` | on/off | mouse 1 down/up | InputController's reel hold |
| `cancel` | none | today's cancel key | InputController's cancel/reset |
| `catchDone` | none | mouse 1 click in CatchScene | `InputController.sendCatchDone()` (exists since W4) |
| `aimEnter` | none | today's Aim binding | InputController's Aim entry |

`rodDelta` and `orbit` are in **mouse-px equivalent** so CastGesture and CameraAF keep their current numbers; each
profile converts with one gain. The gains are config, block `C.Input` (new), WordAgent writes the patch doc,
Dev1 reviews:

```lua
C.Input = {
	-- mouse (today's values, now named)
	MouseOrbitDegPerPx = 0.044,     -- CameraAF addLook base (WSG4b); x sensitivity from the options panel
	-- touch (phones and tablets)
	TouchRodGainPxPerPx = 2.0,      -- a thumb drag is about half the length of a mouse flick for the same intent
	TouchOrbitDegPerPx = 0.09,      -- about 2x mouse; a 600 px swipe turns 54 deg
	TouchHookTapAnywhere = true,    -- a tap on the rod region is a press in HookWindow (ruling 2)
	TouchButtonPx = 84,             -- button side at 1x; the options panel scales 0.8..1.4
	GyroCastEnabled = false,        -- phones only; needs UserInputService.GyroscopeEnabled
	GyroCastGainPxPerDeg = 6.0,     -- 1 deg/frame of forward pitch rate = 6 px of mouse
	-- gamepad
	GamepadDeadzone = 0.15,
	GamepadStickCurve = 2.0,        -- response exponent after the deadzone
	GamepadAimDegPerS = 60,         -- left stick at full deflection in Aiming; matches the W/A/S/D turn rate (Dev1: same constant)
	GamepadOrbitDegPerS = 120,      -- right stick at full deflection in the orbit beats
	GamepadRodGainPxPerUnit = 150,  -- 1.0 of right-stick Y travel = 150 px of mouse; a back-to-forward swing = 300 px
	GamepadTriggerPressAt = 0.25,   -- R2 Position.Z at which a press registers (section 4.3)
	GamepadGyroEnabled = false,     -- stub: Roblox has no controller-gyro API (section 4.4)
	-- accessibility
	HoldToToggleReel = false,       -- a tap toggles the reel instead of a hold (section 6)
	LeftHanded = false,             -- mirrors the touch cluster and the walk stick
}
```

Every gain is a client-only number. None of them reaches a net message.

## 3. Touch

Roblox gives the dynamic thumbstick on the left and nothing on the right once CameraController owns the camera
(`CameraType = Scriptable` since WSG1, so the PlayerModule's touch camera does not move it). Our screen is split:

- **Left region** (x < 40% of the viewport): the PlayerModule thumbstick. In Walking and Holding it walks. In Aiming
  InputMap disables the ControlModule (`ControlModule:Disable()`) and reads `Thumbstick1`-style deltas from the same
  stick for `aimTurn` (left/right = yaw, up/down = pitch, at `GamepadAimDegPerS` x deflection; one constant for both
  devices). Re-enabled on leaving the fishing states.
- **Right region** (x >= 40%, outside the buttons): the rod and the camera. In Aiming a one-finger drag is the rod:
  `rodDelta = (dx, dy) x TouchRodGainPxPerPx` per frame from `InputChanged` with `UserInputType.Touch`, so a pull-back
  then a forward flick casts exactly as the mouse does; CastGesture's windows judge it. In the orbit beats the same drag
  is `orbit` at `TouchOrbitDegPerPx`. In Flight its x is `steer`. In HookWindow a tap on the region is `press`
  when `TouchHookTapAnywhere` is on.
- **Buttons** (ContextActionService with `createTouchButton = true`, then `SetPosition`/`SetImage`/`SetTitle` so they
  sit in our layout; our own art later): a cluster in the bottom-right quadrant, anchored to the corner,
  side `TouchButtonPx` x the option scale.

| Button | Position (px from the corner, 1x) | Visible in | Intent |
|---|---|---|---|
| AIM / CANCEL (one button, label by state) | (-260, -120) | Walking (AIM); Aiming, Presenting, Retrieving, Inspected (CANCEL) | `aimEnter` / `cancel` |
| REEL | (-120, -120) | Presenting, Retrieving, Inspected, HookWindow, Hooked | `hold` (or toggle, section 6) |
| HOOK | (-120, -240) | HookWindow (and, dimmed, Inspected so the thumb finds it before the window) | `press` |
| STOW | (-120, -120) | Holding | today's stow/release binding |
| full-screen tap | anywhere | CatchScene | `catchDone` |

The HOOK button is the latency-critical one: a button hit costs a thumb move; `TouchHookTapAnywhere` lets the thumb
that was already on the rod region press without moving. Both paths stamp the client time at `InputBegan`, as the
mouse does.

**Gyro cast (phones, off by default).** When `UserInputService.GyroscopeEnabled` and the option is on, InputMap reads
`UserInputService.DeviceRotationChanged` (delta CFrame per sample) in Aiming, takes the pitch rate about the device's
horizontal axis and feeds `rodDelta.dy = pitchRateDegPerFrame x GyroCastGainPxPerDeg`. A phone flick forward is then
the mouse flick forward. The right-region drag still works at the same time; whichever stream CastGesture sees first
wins its window. Tablets usually report `GyroscopeEnabled = false`; the option row hides then.

## 4. Gamepad

- **Left stick** (`Thumbstick1`): walk in Walking and Holding (PlayerModule); `aimTurn` in Aiming (ControlModule
  disabled as on touch). Deadzone and curve from config.
- **Right stick** (`Thumbstick2`): the rod in Aiming (`rodDelta.dy = -deltaY x GamepadRodGainPxPerUnit` per frame,
  `dx` likewise, so pulling the stick back then snapping it forward is the flick), `orbit` in the orbit beats at
  `GamepadOrbitDegPerS` x deflection x dt converted to mouse-px equivalent (`deg / MouseOrbitDegPerPx`), `steer` in Flight.
- **R2 (right trigger)**: `press` and `hold`, the exact role of mouse button 1, so "set the hook and keep the trigger
  in to reel" is one motion as it is on the mouse.
- **L2 (left trigger)**: `aimEnter` on press; a second press in Aiming is `cancel`.
- **L1**: `cancel` everywhere cancel is legal. **R1**: `press` as an alternative digital hook set (ruling 3).
- **A**: `catchDone` in CatchScene; `aimEnter` in Walking. **B**: `cancel`. **X**: stow in Holding.

**4.3 Trigger timing.** Roblox fires `InputBegan` for `ButtonR2` at its own fixed threshold and reports the analog
value in `InputChanged` as `Position.Z` (0..1). InputMap registers the press at `Position.Z >= GamepadTriggerPressAt`
(0.25) from `InputChanged` or at `InputBegan`, whichever comes first, and stamps that client time. A trigger has
about 10 mm of travel; at 0.25 the press lands roughly 20..40 ms earlier than a full pull. Dev1 measures both paths in
Studio once; if `InputBegan` is always first, drop the `Position.Z` path.

**4.4 Gyro.** The reference's Steam-controller trick is Steam Input turning gyro into mouse deltas. Under Steam that
still reaches Roblox *as mouse deltas*, so our mouse profile handles it with no code. Roblox exposes no controller gyro
of its own (device rotation is the mobile device's), so `GamepadGyroEnabled` is a stub that stays false; the
right-stick flick is the real gamepad cast. Check in Studio once that `UserInputService.GyroscopeEnabled` is false with
a controller on PC, and leave the stub.

## 5. Input mapping per state and device

Cells say what the control does in that state. "today's binding" = Dev1 fills the key from InputController.
"-" = ignored. Walking and Holding are PlayerModule movement; every other state has the ControlModule disabled.

| State | Mouse + keyboard | Touch | Gamepad |
|---|---|---|---|
| Walking | W/A/S/D walk; mouse orbit; Aim entry = today's binding | left stick walk; right drag orbit; AIM button | left stick walk; right stick orbit; L2 or A = Aim |
| Aiming | W/A/S/D turn the aim; mouse = rod, flick casts; cancel = today's binding | left stick turns the aim; right drag = rod, flick casts; gyro flick if on; CANCEL button | left stick turns the aim; right stick = rod, back-then-forward casts; L2 again, B or L1 = cancel |
| Flight | mouse X = steer | right drag X = steer | right stick X = steer |
| Presenting | hold mouse 1 = reel; mouse orbit; cancel = reset | REEL hold (or toggle); right drag orbit; CANCEL = reset | R2 hold = reel; right stick orbit; B or L1 = reset |
| Retrieving | release mouse 1 = sink again; orbit | release REEL; orbit | release R2; orbit |
| Inspected | as Presenting (the crank shows while held) | as Presenting; HOOK shown dimmed | as Presenting |
| HookWindow | mouse 1 press = hook set | HOOK button, or a tap on the right region (ruling 2); REEL still holds | R2 press (or R1, ruling 3) |
| Hooked | hold mouse 1 = reel, release = give line; orbit - (chase beat) | REEL hold or toggle; drag - | R2 hold; right stick - |
| CatchScene | mouse 1 click = done | tap anywhere = done | A or R2 = done |
| Holding | W/A/S/D walk; stow = today's binding; orbit | left stick walk; STOW button; right drag orbit | left stick walk; X = stow; right stick orbit |

The aim marker: on mouse it already follows the aim (AimMarker rev 3b: the 3D selector and the click). On touch and
gamepad there is no hover, so the marker follows `aimTurn` only, and its click (the distant_click) fires from the same
`press`/`catchDone` path in the states where it is legal. Dev2 confirms AimMarker reads nothing from the mouse position
directly; if it does, that read moves behind InputMap.

## 6. Accessibility

- **Hold-to-toggle reel** (`HoldToToggleReel`, options panel row): a tap on REEL / R2 / mouse 1 toggles `hold` on; the
  next tap toggles it off; InputMap forces it off on every state change out of Presenting/Retrieving/Inspected/Hooked
  and on `cancel`. The wire is identical: the same hold on/off messages, just not tied to a finger. In HookWindow a tap
  is still `press` first; the reel toggle only applies after the set.
- **Button scale** 0.8..1.4 and **left-handed** mirror (cluster bottom-left, thumbstick right).
- **Gyro off by default**; the panel row names what it does.
- **Sensitivity per device and invert Y**: `design/WSH_options_panel_additions.md` has the rows; InputMap reads the same
  attributes CameraAF reads.

## 7. Server-side invariants (Dev3 checks each)

1. No message carries a device type. The only device-related value anywhere is an optional client attribute
   `InputDevice` on the LocalPlayer for analytics, never read by game code.
2. StateRules' state x action matrix is unchanged: every intent maps to an action that is already legal in that state,
   or InputMap drops it client-side.
3. RequestGuard rates are unchanged and touch/gamepad cannot exceed them: `aimTurn` and `orbit` are client-only until
   InputController sends its existing cadence of aim updates; `hold` on/off is debounced to the same minimum interval
   the mouse path has (a toggle cannot flutter faster than a finger).
4. FishJudge sees a press time stamped the same way (client `InputBegan` time, LatencyBudget applied server-side).
   A touch or trigger press is slower by the device's own latency, not by ours.
5. `sendCatchDone()` is the one entry for catch-done on every device.

## 8. PARITY

Reference (About Fishing, Steam): mouse flick casts, mouse orbits, one button sets the hook and holds the reel; a
controller works through Steam Input, with gyro-as-mouse as the community trick; no touch build. We: identical on
mouse; touch and gamepad feed the same CastGesture stream and the same net messages; on-screen buttons, the stick flick
and the phone gyro exist only in ours because the reference has no touch or native controller path; Roblox has no
controller gyro so that part is a stub. Nothing the server judges differs by device.

## 9. Rulings needed (Coordinator)

1. WS-I in F1 or R1. Proposal: the `InputMap` seam and `C.Input` block go in with Dev1's #4 fix now (a pure refactor
   of the mouse path, verified byte-for-byte on the net by the W2 wire gate); touch and gamepad profiles in R1.
2. HookWindow on touch: HOOK button only, or also a tap anywhere on the rod region (`TouchHookTapAnywhere`). Proposal: on.
3. Gamepad hook set: R2 (same as reel, the mouse's muscle memory) with the 0.25 threshold, or R1 (digital, fewer ms).
   Proposal: R2, R1 as a second binding.
4. Gyro cast default off; no gamepad gyro. Confirm.
5. Gain numbers in section 2 are starting points for Adrian's feel pass on a phone and a controller; the panel exposes
   only sensitivity, not the gains.
6. Left-handed mirror in the same batch or later.

## 10. Acceptance tests

Offline (Luau CLI, `tests/wsa/`):
- `inputmap_test.luau`: InputMap is pure given a fake input source. A scripted scene (Aim entry, 12 frames of
  pull-back, 4 frames of flick, wait, Swallow, press, 3 s hold, release, catch-done) is played on all three profiles;
  the emitted intent list is identical in kind, order and payload fields that reach a net message. Negative control: a
  drag below the flick threshold emits no cast on any profile.
- `gesture_test.luau` gains two rows: the touch feeder (gain 2.0 on a 150 px drag) and the gamepad feeder (a 0 -> -1 -> +1
  stick swing over 9 frames) both produce a cast inside CastGesture's windows; a slow swing (30 frames) does not.
- Trigger row: a synthetic `Position.Z` ramp 0 -> 1 over 80 ms registers the press at 20 ms (0.25); a ramp that peaks at
  0.2 does not press.
- Hold-to-toggle row: tap, tap -> hold on then off; hold on then a state change to CatchScene -> off; the message list
  has exactly two hold messages.
- StateRules unchanged: `rules_test.luau` still passes with no new actions.
Studio (sandbox, Dev3 with AF1Playtest): the full loop on Studio's touch emulation and on a controller; the server
log shows the same message kinds and counts as a mouse run of the same script within RequestGuard's limits.
Adrian: a 10-minute feel pass on a phone (cast, orbit, hook set) and on a controller.

## 11. Who does what

- Dev1: `Fishing/Client/InputMap.lua` (new), `Fishing/Client/InputController.lua` (route the mouse path through
  InputMap; fold in the #4 `lineM` clamp), `Fishing/Shared/CastGesture.lua` (a `feed(dx, dy, dt)` entry if the sample
  feed is not already a function), review of the `C.Input` patch.
- Dev2: `Fishing/Client/CameraAF.lua` (`addLook` takes mouse-px equivalent from InputMap; per-device sensitivity),
  `Fishing/Client/CameraController.lua` (orbit beats read InputMap), `Fishing/Client/AimMarker.lua` (no direct mouse
  read), `Fishing/Client/OptionsPanel.lua` rows (with WSH_options_panel_additions.md).
- Dev3: `tests/wsa/inputmap_test.luau`, the `gesture_test.luau` rows, the guard/rate check, the Studio matrix,
  PARITY_CHECKLIST rows.
- WordAgent: `patches/WSI_FishingConfig_input.patch.txt` (the `C.Input` block), README rows.
- Adrian: the feel pass, section 10.
