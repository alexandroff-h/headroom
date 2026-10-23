# Headroom design contract

Headroom answers four questions and nothing else:

1. **Here is your performance.**
2. **Here is how you can improve it.**
3. **Here is what you can kill.**
4. **What IS this thing** — because a process name is the name of an implementation detail, not of anything a person started.

The measure of the app is not time spent in it. It is **how many improving actions the reader takes**, and every action reports how much better the Mac actually got.

## The rule that governs the surface

**One material.** The window background is the only surface. Nothing floats on it, nothing is darker than it, nothing has a shadow. Space is divided by hairlines and by emptiness, never by a card.

The previous version failed because it put a white settings pane beside a dark chart box, and two materials in one window is what makes a window read as a sheet. Every reference on the project board commits to one material: AccessGrid divides plain white with dashed rules, the dark card grid uses no borders at all.

Acceptance tests: no view file outside `Design/` contains a literal colour, and no view file anywhere calls `.shadow(`.

## Honesty

- **No prediction of improvement.** An app's resident memory counts pages shared with other apps, so its footprint is not what quitting it hands back. Headroom asks the app to quit, waits twelve seconds for the system to settle, compares a median of three readings on each side, and reports the difference it can actually see. Below the noise floor — 64 MB, 3 processor points — it says "no measurable change" rather than inventing a win.
- **Rates are never summed.** Memory returned adds up; processor use does not. 6% freed on Tuesday plus 11% on Friday is not 17% of anything, so the recap reports the best single action instead.
- **Unknowns stay unknown.** A missing reading is shown as a missing reading, never as zero.
- **No fictional health score.** Percentages are percentages.
- **Quitting is cooperative.** `NSRunningApplication.terminate()`, so the app can save your work. Force quit exists behind one explicit confirmation and is the only thing in Headroom that can lose work.
- **macOS is never offered for quitting.** It is in the list so the totals do not lie, and folded because quitting it is not a thing a person should be invited to do.
- **Everything is local.** One JSON file on this Mac, no account, no telemetry, and a visible way to erase all of it.

## Attribution

The fourth question is answered by two rules, in this order:

1. A helper's executable lives inside its app's bundle, so walking the path to the **outermost** `.app` collapses every Chrome renderer onto Google Chrome with no catalogue entry for any of them.
2. Anything left over is attributed to **whoever started it**, walking the parent chain and stopping at `launchd`. A `node` with no bundle belongs under the editor that launched it.

A short catalogue explains the executables people actually see at the top of Activity Monitor and cannot decipher. It supplies explanations, never names: a bundle on disk always outranks it for the name.

## Type and colour

Nine type roles, three weights. Hierarchy is carried by size and weight because there is only one surface to carry it on. Live figures are tabular, with the unit in its own lane so `956 MB` becoming `1 GB` does not reflow a row.

Every contrast ratio below was measured, not estimated, against its own surface:

| Token | Light | Dark |
| --- | --- | --- |
| primary | 17.3:1 | 16.4:1 |
| secondary | 7.1:1 | 7.4:1 |
| tertiary (the floor) | 4.9:1 | 5.4:1 |
| accent fill vs its white label | 5.9:1 | 5.9:1 |

The accent appears once per screen: on the thing to do. It never touches a figure, a heading, or a reading. Green appears only after the reader has acted, on a measured gain.

## Motion

DialKit does not cover SwiftUI, so these are chosen rather than dialled:

- **hover 90 ms** — below ~100 ms a pointer-driven change reads as instant.
- **press 70 ms** — a press has to land before the finger lifts. Expressed as a fill shift, not a scale, so it lands identically from the pointer or from the space bar.
- **reading 0.45 s spring, no bounce** — a live figure should look like it is settling. Bounce implies overshoot, which is a lie about the data.
- **reveal 0.34 s, bounce 0.18** — disclosure is physical, so it may bounce. The only thing in the app that does.
- **leave 0.28 s** — a row removed after a quit should go quickly, but not vanish.
- **arrive 0.4 s, bounce 0.1, rise 8 pt** — the measured-gain line is the payoff of the whole app, so it is the slowest thing in it and the only one that travels.

Reduce Motion drops to a 0.12 s crossfade rather than to nothing: a change with no transition is harder to follow, not easier.

The list only commits a new order every four seconds, and never while the pointer is inside it. A row that moves out from under the cursor cannot be clicked.

### Light

Glass has a highlight, and a highlight has a source. On the one filled button the specular is
pinned to the pointer: move across it and the light moves with you, the way it would if you
tilted the thing in your hand. Tracking is instant — the light is cast by the pointer, it is not
chasing it — and only the fade in and out is timed, at 160ms.

It is on the filled button and nowhere else. Over a near-white capsule additive white has nothing
left to brighten: it clips, and the pool of light becomes a grubby square patch with the
gradient's own frame showing at the edges. That was rendered and looked at before it was ruled
out. The glass material's own `interactive()` highlight already covers those controls.

