# PerformanceDaddy

A native Mac performance investigator and regression lab.

PerformanceDaddy shows local processes, occupied ports, local coding-agent
families and RAM usage, with reviewed process termination and a separate
incident-diagnosis workspace. It runs locally without dependencies or accounts.

## Daily use

- **Understand a process:** click **Running** to sort duration; it remains visible
  while inspecting a row. **What is this?** gives app-path association, observed
  ancestor-app context, documented role hints for 37 macOS services and an explicit
  unknown fallback. Search also matches roles, categories and app context. Catalog
  matches require an exact executable name in a system location, not authentication.
  **Validate running code** performs an explicit, offline native identity check.
  Apple/developer validation is separate from inferred app association and is not
  proof of safety or necessity. Online revocation/notarization is not checked;
  unavailable evidence does not establish invalid code. Results reset when the
  selected PID/start, UID or executable changes; checks are serialized and cancelled
  when the inspector closes.
  **Inspect startup metadata** checks bounded launch configurations on demand and
  shows exact executable matches, configured policy and coverage. A selected row
  is also observed running in the latest sample, but configuration plus observation
  does not prove the policy launched it, that it is enabled, or why it returned.
  Startup inspection does not validate publisher identity.
  **Review Login Items in Settings** opens the supported macOS control without edits.
- **Stop history:** the clock-arrow toolbar button shows successful reviewed stop
  requests, missing observations, confirmed exits and later matching executables.
  A separate read-only native identity check confirms that an original instance
  is gone; missing samples or denied inspection do not prove exit. Reappearances
  are not proven automatic restarts. History
  is stored locally with a 500-event, 100-watch and 24-hour bound. Events survive
  relaunch; active exit watches do not.
  Existing sibling instances, rejected signals and pre-stop starts do not count.

- **Configuration:** on-demand metadata inventory of known shell/agent paths
  under the user's home folder. Search, sort and select a file for size,
  modification date and Finder reveal. No content
  reads, symlink following, recursive scan, edits or deletion. This does not prove
  a config was loaded, resolve inherited settings or inventory every config.
- **App access:** on-demand, bounded inventory of apps in the top level of
  `/Applications` and `~/Applications`, plus user and shared launch-agent and
  launch-daemon files. It shows exact executable matches to the latest process
  sample and app privacy purpose strings. This is a partial audit: a launch file does not
  prove an item is enabled or launched automatically; a purpose string does not
  prove a permission grant. Login Items and other apps' privacy grants require
  confirmation in System Settings. An optional local code-signature check shows
  declared entitlements, which also do not establish privacy grants.
  The owner can record dated Settings observations for each app and category;
  these are stored locally, are not live grants, and should be rechecked after
  app or settings changes. Apps with a sensitive category marked allowed and
  startup evidence move to the top for review, without a safety score. The
  audit does not read the TCC database, request permissions, or classify apps as
  safe or malicious. After an exact-item review, a user-owned LaunchAgent file
  can be moved to Trash; this does not stop a running service and the app may
  recreate it. Shared launch files are revealed in Finder for manual handling.
  For supported categories, a user-confirmed allowed note exposes a reviewed
  per-app `tccutil` reset. Resetting forgets the decision and may let the app
  ask again; keeping access off requires System Settings. Neither action runs
  during scanning.
- **Processes:** search by name, PID, project folder or port; sort by CPU, RAM,
  name or port; select a row for its context and children. Command-click selects
  multiple rows.
- **Ports:** TCP listeners and bound UDP sockets, grouped by owning process.
  Search a port number to find its owner. The inspector shows IPv4/IPv6 bind
  addresses and distinguishes loopback from non-loopback binding. This is local
  socket inventory; it does not probe other machines.
