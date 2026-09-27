# Design direction

## Daddy series — authoritative owner direction, 2026-09-19

The owner explicitly requested the exact styling and patterns from StorageDaddy
for the upcoming Daddy series. This supersedes the previous system-appearance
workbench and Calm Triage color treatment; the incident evidence hierarchy stays.
No new direction-selection round is required: StorageDaddy is the supplied design.

Owner clarification: Daddy-series branding is for external surfaces, not an
in-app label. Keep the shared visual language, but only show useful local-control
reassurance inside the app. PerformanceDaddy uses its own matching mascot holding
a performance monitor for the app icon.

Use its exact Tints: black app-owned surfaces, mint (0.42,0.79,0.62), pale-mint
secondary text (0.78,0.90,0.86), coral (0.90,0.46,0.40), blue (0.33,0.58,0.83),
cyan (0.27,0.70,0.75), amber (0.87,0.67,0.28). Retain its dark appearance, hidden
toolbar, rounded lowercase 17pt brand, 7pt-radius outlined/prominent controls,
32pt full-width navigation targets, mint 11% selected navigation, flat black lists
and explicit clickable column headers with accessible direction announcements.

## Agent signal menu bar, owner-selected 2026-09-27

The owner selected Signal from three menu bar directions, then requested a more
compact, outline-only battery without a numeric count or filled background.
Green, amber and red marks represent individual sessions in state order up to
twelve. At higher counts, one proportional color strip preserves the same
width. Clicking opens a restrained black panel grouped by state, with the exact
status, workspace and bounded latest-request label for each agent. The existing
RAM, pressure, socket and app controls remain in that panel. This is a compact
view of the agent wall's evidence, not a separate status source.

Reuse original StorageDaddy brand and PageDoodles assets unchanged, as authorized
by the owner. PerformanceDaddy keeps its own processes, ports, agent families,
memory evidence and reviewed process actions. StorageDaddy source is unchanged.

## Role of Calm Triage

Calm Triage is the selected incident-investigation surface, not the complete
information architecture. NOW / WHY / NEXT / RESULT turns one captured slowdown
into an understandable decision. Live workloads, ports, agent sessions,
regression comparison and workflow experiments should reuse its evidence
hierarchy and visual roles without forcing every task into the same four bands.

## Historical: first daily utility implementation

Evidence Workbench is the implementation basis for the owner's request to get
the project ready for daily process, port and RAM use. The native sidebar opens
Processes, Ports, Agent sessions, Memory and Diagnose. Live pages share a compact
memory/pressure/swap strip, searchable and sortable native table, multi-selection,
and a contextual inspector. Stop actions open an exact-target review with normal
termination as default and explicit force-stop choice. A menu-bar RAM readout
keeps the utility accessible when its window is closed. Native system appearance
and semantic text sizes are retained.

Daily-table refinement reuses StorageDaddy's native app-icon and readable-label
patterns, without importing its storage artwork or changing PerformanceDaddy's
appearance system. Process, CPU, RAM and Ports headers own sorting and direction;
there is no separate sort picker. Numeric columns align right, repeated socket
port numbers collapse in the summary, and rows use a quiet unstriped surface.
Owning-app icons are cached at bounded resolution; CLI processes use neutral
initials. Full executable and socket details remain available on hover.

## Historical: incident hierarchy, Calm Triage

Owner-selected on 2026-09-19 from four materially different directions.

The interface leads with a plain-language verdict, followed by three stable
bands:

1. **NOW** — the measured symptom and its time window.
2. **WHY** — the strongest causal explanation, healthy counter-evidence, and
   confidence.
3. **NEXT** — one safe recommendation plus a comparable verification action.

The system uses a cool fog background, deep ink text, coral for active load,
mint only for verified healthy signals, and blue for deliberate actions. Large
type carries the verdict; raw details are progressively disclosed. It avoids
speedometers, health scores, red alarm theater, decorative charts, dense card
grids, and one-click optimization language.

The product-native signature is the three-band conversion from symptom to cause
to action. Its deliberate risk is under-serving experts; expandable evidence
and process detail may be added without weakening the primary hierarchy.

The selected direction preview is
`artifacts/design/direction-c-calm-triage.png`.
