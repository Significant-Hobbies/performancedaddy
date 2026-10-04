# PerformanceDaddy status

## 2026-10-04 — public 0.2.17 build 22

Released [v0.2.17-22](https://github.com/Significant-Hobbies/performancedaddy/releases/tag/v0.2.17-22)
from `c139fe84ca554bc6c2aeec68e3fc0660481c91ae`. Both CI jobs passed, then the
protected workflow passed candidate checks, universal Release builds,
Developer ID signing, Apple notarization, stapling, signed Sparkle feed
validation and live publication checks.

Independent public download: 8,954,369 bytes, SHA-256
`a79739c422c16d115c84c3dd6a1fa02cce4b644de2920fe48b20030fe14de08e`.
The live feed matches the release asset and advertises 0.2.17 build 22.
The DMG checksum, integrity and staple validate; both the DMG and mounted app
are accepted by Gatekeeper as Notarized Developer ID. The mounted app passes
strict signature verification and contains arm64 and x86_64. Receipts are
retained in `artifacts/releases/v0.2.17-22/`.

This ships opt-in sustained-load alerts: a local notification names the
workload that consistently led sustained CPU or memory pressure, and Quit runs
only when the owner presses it (apps get a normal quit request, other
workloads SIGTERM to captured identities, nothing is force-stopped). Off by
default. The notification and Quit action were covered by unit tests but not
exercised on a real Mac; no local launch smoke or native UI run occurred this
session. The installed build 21 was not replaced.

## 2026-10-02 — public 0.2.16 build 21

Released [v0.2.16-21](https://github.com/Significant-Hobbies/performancedaddy/releases/tag/v0.2.16-21)
from `439d06490d3e135942d4decc62fb96c9ddca0ced`. Both CI jobs passed, then the
protected workflow passed candidate checks, universal Release builds,
Developer ID signing, launch smoke testing, Apple notarization, stapling,
signed Sparkle feed validation and live publication checks.

Independent public download: 8,781,025 bytes, SHA-256
`f1ff1f8a59499220a102d2eebcb4182ee61de55b13d4365568afcd0894766098`.
The live feed matches the release asset and advertises 0.2.16 build 21.
The DMG checksum and staple validate; both the DMG and mounted app are accepted
by Gatekeeper as Notarized Developer ID. The mounted app passes strict
signature verification, contains arm64 and x86_64, and passes a local launch
smoke test. Receipts are retained in `artifacts/releases/v0.2.16-21/`.

This ships session reconciliation, the no-scroll wall, bounded artwork and
visibility-aware monitoring. It does not establish a 10x whole-app RAM gain.
Native UI automation still fails during pipe startup; live fullscreen/session
acceptance and a controlled warm-app allocation capture remain open in issue
#15. The installed build 20 was not replaced.

## 2026-10-02 — local session, viewport and memory follow-up

Prepared locally under [issue #15](https://github.com/Significant-Hobbies/performancedaddy/issues/15).
Early hooks reconcile by exact process/session identity; links survive incomplete
inventories until native exit evidence. The existing agent wall fits its viewport
without a ScrollView. Artwork decoding and icon-cache costs are bounded.
Monitoring tracks actual visible surfaces: hidden mode uses a 30-second,
socket-free inventory without resource histories; hooks and two-second exit
checks stay active. Reopening requests fresh evidence and resets rate continuity.

All 155 ordinary package tests pass, plus the separate opt-in Release native
page probe; Release build, design and whitespace checks pass. DaddyRad's shared
read-only MCP passes its four unit tests and all-eight-tool protocol regression
against the updated native core. Three matched native-page probe pairs show
median resident memory 121.45 to 116.44 MiB and footprint 63.09 to 62.13 MiB.
These are modest test-host/page results, not a 10x complete-app improvement.
See [RESOURCE_FOOTPRINT.md](RESOURCE_FOOTPRINT.md) for reproduction and limits.

Native UI provider startup still fails. Live fullscreen/session acceptance and
a comparable complete-app memory measurement remain open. No installation,
commit, push or release occurred.

## 2026-09-27 — public 0.2.8 build 13 installed

The owner requested an even smaller battery mark without a numeric count or
filled background. Source now draws a fixed-width outline with one colored mark
per agent through twelve sessions and a proportional strip beyond that. The
status-item label starts live monitoring when it appears, covering app launches
that restore no main window. Apple Silicon and Intel Release builds, 18 focused
tests, 110 full-package passes with one environment-dependent skip, and the
design check passed. The protected workflow released `v0.2.8-13` from source
`d1f8415` after exact-source checks, universal build, launch smoke test,
Developer ID signing, Apple notarization, stapling, signed appcast and live
download verification. The public DMG SHA-256 is
`1a08b7f3c7d1cefc66695bff5a45b8026e9cd0cace333819ec841dfb4a721031`.

The independently downloaded public image matched the GitHub release asset and
`SHA256SUMS`, and Gatekeeper accepted it as Notarized Developer ID. The mounted
app passed strict signature and Gatekeeper checks. `/Applications/PerformanceDaddy.app`
is build 13; its executable matches the public image byte for byte and
XcodeBuildMCP launched it successfully. Build 12 is preserved at
`~/Applications/PerformanceDaddy backups/PerformanceDaddy-0.2.7-build12.app`.
The native UI provider's pipe failed to start during installed-build inspection,
so the final battery appearance and popover remain visually unverified.

## 2026-09-27 — public 0.2.7 build 12 installed

The protected workflow released `v0.2.7-12` from source `0a94cecb` after
Apple Silicon and Intel Release builds, 18 focused and 111 full package tests,
Developer ID signing, notarization, stapling and public artifact checks. The
independently downloaded public DMG matched the GitHub release checksum and
passed Gatekeeper. Its SHA-256 is
`eacbf83baf18bbdd8e36870022623ad9034506ada5f5757381a80bd0043ec82d`.
The live appcast advertises 0.2.7 build 12 and the exact public DMG URL.

`/Applications/PerformanceDaddy.app` is now build 12. Its executable matches
the public DMG image byte for byte, its strict signature and Gatekeeper
assessment pass, and XcodeBuildMCP launched it successfully. Build 11 is
preserved at `~/Applications/PerformanceDaddy backups/PerformanceDaddy-0.2.6-build11.app`.
The update adds the compact battery-shaped menu bar count and per-agent state
marks, a grouped session panel, continuous session-presence refresh while the
wall is closed, and filtering of Claude task notifications from request labels.

Native UI automation confirms that the installed app is running but cannot
select a PerformanceDaddy window or its menu panel (`cgWindowNotFound`), even
after reopening it. The exact installed battery appearance and click-through
panel remain visually unverified; source builds and tests do not substitute
for that visual check.

## 2026-09-27 — public 0.2.6 build 11 installed

The protected workflow released `v0.2.6-11` from source `8fb67ec` after
exact-source candidate checks, a universal build, Developer ID signing,
launch smoke test, Apple notarization (`a0719022-bbc7-4bc2-a498-e5a9db5185f4`),
stapling, signed appcast and live download verification. The public DMG SHA-256
is `82de20aee553ea4ed277146bc5fa64b2bc541f3c5c50ad762fd9e6ca4b4f4bd7`.
The independently downloaded public artifact matched `SHA256SUMS`; its ticket,
Gatekeeper assessment and the app's strict signature passed. The installed
`/Applications/PerformanceDaddy.app` is build 11 and its executable matches the
released image byte for byte. Build 10 is preserved at
`~/Applications/PerformanceDaddy backups/PerformanceDaddy-0.2.5-build10.app`.

Codex and Devin user hooks now call the installed app. Fresh sessions of both
providers showed the correct terminal tile, stopped state and short request
label in the installed full-screen wall; their tiles disappeared on exit. The
three earlier terminal sessions observed during development had no hook events,
so their states were unavailable. Older sessions still require a hook reload or
restart before the wall can report their lifecycle state.

## 2026-09-27 — public 0.2.5 build 10 installed

The protected workflow published `v0.2.5-10` from source `cdecb4c` after
exact-source candidate checks, universal build, Developer ID signing, launch
smoke test, Apple notarization (`d4f58803-f482-4119-b54a-01515356f64c`),
stapling, signed appcast and live download verification. The released DMG SHA-256
is `acb6575b9a2d59a03bcb8b97d61b6529b03fc285a4a8bdb6fd37a6da6187d790`.
The downloaded artifact passed its published checksum, Gatekeeper and strict
signature checks. `/Applications/PerformanceDaddy.app` is now 0.2.5 build 10;
its executable matches the released image byte for byte and launched through
XcodeBuildMCP. The installed App access screen showed 25 launch files split
11 user, 4 all-user and 10 system, with owning-app icons where available;
Diagnose showed the saved-baseline control. Build 9 was preserved at
`~/Applications/PerformanceDaddy backups/PerformanceDaddy-0.2.4-build9.app`.

## 2026-09-27 — local follow-up prepared for review

Source changes add launch-file scope counts and app icons where a file points
into an app bundle, include already-measured footprint and cumulative disk
counters in anonymous snapshot exports, and add a locally saved known-good
capture with independent recent-run and baseline deletion. All 106 package
tests, two Sparkle support tests, six Worker tests, the native Release build and
the design-workflow check pass. A separate development app showed the new
baseline action and exact recent-run deletion review; the review was cancelled.
This qualification used a separate development app and left the installed
public build 9 unchanged; publication and installation require their own
release receipts.

## 2026-09-26 — public 0.2.4 build 9

The protected release workflow published signed, notarized `v0.2.4-9` from
`8a9735c`. The public download and Sparkle feed were verified against the
qualified artifact, and build 9 is installed in `/Applications`. The release
adds the bounded App access audit, dated manual Settings notes, reviewed
single-file LaunchAgent Trash actions and reviewed per-app permission resets.
macOS does not provide this app a supported readout of other apps' live privacy
grants or a way to unregister another app's Login Item; those reviews remain in
System Settings.

## 2026-09-23 — Claude Code sessions and public update 0.2.2 build 2

Claude's native installer runs version-named binaries under
`~/.local/share/claude/versions/`; exact `claude` process-name matching missed
them. Recognition now accepts only numeric versions in that installed layout.
The local development launcher also embeds its pinned Sparkle framework.
All 100 package tests, the Sparkle support tests and the Worker tests pass.
The signed release candidate and installed `/Applications` app each showed five
live Claude Code rows in Agent sessions. This is running-process evidence, not
conversation history or a promise that every wrapped launch is visible.

The universal arm64/x86_64 DMG was Developer ID signed, notarization accepted
(submission `d54c4f80-86a3-4e92-99b7-c7584cd0ffdb`), stapled and accepted by
Gatekeeper. SHA-256 after stapling is
`67ba28016282fade4129a1d7cf4e00f0ff1d2cb8bdaf9db5e2ea191ea5e7610e`.
The installed app passed strict signature verification and matches the DMG app
executable byte for byte. The Ed-signed 0.2.2 build 2 appcast and exact DMG are
live on the `/updates/*` Worker (version
`d49e559c-5e82-4525-89a3-86dd32c96615`); a public download matched the
local DMG byte for byte. Release source: `1d83d6c` on `main`; CI passed.

## 2026-09-20 — first public update release 0.2.1 build 1

PerformanceDaddy 0.2.1 (build 1) is the first public, Sparkle-enabled release.
Universal arm64/x86_64 DMG, Developer ID signed with hardened runtime, Apple
notarization accepted (submission e1ce2445-0724-4eb5-ac3c-dba11d4f614a), stapled
and Gatekeeper-validated. The signed appcast was generated via
`scripts/prepare-appcast.py` and is served live at
`https://performancedaddy.significanthobbies.com/updates/appcast.xml` by the
`performancedaddy-updates` Worker; the Ed-signed enclosure downloads verified.
This ends the private-prerelease posture: update DMGs are publicly fetchable.
Notarization credentials were restored to Keychain as the
`fleet-personal-notary` profile (from Infisical). SHA256SUMS records the final
stapled artifact since stapling rewrites the DMG. Independent review hardened
two edges in the same window: `prepare-appcast.py` now requires a strict
per-filename SHA256SUMS match plus a destination hash check, and busy-time
background update checks are recorded and fired on idle rather than dropped
(applied across all three daddy apps).

## 2026-09-20 — daddy-series update stack and grouped lists

PerformanceDaddy now shares the daddy-series structure and Sparkle update stack
with storagedaddy and browserdaddy (issue sarthakagrawal927/storagedaddy#30):
Sparkle 2.9.6 pinned, `AppUpdates` defers checks and relaunches while a recording
or reviewed stop action is in flight, update items live in the app menu and the
menu-bar extra, `SU*` keys are injected at packaging by
`scripts/package-release.py`, and `scripts/{sparkle_support,prepare-appcast,
test_sparkle_support}.py` match the sibling repos. An updates-only Worker owns
`performancedaddy.significanthobbies.com/updates/*` — deployed and verified live
alongside the ios-landings Pages site; the feed is a dormant empty channel until
the first release publishes an enclosure via `prepare-appcast.py`, which gates on
a signed, notarized, stapled DMG plus SHA256SUMS. EdDSA signing key
`performancedaddy-updates` stays in Keychain; only the public key is committed.
CI parity added (`swift test`, release build, sparkle unittest, worker test).
Also shipped: Kind/App/Category grouping on the Processes and Memory pages with
clickable toolbar metrics ranking top contributors (issue #3), and configuration
inventory excludes top-level personal folders (Desktop, Downloads, ...) while
still observing project subfolders. All 93 package tests plus sparkle and worker
tests pass. Note: the next release's DMG becomes publicly fetchable through the
feed — the private-prerelease posture ends with that publish.

## 2026-09-20 — signed private native release

PerformanceDaddy 0.2.0 (build 1) is installed from the same universal arm64/x86_64
artifact published as private prerelease `v0.2.0-1`. The application and DMG are
Developer ID signed with hardened runtime, accepted by Apple notarization, stapled,
validated by Gatekeeper and checksum-qualified. Release tag `v0.2.0-1` resolves
to source commit `8b0407c076b0e946cc9088e98d8e916c40d170de`; the DMG SHA-256 is
`54d42014380dadfd2f6af374bb25529d52796587d7ec0dc649d84c4efcd862e0`.
The public landing remains informational and does not expose this private download.

Durable local evidence now retains at most ten completed diagnostic captures and
500 valid lifecycle events for 24 hours using bounded atomic owner-readable files.
Active exit watches are deliberately not restored. Process inspection distinguishes
an exact configured launch policy from a currently observed identity without claiming
registration, enablement, launch cause or automatic restart. Thermal evidence uses
Apple's supported public thermal state and power constraints; raw fan RPM and sensor
temperatures remain explicitly unavailable rather than relying on private SMC access.

The final design receipt passes in preserve mode with deterministic native captures,
36/40 critique, 18/20 audit and no open P0/P1 findings. The exact installed app exposes
named controls and headings through macOS accessibility and retains Command-F search.
All 94 tests pass. A 30-second optimized-candidate sample consumed about 0.67 CPU-seconds
(roughly 2.2% of one core) and remained below 150 MB resident; a follow-up installed-app
sample showed idle intervals with one bounded inventory spike and remained below 175 MB.
These are local observations on this Mac, not a universal energy or memory guarantee.

## 2026-09-20 — remote source backup

Owner authorized committing and pushing the existing native product source to
a private GitHub repository. Source, tests, artwork and reproducible scripts
are included; build output and machine-local diagnostic captures are excluded.
This is source backup, not a signed/notarized native release. The public landing
is live at https://performancedaddy.significanthobbies.com/ from ios-landings.

## 2026-09-19 — an RCA for every completed recording

Each DiagnosticReport now contains deterministic RootCauseAnalysis, even for
empty, quiet, mixed or insufficient captures. Independent CPU, headroom,
swap-out, thermal and disk-capacity assessments retain simultaneous signals,
show valid/qualifying sample counts and explain evidence limits. The analysis
lists up to three measured CPU contributors below the old verdict threshold,
with observation coverage and explicit top-16/name-grouping limitations. No
causal proof, network wait, disk latency, app hang or GPU attribution is invented.
Duplicate/out-of-window/nonfinite evidence cannot manufacture repeated signals.

The existing WHY/NEXT bands now show this investigation and its next
discriminating check. Recent runs keeps the last ten completed reports in memory
until app exit; it is not durable history. Dated recordings are explicitly
labelled not live, and history selection clears unrelated comparisons.
Recording rates reset before every capture; full-suite tests caught and fixed a
Swift protocol default-dispatch regression by making the async reset mandatory.

Final build and 88 tests pass, including RCA edge cases, bounded history and two
successive recording windows. Native live recording generated all five
assessments and named contributors; the dated report survived New check and
reopened through Recent runs. The headline now leads with the strongest measured
signal rather than the legacy generic verdict. No personal shell configuration was executed, no processes
were stopped as remediation, and no release/sign/commit/push occurred. Existing
whole-product design-gate and accessibility/overhead qualification gaps remain;
this change does not declare the entire product finished. Tracker: StorageDaddy
issue #29, extension comment 5742816555.

## 2026-09-19 — zsh startup experiment and visible ports

Added Diagnose → Diagnose terminal startup: a permission-gated local zsh
experiment, separate from passive recording. Minimal baseline skips personal
startup files; configured profiling requires fresh consent on every run. Native
pseudo-terminal launch, minimal environment, fixed executable/arguments, private
temporary bootstrap, 10-second deadline, 256 KiB output bound and cancellation
protect the host UI. Only this app's unreaped diagnostic child/original process
group is stopped; detached descendants and startup side effects can remain.
Inherited application descriptors are closed before exec. Normal probe completion
suppresses history saving and logout scripts. No real configuration edits or raw
output persistence. Results contain elapsed time and validated zprof name/call/
self/inclusive rows; both LF and CRLF work.

This is one-trial startup attribution, not first-prompt/typing measurement,
terminal-environment parity, repeated-trial statistics, or causal before/after
proof. Global zshenv still runs for the minimal baseline. Externally supplied
ZDOTDIR and terminal-specific integration are not reproduced; the review explains
these limits and that shell execution is not a sandbox.

Ports now lead the Ports table in larger cyan monospaced text with observed bind
scope and partial-coverage disclosure. Six numbers are shown per row, with an
explicit remainder; numeric search matches lead the preview. All endpoints remain
in the inspector/copy action. CPU and running duration remain in Processes and
the inspector, leaving space for ownership. Other live tables have wider,
two-line port summaries.

Build and 79 tests pass (seven shell tests: parser, consent, synthetic profile,
timeout, noisy output/early exit, LF/logout suppression, cancellation). Native UI
verified disabled configured action before consent, minimal baseline result,
Escape dismissal, leading ports and owner/endpoint inspector. Personal startup
files were not executed during development. Dual independent read-only reviews
found no remaining concrete P0/P1 after fixes; source design score is provisional.
Full VoiceOver, smallest-window acceptance, real-config profiling and the legacy
web-shaped design-receipt gate remain unqualified; that gate still fails. No
signing, release, commit or push. Tracking: StorageDaddy issue #29, extension
comment 5742645207.

## 2026-09-19 — tooltip refinement

Owner confirmed hover tooltips are visible and requested better styling and
stacking. Moved tooltip rendering from each control into a page-level anchored
overlay above the native split/table, with non-interactive high stacking priority.
Added dark-green surface, pale-mint text, subtle mint border, soft downward shadow,
more padding and line spacing, and horizontal edge clamping. Native accessibility
help remains. Build and 72 tests pass; the local app was reopened. The owner's
visibility confirmation applies to the previous rendering; this revision's live
hover placement is not independently visually qualified by automated tests.

## 2026-09-19 — owner-requested polish, icon and stability pass

Preserved the approved black/mint styling. Removed the internal DADDY SERIES
label; Diagnose slowdown now clearly opens diagnostic setup rather than implying
that clicking starts a recording. Added a matching generated mascot icon in the
sidebar, own-process row and application icon, plus native ICNS representations
and reproducible build-icon script. Source artwork is
`Sources/PerformanceDaddy/Resources/PerformanceDaddy.png`; generation used the
owner-supplied mascot as a style reference, holding a performance monitor instead
of a storage box, with no text and transparent outer corners.

Added control help coverage, mint hover feedback, keyboard Command-F search,
readable keyboard-dismissable measurement help, clearer single empty-state
recovery and a wider inspector minimum. Native checks verified help content,
Escape, Command-F, no-match recovery, Processes/Ports/Agents/Memory navigation,
diagnostic setup and a complete real 15-second recording. New icon is visible in
the sidebar and process row. Root did not stop any user process during UI checks.
Toolbar/column help also has a high-contrast in-app hover overlay with native
accessibility help retained. Automated coordinate clicks did not reliably generate
hover entry; owner hover confirmation was requested. Do not claim this part has
passed live hover verification from AX help strings alone.

Hardened invalid memory/timing conversions and oversized family-memory sums.
72 tests pass, including 200 snapshot/filter replacement cycles and numeric edge
cases; no red-before mutation demonstration was run. Independent reviews found
and rechecked the duplicate empty-state fix; no remaining concrete P0/P1/P2 in
this bounded pass. Design review 39/40 is provisional source-only, not release
qualification. Minimum-window/full VoiceOver and legacy receipt-gate gaps remain.

Two pre-existing morning crash logs reported CODESIGNING Invalid Page. The local
launcher now stages and atomically replaces the executable rather than overwriting
its inode. This mitigates a plausible launch hazard, not a proven explanation of
those old crashes. Fresh standalone binary verification passed; within the unsigned
development bundle, code verification passes with resources excluded, while full
bundle verification fails because it has no sealed resource envelope. No signing
or notarization was performed. The development app launches and remains responsive;
this is not a promise that every possible future crash is eliminated.

## 2026-09-19 — sourced catalog, running-code identity and confirmed exits

Continued the approved process-understanding scope after the owner asked for
persistence. Catalog v2 covers 37 services, paraphrasing their shipped macOS
manuals. Matches use exact executable names in bounded system locations and reject
lookalike/traversal paths; they remain explicitly unauthenticated role hints.
Rows show service categories or app names; search includes roles and observed
ancestor-app context. Ancestry is cycle-safe, capped at 256 steps and rejects
younger replacement parents. It suggests launch context, not verified ownership.

Explicit running-code validation uses Security.framework dynamic code checks,
with network access disabled and PID/start/UID/executable checks before and after.
Apple/developer/unattributed/unavailable outcomes do not establish necessity,
safety, online revocation or notarization. Removed the old unvalidated static team
display. Evidence state resets across executable or UID changes. A shared actor
serializes requests; inspector task cancellation discards interrupted results and
skips cancelled queued work. Code identity and startup have separate accessible
headings; technical validation detail is disclosed rather than always expanded.

Stop outcome and history now use independent read-only native identity presence.
BSD start-identity mismatch or an ESRCH existence check confirms the original
instance is gone; signal zero delivers no signal. Permission/read failures remain
unknown, and missing resource samples no longer falsely report Exited. Confirmed
exit does not imply that the stop caused it or establish why a later process began.
The journal retains its 100-watch/500-event/24-hour in-memory limits.

Build and 69 tests pass. Native tests validate an Apple-signed disposable child,
reject stale identity, skip cancelled validation, distinguish presence/reuse/exit,
and exercise reviewed child termination through the view model and journal. Pure
tests cover credential/executable evidence keys and missing-sample honesty. Final
native app verification found photoanalysisd by role and validated its running
Apple identity, with visible Code identity/Startup headings and details disclosure.
Live Warp inspection also returned a validated developer identity and signing team,
separately from the path-based app association; no real user process was stopped.
The existing development harness was refreshed and reopened; no release occurred.

Independent source reviews found no remaining concrete P0/P1/P2 in this increment;
design score 37/40 is source-only. Full minimum-window, keyboard/VoiceOver and the
legacy web-shaped receipt gate remain unqualified. A five-second debug profile
found the main thread mostly waiting (4,100 of 4,229 samples at mach_msg), but live
debug monitoring during checks still showed roughly 5–8% CPU. This is neither an
energy benchmark nor an optimized-build overhead qualification. Profile artifact:
`artifacts/monitor-profile-2026-09-19.txt`.

Still open: active/registered startup-state evidence, comprehensive third-party
ownership, retained baselines/alerts, effective config analysis, qualified raw
fan/GPU providers and opt-in local telemetry. No new dependency, privileged helper,
config edits, startup writes, telemetry service, commit, push or distribution.

## 2026-09-19 — process understanding increment

Owner approved the bounded process-understanding proposal in StorageDaddy #29.
Added always-visible sortable Running duration, app-path ownership explanations,
an exact-path catalog v1 for cfprefsd/distnoted/coreaudiod sourced from the shipped
macOS manuals, and explicit unknown/unverified ownership states. An on-demand
inspector reads signing team metadata (not validated publisher identity) and
matches the selected executable against launch agent/daemon configurations.
It retains only policy projections, not raw plist dictionaries, environment or
argument values. Reads refuse symlinks and nonregular/over-128-KiB files; lazy
enumeration caps 512 files/2,048 entries. No startup registration database or live
override inspection is claimed; active status stays unknown. System Settings is
opened only through the explicit review action; no startup setting is changed.

Successful reviewed stops now feed an ephemeral journal: 500 events, 100 watched
stops, 24-hour expiry even while sampling is paused. Signals, missing observations
and later matching executables remain distinct. PID reuse, existing siblings,
different users/paths, ambiguous replacements and unknown launch causes are
handled conservatively. The toolbar history remains available after a row exits.
No cross-launch retention, telemetry, uploaded metadata, helper or dependency.

Build and 58 tests pass, including a real disposable child stop through the view
model and pure lifecycle/policy/bounded-file regressions. Native verification
confirmed duration sorting both ways, duration remaining beside the inspector,
history empty state, and a real cfprefsd policy match with disclosed partial
coverage (512 files, 105 ms on this check). This is not universal startup coverage
or a whole-app overhead benchmark. Independent review findings about disappearing
duration, unbounded directory listing and paused expiry were fixed. Full minimum
window/VoiceOver and the legacy web-shaped design receipt gate remain unqualified.
Broader catalog coverage, verified publisher attribution, confirmed exits and
registered/enabled startup-state providers remain future qualification work.

## 2026-09-19 — evidence correctness and bounded process resource history

Owner requested all six roadmap areas. This is the first hardened increment,
not completion of that request. Diagnosis no longer calls allocated swap active
paging, treats mixed before/after results as inconclusive, rejects insufficient
or mismatched captures, and preserves thermal worsening even when another metric
is missing. A single low-headroom sample does not establish sustained pressure.
Development-tool CPU and process-name aggregates no longer imply a proven cause.

Added up to five minutes of resident-memory history for the largest 512 process
identities, capped at 150 samples each, in memory only. Missing observations,
PID reuse, pause and long gaps reset continuity. Inspector shows net change,
peak, duration and observation count, with no leak claim. Native libproc rusage
adds optional physical footprint and cumulative disk byte counters. Failed task
reads no longer become zero-resource rows; a final start-time check rejects PID
reuse across native reads. New fields are not added to snapshot export yet.

Build and all 50 tests pass. Focused regressions cover comparison edge cases,
history retention/identity/gaps, and live self-process rusage availability and
counter monotonicity. Native UI verified real resource values, wrapping and
lower inspector scroll reachability in the current window. Independent source
reviews found no P0/P1; both P2 correctness/copy findings were fixed and detail
section headings gained accessibility header traits. Full VoiceOver, minimum
window, physical sleep/wake, sustained/release energy qualification remain open.
Observed debug monitor CPU varied around 4–10% during UI interaction; this is not
a certified overhead result and remains a product concern.

Remaining broader scope: effective configuration analysis, background-service
registration/restart evidence, alerts and retained baselines, qualified fan/GPU
providers, and opt-in local telemetry. No config contents, telemetry, privileged
helper, fan controls, new production dependency, release or commit were added.

## 2026-09-19 — configuration inventory

Implemented the Configuration sidebar destination using the approved Daddy-series
list, searchable rows, clickable sort headers and selected-file metadata/Finder
reveal. The on-demand collector checks 12 known user shell/agent locations and
13 known config filenames in up to 32 observed eligible user working directories.
It does not read file contents, follow file or directory symlinks, scan recursively,
edit files, delete data or include configuration paths in snapshot exports.
Protected processes, sensitive roots, Library/app data, caches and dependency
directories are excluded from project candidates. This is a bounded inventory,
not every config on disk; cwd association does not prove a file was loaded.

Native checks found actual shell/Git/Codex/Claude/project files and verified sort
reversal, search, selected metadata, and hiding details when filtered out. Live
testing caught irrelevant service-directory flooding and an unbounded list layout;
both were fixed. Independent source reviews rechecked first-sample readiness,
separate metadata/process timestamps, hit targets and existing-target symlink tests.
Minimum-window and full VoiceOver qualification remain open; broader design gate
still has legacy receipt failures. No telemetry exporter was enabled.

Codex OTEL research supports an optional local timing/usage adapter, not raw log
ingestion: official documentation says tool-result events can contain output
snippets even when user prompt logging is off. Integration is not implemented.

## 2026-09-19 — measured workload-derivation optimization

Resolve agent metadata once per immutable process observation, cache agent roots
per snapshot, and reuse a MainActor-confined byte formatter. UI output, reviewed
actions and polling frequency are unchanged. Added cache-count invalidation and
formatter parity coverage plus a fixed 1,000-process derivation benchmark.

The same debug benchmark measured about 23 ms/update before and 9 ms/update
after (10 iterations each). It covers sorting, agent grouping/counts and byte
formatting after constructing input; it does not measure total sampler cost,
SwiftUI rendering, whole-app CPU or release energy usage. Do not generalize this
to a whole-app percentage improvement. Build and all 35 tests pass.

## 2026-09-19 — native memory and thermal evidence

Added a read-only Memory & thermals popover to every live page, preserving the
approved Daddy-series controls and palette. It reports wired, compressed,
file-backed, free and inactive VM categories with explicit overlap limitations;
swap-in/out VM-byte rates and measurement interval; ProcessInfo thermal state,
Low Power Mode and optional public IOKit CPU speed/scheduler allowances.
VM statistics are read once per system sample instead of duplicating the read
in WorkloadSampler. Redacted snapshot exports explicitly include the new fields.

Rates use ContinuousClock, reject invalid/reset counters and gaps above 30
seconds, and reset on pause/resume. Missing readings remain unavailable, not
zero. CPU allowances are not clock-speed measurements or proof of a thermal
cause. No qualified raw fan/temperature provider is implemented; both are
explicitly unavailable. No fan writes, helper, dependency or config scan added.

All 33 tests pass. Focused tests cover native reads, rate calculations and reset/gap behavior,
optional power values, export privacy, and actual view-model pause transitions.
Native inspection verified values, lower-content scrolling, and Escape
dismissal. Independent source reviews found no remaining P0/P1 in this increment;
the pause-continuity finding was fixed. Full VoiceOver, minimum-window fit,
hardware sleep/wake testing and release overhead remain unqualified. This is
an implemented increment, not completion of the broader product or fan support.

## 2026-09-19 — daily workflow hardening and evidence export

Implemented cycle-safe indexed process ancestry with start-time guards against
parent-PID reuse. Same-provider wrappers collapse into a responsible agent row;
separate sibling launches and different agent providers stay inspectable. Native
Devin grouping was verified live. Derived rows and aggregated agent rows are
cached per relevant inputs, with cache-invalidation regression tests.

Added row context actions for copy PID/project/endpoints, project opening,
executable reveal, and reviewed single-process/family stops. Bulk agent-family
review deduplicates overlapping targets. Added explicit CPU/RAM/port accessibility
labels and a footer with the observer process CPU/RAM and scan duration.

Added redacted versioned JSON export through a native save panel. Export contains
anonymous process/parent aliases and resource/port evidence, never process names,
paths, raw PIDs, start times or bind addresses. Private argv/environment/transcripts
are not collected. Focused tests cover redaction and unavailable/nonfinite values.

Build and all 26 tests pass. Native checks verified RAM header reversal, grouped
agents, context-menu contents, export explanation and cancellation, and Memory
layout with overhead readout. No real process was stopped and no user export file
was written during UI verification. Steady-state/release overhead, minimum-window
and full VoiceOver acceptance remain open. This completes this daily-workflow
increment, not the broader regression-lab/workflow-experiment roadmap.

## 2026-09-19 — Daddy series and local agents

Owner selected exact StorageDaddy styling and confirmed local agents only.
Implemented the original black/mint palette, rounded lowercase brand, shared
original artwork, outlined/prominent controls, custom full-width navigation,
flat native lists and accessible clickable sort headers. No StorageDaddy source
or cloud integration changed. Previous system-appearance design notes are historical.

Agent metadata recognition now includes Codex, Claude, Devin, Hermes, Aider,
Gemini CLI, OpenCode and Cursor CLI. Generic interpreters, ambiguous `agent` and
substring matches remain excluded. This inventories identifiable local processes,
not conversation activity; wrapper/helper processes can have separate rows.

Build and all 18 tests pass. Native UI verified local Devin rows, project/RAM/CPU,
Devin's three-process family inspector, and opening/cancelling the exact-target
stop review without stopping any real agent. The prior inspector automation crash
did not recur after replacing Table with the StorageDaddy-style native List.
Owner feedback: “it automatically looks much better.” Independent design review
35/40, source audit 15/20. Full VoiceOver and minimum-window qualification remain
open; no release or complete design-gate pass is claimed.

## 2026-09-19 — daily-table refinement

Adapted StorageDaddy's native app-icon and readable-path presentation patterns;
StorageDaddy itself is unchanged. Native Process/CPU/RAM/Ports headers now own
sorting and direction, replacing the separate picker. Quiet unstriped rows,
bounded 64px icon raster caching, neutral CLI initials, trailing numeric values,
deduplicated port labels and concise coverage status reduce visual noise.

Native dark-mode screenshots at 1180×740 verified the table; RAM header clicks
verified ascending and descending order, and Ports starts in numeric ascending
order. Final PID-only root-directory labels were verified after relaunch. Build
and all 15 tests passed. A subsequent review raised the window minimum to
980×800 to accommodate Memory and the inspector. Memory's final layout was
visually checked after relaunch; minimum-width inspector acceptance, VoiceOver
and stop-dialog UI acceptance remain open.

Independent review: design 34/40 for this bounded refinement; technical audit
found two minimum-window layout risks and several P2 issues. The Swift-unsupported
web detector returned an empty result, which is not treated as native evidence.
The broader visual completion gate remains open, not a release approval.

## 2026-09-19 — daily local utility

Implemented live Processes, Ports, Agent sessions and Memory destinations using
the Evidence Workbench composition. The owner asked to proceed with a daily-use
utility after reviewing the three concepts; implementation uses A as the working
basis. Existing incident diagnosis remains available.

- Native libproc process inventory includes idle processes, parent PIDs, start
  times, executable paths, available working directories, CPU and resident RAM.
- Native TCP listener and bound UDP inventory includes IPv4/IPv6 addresses,
  loopback status, process ownership and partial-coverage disclosure.
- Native Codex/Claude process families aggregate descendant CPU/RAM and ports.
- Five-minute bounded RAM history, macOS pressure, swap, compressed memory,
  menu-bar RAM readout, pause and adaptive polling.
- Reviewed SIGTERM/SIGKILL actions for selected rows, families or all matching
  rows. Immutable target lists, UID/system restrictions and start-time checks
  guard against stale PID selections. Exit is rechecked after signalling.
- Corrected the original process-count truncation and Mach-time CPU unit bugs.
- Eight focused workload tests pass, including real temporary TCP/UDP sockets,
  isolated SIGTERM/SIGKILL children, idle inventory, agent ancestry/cycle handling,
  stale PID rejection and independent CPU-counter validation.
- A local unsigned runnable app is available at `.build/PerformanceDaddy.app`;
  `sh scripts/run-local.sh` reproduces it. No commit, push or release.

Live verification: real Processes, Ports, port search, RAM totals and Agent
sessions were inspected through native UI automation. Window overflow was
corrected and visually rechecked. Inspector and confirmation-sheet UI acceptance
remains incomplete: SkyComputerUseService crashes with an Array.remove assertion
when reading the selected inspector, while PerformanceDaddy remains responsive.
The underlying signal operations were verified only on disposable test children.

Known limitations: metadata-only agent detection cannot identify every wrapped
Node launch or conversation; RAM is labelled as an estimate; libproc coverage
varies with macOS permissions. Release overhead qualification, full accessibility
acceptance, workflow experiments and historical regressions remain open.

## 2026-09-19 — local diagnostic vertical slice

PerformanceDaddy is an uncommitted, local-only native macOS prototype tracked
by [StorageDaddy issue #29](https://github.com/sarthakagrawal927/storagedaddy/issues/29).

The product north star is broader than this slice: a Mac performance
investigator and regression lab with live workload, listening-port and active
Codex/Claude session context, known-good baselines and repeatable workflow
experiments. The current build proves only the first incident workflow.

Implemented:

- Owner-selected Calm Triage visual direction with NOW / WHY / NEXT hierarchy.
- Read-only native sampling for system CPU, process CPU and resident memory,
  memory headroom, swap use, disk headroom and thermal state.
- Bounded 15-second and two-minute recordings with cancellation.
- Deterministic findings for temporary development load, memory pressure,
  thermal pressure, dominant process load, healthy capture and inconclusive
  evidence.
- Explicit confidence, unavailable-evidence handling and no-change disclosure.
- Comparable follow-up captures that preserve the baseline and report improved,
  worsened, unchanged or inconclusive outcomes.
- Contextual next actions, evidence-method disclosure and a RESULT band.
- System light/dark appearance, semantic typography, compact band fallback and
  explicit VoiceOver status labels.
- Seven focused diagnostic-engine tests and a successful native package build.
- Live 15-second native click-through verified with an accessible result tree.

Not implemented or claimed:

- Live workload and process-tree views, listening ports, active Codex/Claude
  session grouping, disk/network/GPU I/O, login/background-item attribution,
  known-good baselines, workflow experiments, report export, retained history,
  reviewed process actions, StorageDaddy handoff, packaging, signing or
  distribution.
- The sampler caches process names and maintains a bounded top-process set, but
  adaptive cadence and a release-profile overhead budget are still required.
- No configuration, process, login item or user file was changed by the app.
- No commit, push, GitHub repository creation, release or deployment occurred.