- **Agent sessions:** exact-name recognition for Codex, Claude, Devin, Hermes,
  Aider, Gemini CLI, OpenCode and Cursor CLI, including Claude's versioned native
  installer executables. Same-provider wrappers collapse
  into one workload with descendant CPU, resident RAM and ports; sibling
  launches remain separate. Generic Node/Python wrappers may not be identifiable.
  This is local process evidence, not cloud sessions. **Insight Agent Sessions**
  opens a focused full-screen wall. Each observed terminal-attached agent family
  or locally instrumented background family is a tile; detached, uninstrumented
  app-server hosts remain in the process list unless they send a hook. An
  instrumented shared Codex host has its own clearly labeled tile. Tiles
  fill the display, with relative area based on observed resident RAM and capped
  so one process cannot hide the rest. A single agent fills the wall. Green
  means a recent work event, orange
  means stopped, waiting for input or status unavailable, and red means an
  explicit provider failure event. A tile disappears when its process exits.
  The app checks process presence every two seconds even when the wall is closed;
  new processes appear on the regular live sample. Tiles also show the
  workspace, latest request label when a prompt hook supplies one, host, uptime
  and last lifecycle event.
  Resident pages can be shared across families.

  While PerformanceDaddy runs, its compact outline-only menu bar battery shows
  one colored mark per session through twelve agents. Above twelve, the marks
  become a proportional color strip; the exact count remains in the panel.
  Clicking it shows every agent's exact state, workspace and available latest
  request, plus a shortcut to the full-screen wall. The same lifecycle evidence
  drives both views; a green mark is a recent work signal, not a process-presence
  claim.

  Use **Set up statuses…** on Agent sessions to copy Codex, Claude or Devin lifecycle
  hook JSON into the existing user-level hooks file. Merge the event entries;
  do not replace other settings. The bundled app executable's `--agent-hook`
  mode finds its local agent ancestor and sends the event, process identity,
  workspace basename and, for prompt events, a short latest-request label
  through a local macOS notification. It derives that label from the submitted
  prompt, then discards the full text. It does not read replies, transcripts,
  environment values or command arguments. Hook
  trust/reload is controlled by the provider. An uninstrumented terminal agent remains
  orange with “Status unavailable”; CPU use alone is not proof of agent work.
  Working evidence expires after five minutes without another event. The default
  hooks also observe compaction, Claude tool failures, and Claude MCP input
  requests. Claude's `StopFailure` turns a tile red for API failures, except its
  documented `rate_limit` error, which shows amber as “Rate limited.” Devin
  documents no QPS wait hook, so a QPS pause cannot be identified immediately;
  it becomes amber as “Status unavailable” if no work event arrives for five
  minutes. Codex does not expose a general crash event through these hooks.
  Hook events are best-effort and
  may be missed if the app is closed or the provider cannot link the hook
  process to its local agent process. Status is held in memory while the app
  runs; older sessions may need to reload hooks or restart before they report
  an event. Codex hooks attach to the nearest matching client process when
  present. A shared background host's hook stays with that host because its
  working directory cannot identify the terminal client. The hook hashes the
  provider session ID locally so a request label is carried forward only for
  the same session. Terminal sessions without directly attributable hooks
  remain status unavailable.
  Other recognized CLI agents can use the
  same `--agent-hook "Provider name"` input contract when they expose compatible
  lifecycle hooks; no provider hook is installed automatically. This remains a
  process-family view: multiple conversations hosted by one app can share a tile,
  and its RAM cannot be apportioned reliably among those conversations.
- **Memory:** five minutes of in-memory RAM estimates, macOS memory pressure,
  swap, compressed memory and the largest resident processes. The menu bar
  panel retains the RAM estimate and pressure while the window is closed.
- **Process resource history:** the inspector shows resident-memory change and
  peak over up to five minutes for the 512 largest processes (150 samples each).
  A large net increase is a review cue, not a leak diagnosis. Histories reset
  across missing observations, pause and long gaps. Physical footprint and
  cumulative native disk-read/write counters are separate measurements; agent
  inspectors explicitly show the root process, not family totals. Physical
  footprint and cumulative disk counters are also included in redacted snapshot
  exports when available; they are not disk throughput or family totals.
- **Stop:** review selected processes, a process family, or all currently
  matching rows. Normal stop sends SIGTERM; force stop explicitly sends SIGKILL.
  The review freezes exact targets and checks PID/start-time identity again at
  execution. Protected system processes and other users' processes are excluded.
  Stop results distinguish confirmed exits, still-observed processes and unknown
  exit status. A successful signal alone does not establish successful termination.
