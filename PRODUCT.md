# PerformanceDaddy

PerformanceDaddy is a native Mac performance investigator and regression lab.
It helps people understand why a machine or important workflow became slower,
what changed, what is responsible, and whether a reviewed action measurably
helped.

The first incident surface records a bounded local diagnostic window,
correlates system and process evidence, explains the likely cause with an
explicit confidence level, and verifies whether a reviewed action helped. That
surface is the opening wedge, not the complete product.

## North star

Move from “what is using CPU?” to “why did this experience regress?” A useful
answer can combine process ancestry, CPU scheduling, memory pressure, disk and
network I/O, GPU work, thermal and power state, application versions,
background activity, listening services and a timeline of locally observed
system changes. PerformanceDaddy distinguishes correlation from causation and
uses repeatable experiments when observation alone cannot prove a cause.

## Product modes

### Live workloads

Show active work as responsible process trees rather than an undifferentiated
PID table. Each workload can expose CPU and memory now, uptime, owning app,
parent terminal or IDE, project working directory when safely available, and
related listening ports. Inspect, reveal and reviewed quit actions are useful
utilities; they support investigation rather than define the product.

Listening ports are first-class evidence. Show protocol, local port, bind scope,
owning workload and whether a listener is loopback-only or reachable from other
machines. Never infer safety from the port number alone.

Active Codex, Claude and Devin sessions are first-class developer workloads. Group
their agent process trees and show provider, project/cwd, parent terminal or
IDE, resource use, uptime, related ports and last observed process activity.
Only an owner-enabled prompt hook may derive a short latest-request label for
this view. Discard the full prompt after deriving the label; do not read replies,
environment values, command arguments or stored transcripts to populate it.
Do not equate stored transcript files with live sessions.

The focused Insight Agent Sessions wall uses the same live process families.
Detached hosts without lifecycle evidence remain in the process inventory rather
than becoming wall tiles. Terminal-attached agents remain visible when their
status hooks have not been installed.
Optional local provider hooks report lifecycle state and a bounded latest-request
label derived from an opted-in prompt. It distinguishes recent work,
waiting/stopped, explicit failure, and
unavailable status; process presence controls whether a tile remains visible.
The wall fills the screen, including when just one agent is present. Resident
RAM changes relative tile area within bounds and is an estimate, not unique
physical memory owned by the agent.
While the app runs, a compact outline-only menu bar battery shows one green,
amber or red mark per agent when twelve or fewer are present. Larger counts use
a proportional color strip; the exact count, per-agent states, workspace and
available latest-request labels remain in the menu and full-screen wall. The
menu uses the wall's lifecycle evidence and removes exited processes rather
than treating process presence as proof of active work.

### Investigate an incident

Capture a slowdown while it happens, reconstruct the responsible workload and
system activity, explain the evidence in plain language, and preserve enough
context for a comparable follow-up.

### Find a regression

Compare the current Mac or workflow with a user-chosen known-good baseline.
Highlight material changes in application versions, startup/background items,
resource behavior and workload timing without claiming every coincident change
caused the regression.

### Optimize a workflow

Measure repeatable work such as an Xcode build, test suite, dependency install,
AI inference task, app launch or export. Run multiple local trials, report
variance, identify the limiting resource, and test one reviewed intervention at
a time. The result is a reproducible performance record, not a generic “faster”
score.

### Remember performance, within limits

Keep bounded local baselines and incident summaries so the user can answer
“when did this get worse?” Raw high-frequency samples expire quickly; compact
derived evidence is retained only with clear controls and deletion. No cloud
account or telemetry is required.

These are product requirements, not current implementation claims. Each sensor
and intervention must earn inclusion through accuracy, observer-overhead and
privacy tests.

## Purpose contract

- **Audience:** Mac users—especially developers—who can see that their machine
  is slow but do not want to interpret Activity Monitor themselves.
- **Outcome:** Replace vague performance anxiety with a specific, evidence-backed
  explanation, locate regressions, and prove whether a safe intervention helped.
- **Mechanism:** Low-overhead native sampling, responsible workload grouping,
  deterministic finding rules, plain-language incident triage, known-good
  baselines, repeatable workflow experiments and comparable follow-up captures.
- **Proof:** Every conclusion exposes its measurements, time window, confidence,
  limitations, and whether any change occurred.
- **Next action:** Run a quick check while the slowdown is happening.

## Product boundaries

The app is not a RAM cleaner, malware scanner, fan controller, generic menu-bar
monitor, or one-click optimizer. It never silently kills a process, disables a
background item, edits configuration, or deletes data. Persistent-footprint
intelligence and lifecycle cleanup belong to StorageDaddy: applications and
support data, caches, builds, dependencies, models, logs, duplicates, AI data,
and abandoned tool or project artifacts. Configuration is only one piece of
that ownership evidence and is never treated as junk by file type alone.

PerformanceDaddy may attach measured runtime relevance to a persistent
candidate and hand it to StorageDaddy for ownership, recovery and cleanup
review. StorageDaddy may ask PerformanceDaddy to verify whether removing or
disabling a reviewed item changed runtime behavior. Neither product silently
optimizes the Mac.

For the App access surface, the owner also requested narrow, explicit actions:
move one user-owned LaunchAgent file to Trash after exact-file review, or reset
one app's supported macOS privacy decision after exact-app and category review.
These do not run during sampling and do not replace StorageDaddy's wider cleanup.

The current macOS 14+ application is publicly distributed as a signed and
notarized download with local Sparkle updates. Telemetry and payments remain
outside the product. A single saved capture can anchor a resource comparison;
application/startup change attribution, repeatable workflow experiments, and
compact retained evidence remain later product requirements.
