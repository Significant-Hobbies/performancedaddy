# Local resource investigation — 2026-10-02

The running installed PerformanceDaddy 0.2.15 build 20 had 186.6 MiB resident
memory and 192.5 MiB physical footprint, with a 307.2 MiB historical footprint
peak. `vmmap -summary` attributed 49.9 MiB to CG Image regions and 21.9 MiB to
Image IO regions, including compressed/swapped pages. These regions do not
prove which image or view owns every allocation. StorageDaddy was 39.2 MiB
resident; ContextDaddy and BrowserDaddy were not running and were not measured.

A 7 MB executable does not imply 7 MB runtime memory. Decoded images, UI
framework objects, drawing surfaces, caches and diagnostic data are allocated
at runtime. PerformanceDaddy's original two 1254-square mark uses and one
1000-square doodle sheet alone represent 16,580,128 decoded RGBA bytes.

The local candidate decodes them at 128, 256 and 432 pixels respectively. This
is sufficient for the existing small marks and 72-point doodles at 2x display
scale. The process-icon cache also records pixel costs with a 2 MiB eviction
budget and requests the closest 64-pixel source representation. NSCache's
cost limit is advisory, not a hard process RAM cap.

## Controlled artwork probe

From the repository root:

```sh
xcrun swiftc -O Sources/PerformanceDaddy/DecodedArtwork.swift scripts/measure-artwork.swift -o /tmp/PerformanceDaddyArtworkProbe
/tmp/PerformanceDaddyArtworkProbe original "$PWD/Sources/PerformanceDaddy/Resources"
/tmp/PerformanceDaddyArtworkProbe bounded "$PWD/Sources/PerformanceDaddy/Resources"
```

The same executable loads and retains the same three asset uses in separate
processes, touches decoded pixel data, and reads its own native physical
footprint. The bounded mode calls the production decoder. Observed results:

| Mode | Decoded bytes | Process physical footprint |
| --- | ---: | ---: |
| Original | 16,580,128 | 22,594,256 |
| Bounded | 1,074,176 | 10,666,656 |

Decoded artwork is 93.5% smaller. The isolated probe saves about 11.9 MB of
physical footprint. Framework and decoder overhead remains. This is a component
benchmark, not a controlled comparison of the complete app or a 10x GUI claim.
The installed app was not replaced or closed. Native UI inspection failed
because the automation provider could not start its pipe, so a complete
release-mode GUI before/after measurement remains unverified.

The sibling DaddyRad MCP can perform agent diagnostics without launching the
four GUIs. Its release protocol run initialized at 9.3 MiB RSS and had a maximum
request-time sample of 34.6 MiB in the latest regression run, including cancellation of a 20,020-file scan.
These are request-time resident samples, not continuous peaks or directly
comparable GUI workloads. Reproduce its current workload with
`python3 scripts/verify-mcp.py .build/out/Products/Release/daddyrad-mcp` from
`../daddyrad/mcp`.

Track full-app verification in [issue #15](https://github.com/Significant-Hobbies/performancedaddy/issues/15).

## Visibility-aware monitoring

The local candidate tracks the dashboard, agent wall and menu popover separately.
When no surface is visible, the process census runs every 30 seconds without
enumerating sockets or accumulating resource history. Hook notifications and
two-second exact-identity exit checks remain active. A pending hook from a natively
observed process wakes the inventory loop rather than waiting for the background
tick. Reopening schedules a fresh full snapshot and resets rate/history continuity.
Hiding one window does not change modes while another surface remains visible.

The background sampler releases cached socket observations and reports their
timestamp unavailable. It does not turn stale evidence into a zero socket count.
Icons cached for presentation are evicted when the last surface hides. Full
socket scans also reuse one output buffer across PIDs. These changes reduce
collection and retention; they are not a measured whole-app RAM percentage.

## Native Release page comparison

`python3 scripts/measure-native-pages.py` runs a fresh Release XCTest process
with the product's process and memory pages, 512 identical fixture processes,
30 history points, artwork and icons at 1180×800. It renders Processes, Memory,
then Processes again and detaches the content. Copy
`Tests/PerformanceDaddyTests/NativeResourceProbeTests.swift` to a temporary
checkout of the baseline and pass that checkout to the same script to compare.
The original working tree and installed app need not be replaced.

Three alternating fresh-process pairs compared baseline
`5cb28c0b955a51e1c1ad738ee9fdae76a8c182e2` with the local candidate. Median final
readings after content detach:

| Measurement | Baseline | Candidate | Reduction |
| --- | ---: | ---: | ---: |
| Resident memory | 121.45 MiB | 116.44 MiB | 4.1% |
| Physical footprint | 63.09 MiB | 62.13 MiB | 1.5% |

Candidate footprint ranged 61.47–62.24 MiB; baseline ranged 62.86–63.20 MiB.
The host includes XCTest, SwiftUI/AppKit and product views. This offscreen
fixture excludes the complete app lifecycle, status item, live workload and
user history, and does not exercise automatic window visibility. It demonstrates
only a modest page-level difference, not a 10x GUI reduction or the component
probe's 53% saving applied to the app. The retained native UI and framework
allocations require complete-app profiling before further architectural changes.

Validation: 155 normal package tests pass; the opt-in measurement test is
skipped in the ordinary suite and passes in the Release probe runs. Focused
tests cover a real TCP listener's opt-out/restoration, multiple surfaces,
occlusion/minimization/detachment, rate discontinuities and background hooks.
Native UI automation still fails during pipe startup, so installed-app
fullscreen/session acceptance and comparable full-app measurements remain open.
