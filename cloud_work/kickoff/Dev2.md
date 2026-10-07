Adrian: resume. The weekly limit reset. Your queue, in order:

**1. Finish CameraAF R1/R2** where the limit cut you off: the three new sweep checks were written as probes; check 8 was expected to FAIL on rev 4 (R1's snap). Run it, fix the thresholds, finish R1 and R2 in both copies (the w3 copy at :479 and the batch-2 copy at :426), send the delta to Dev1.

**2. Cloud items routed to you** (branch `claude/hello-b2aghd`, pulled to `%CW%`; all written without the project files, so fit them to the real bytes):
- `%CW%\design\WSH_options_panel_additions.md`: mouse/touch/gamepad sensitivity, invert Y, FOV (Walk and Aim beats only; Caught keeps its pin), hold-to-toggle reel. The Coordinator rules which rows go in F1 (R5). Values as `Opt*` attributes on the LocalPlayer now, SaveData later.
- `%CW%\design\WSI_touch_gamepad.md`: one device layer, `Fishing/Client/InputMap.lua`, that turns touch drags, stick swings, triggers and phone gyro into the same calls the mouse path makes (`TouchRodGainPxPerPx = 2.0`, `GamepadRodGainPxPerUnit = 150`, trigger press at 0.25). The 10-state x 3-device table is section 4. You and Dev1 share it; the Coordinator rules R4.
- New client modules, review as new files: `%CW%\src\Fishing\Client\TackleBoxUI.lua` (grid geometry, hit test, a drag state machine with the same four verbs for mouse, touch, gamepad) and `CatchCard.lua` (the card's text: units, badges, price). Suites in `%CW%\tests\`. A sandbox driver, `%CW%\tests\TackleBoxUI_sandbox_driver.client.lua`, draws the grid with Frames in a Play session; it only compiled in the cloud, so expect to fix a require path or two.
- `%CW%\design\mockups\`: generated UI mockups (tackle box, catch card, trader) as a look reference, not pixel truth.

**3. Blender assets** in `%CW%\blender\exports_v2\` (textured fish x5, a rigged trout with 7 bones, rod and reel, dock, trader stall; `README_v2.md` has the import steps). Import ONE fish into your sandbox and confirm: the facing axis (+X by default; `--face-negz` builds along LookVector), the import scale against the project's metre-to-stud ratio (read MeshPart.Size.X), that Studio keeps the texture (SurfaceAppearance or TextureID), and that the fish stays one MeshPart for `TroutView.setBend`. F1 keeps your existing trout rig; these are F2 placeholders. Report the four answers to the Coordinator in one line.

**4. Still yours from before:** the Caught camera's body ratio (R1 seed), the dead peak-tracking branch note for WordAgent's WS-H rows.