A **beam** crosses the button while a measurement is settling. The determinate fill underneath
says how far along it is; the beam says it is still moving, which a fill creeping across a
twelve-second window cannot say on its own. It is the only looping animation in the app, it lives
for at most twelve seconds at a time, and Reduce Motion removes it and leaves the fill.

What the beam is made of depends on what it crosses. On a dark ground it is light, added
(`plusLighter`, white at 0.28). On a near-white ground there is nothing to add, so it is the
accent hue laid over the surface instead (normal blend, 0.32). Both values were chosen by
rendering the alternatives side by side rather than by taste: white-on-white at every strength
read as a pale smear you could not track, and white at 0.45 on dark washed out the label it
passed under.

## Cost

A tool about wasted processor time may not waste it. Headroom samples every two seconds and holds **≈2% of one core** while doing so. Two measured fixes got it there from ≈29%:

- Process names and paths are read once per process and then carried. Decoding them again for 490 processes every two seconds was the single most expensive thing the app did.
- Two readings that would draw the same pixels are equal, so the list redraws only the rows that visibly changed. Comparing raw bytes made all forty rows differ every sample.

Icons are rasterised once at their final size; resampling the 1024 pt master down to 26 pt forty times per sample cost more than every measurement in the app put together.

## Capture affordances

`HEADROOM_WINDOW=820x1560` opens a window taller than anyone would use, so a whole scrolling column fits in one frame. `HEADROOM_SCREEN=progress` opens on the other screen. `HEADROOM_EXPAND=Chrome` opens that row. `HEADROOM_TIMING=<path>` appends per-sample timings. None of them does anything unless the variable is set, and none of them invents a reading.

## References

The project board is **Headroom — performance you can act on**. Disk utilities are explicitly rejected as a reference category.

- Monarch's subscription row — logo, human name, what it costs, when, in one row you can act on. The structural model for the app row.
- Monarch's reports — how accumulated numbers are made to feel like progress rather than like a log file.
- AccessGrid — plain white divided by dashed hairlines, generous type, one accent on the one thing to do.
- An activity timeline with sentence rows and period headings — the model for the action record.
- Raycast, Things, Arc — the register: quiet surface, short list, nothing trying to impress you.

## Deployment

Headroom deploys to **macOS 14 and later**. Almost nothing in the source is version-gated,
because the deployment target makes the compiler reject anything newer — availability is enforced
at build time rather than guarded at runtime. Liquid Glass is the one exception, and it is gated
three times. Two of those are in `Design/Glass.swift`; the third is not in the source at all.

**The SDK stamp is a design decision, not build trivia.** AppKit reads the SDK version recorded in
the Mach-O header to decide which era of controls to draw — that is how Apple changes an
appearance without redrawing every app already in the field. SwiftPM stamps the *deployment
target* there, so Headroom shipped `minos 14.0 / sdk 14.0` and was handed macOS 14 controls on
macOS 26: a flat grey segmented picker, no glass, nothing in the build output mentioning it. The
code was right the whole time. `build-app.sh` now passes `-platform_version macos 14.0 <sdk>` so
the binary says what every other Mac app says — newest SDK, oldest deployment target — and
`check-compat.sh` fails if the stamp ever equals the deployment target again.

The compile-time gate is the other half. `glassEffect` exists only in the macOS 26 SDK, and
`@available` cannot conjure a symbol the compiler never saw, so an older SDK would not build at
all. `build-app.sh` defines `LIQUID_GLASS` only when the SDK it found can see the API; without it
every control compiles its pre-26 half and nothing else. The Command Line Tools still build a
working app.

The hazard that version is *not* the compiler's job, and was audited separately:

- **Weak-linked SwiftUI entry points.** Building against the macOS 27 SDK emits weak externals
  for `WindowGroup(id:title:lazyContent:)`, `_TaskModifier2`, `_TagTraitWritingModifier`,
  `popoverCore`, and `ForEach.create`. Each was traced into the disassembly and each sits behind
  a real version check with a live fallback branch (14.5, 26.4, 26.0, 15.1 and 26.0
  respectively). Built against the macOS 15 SDK only the first appears. There is no unguarded
  weak call in the image.
- **`swift_coroFrameAlloc`** is absent from macOS 15's `libswiftCore`; the compiler emits a null
  check with a `malloc` fallback.
- **`vm_statistics64_data_t` grew** from 152 bytes in the macOS 15 SDK to 416 in the macOS 27
  SDK. Every new field is appended, the six fields actually read sit at identical offsets, the
  struct is zero-initialised, and the kernel clamps an oversized count rather than failing.
- **SF Symbols are not compiler-checked.** Every symbol name in the app was verified against
  `/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist`.
  The newest is `gauge.with.dots.needle.50percent` at macOS 14.0.

`scripts/check-compat.sh` asserts the Mach-O minimum, the Info.plist minimum and the SDK stamp,
and prints every weak-linked SwiftUI entry point so a new one is traced rather than assumed safe.
The five `Glass` symbols appear there, each behind `if #available(macOS 26.0, *)`.