- **Context actions:** right-click a process to copy its PID, project path or
  endpoints, reveal its executable in Finder, or review stopping its family.
  Agent bulk-family reviews deduplicate overlapping targets.
- **Export:** the share button saves a versioned local JSON snapshot. It omits
  process names, paths, raw PIDs, process start times and bind addresses, retaining
  anonymous parent relationships, agent types, resource measurements, coverage
  and port numbers. It does not claim a cause or a verified improvement.
- **Monitor overhead:** the footer exposes this app's CPU, resident RAM and latest
  collection duration. These are measurements, not a certified overhead budget.

Snapshots refresh about every ten seconds and back off to at most fifteen
seconds when collection takes longer. Socket inventories refresh about every
thirty seconds at the default cadence. Initial and manual refreshes remain
immediate. Pause freezes the display. Collection reads process metadata, not
prompts, transcripts, environment variables or command arguments.

## Run locally

```bash
swift test
swift run PerformanceDaddy
```

For a Finder-launchable development app and working menu bar:

```bash
sh scripts/run-local.sh
```

This builds an unsigned local app under `.build/PerformanceDaddy.app`. Quit a
previous running copy before rebuilding. No release or installation is performed.

Use `swift run PerformanceDaddy --preview-fixture` to inspect the selected UI
with clearly labelled synthetic before/after evidence.

Completed diagnostic captures are stored locally under Application Support and
bounded to the ten most recent runs. Reports are reconstructed with the current
deterministic analysis engine at launch. Corrupt or incompatible history is ignored
without preventing startup. In Diagnose, you can save one owner-selected capture
as a known-good baseline, compare later recordings with it, and delete the saved
baseline or all recent runs independently. Comparisons require similar workloads
and enough comparable evidence; the app does not claim that a coincident change
caused a regression. Local captures remain until replaced or explicitly deleted.

## Native release

Build and verify both architectures through XcodeBuildMCP before running
`scripts/package-release.py`. The script accepts only fresh Release products,
verifies bundled artwork, creates the stable `com.significanthobbies.performancedaddy`
identity and signs with hardened runtime. It never installs, notarizes or publishes
the candidate; those remain explicit release gates. The public update is
distributed through the signed Sparkle appcast at
`https://performance.daddyrad.com/updates/appcast.xml`.
The protected GitHub release workflow builds verified universal Release products,
signs and notarizes an exact tagged candidate, signs its appcast with the protected
Sparkle key, and retains the checked artifact. A manual dispatch on `main` then
deploys that artifact and appcast to the app-owned Worker, verifies the live bytes,
publishes the GitHub release, and records the site manifest on `main`. The
`production-release` environment requires approval; ordinary pushes run candidate
CI only.

Tracking spec: [PerformanceDaddy #2](https://github.com/sarthakagrawal927/performancedaddy/issues/2)

## Measurement limits

RAM in use is an estimate that excludes free and inactive pages; the pressure
label comes from macOS separately. Per-process resident memory includes shared
pages and cannot be summed into physical RAM usage. CPU uses 100% per logical
core. Ports may be unavailable due to permissions, process exits or bounded
scan limits; a non-loopback bind alone does not establish network reachability.

Repeatable workflow experiments, compact derived history with sample expiry,
disk/GPU/network throughput and StorageDaddy handoff remain future work.

Before/after diagnosis rejects insufficient or mismatched evidence and reports
mixed resource changes as inconclusive. Allocated swap alone is not a diagnosis
of active paging; a comparison does not establish what caused a change.
## Memory and thermal evidence

Open **Memory & thermals** in the footer of any live page for native VM categories,
swap-in/out rates, thermal state, Low Power Mode and optional macOS CPU allowances.
Rates reset after pause/resume, failed reads and long gaps. Memory categories
overlap; swap rates describe VM pages, not physical disk throughput. These values
are included explicitly in redacted snapshot exports.

Raw fan RPM and temperature readings appear as unavailable because this release
does not use unsupported private SMC interfaces. The supported signal is Apple's
system thermal state plus public power constraints. PerformanceDaddy does not
install a helper or change fan settings.
CPU allowances may also be unavailable on a particular Mac; unavailable never
means zero or unrestricted.
