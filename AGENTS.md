# PerformanceDaddy agent instructions

PerformanceDaddy is a native, local-only macOS diagnostic tool. Preserve these
boundaries:

- Diagnose from measured evidence; never invent causes or claim improvement
  without a comparable follow-up capture.
- Keep sampling read-only. Do not terminate processes, alter login items,
  change configuration, clear caches, or delete files without a separate,
  explicit reviewed action.
- Do not shell out to monitoring commands from the product. Use supported
  native macOS APIs and disclose unavailable evidence.
- Avoid privileged helpers, kernel extensions, analytics, networking, and new
  production dependencies unless repository evidence proves they are needed.
- PerformanceDaddy owns runtime diagnosis. StorageDaddy owns storage and
  configuration cleanup.
- Agent Inbox owns agent lifecycle/status, attention, conversations, replies and
  the segmented agent-status battery. Keep this app's wall/menu/hook setup as
  migration compatibility until replacement parity is verified. Retain measured
  agent workload attribution and device battery/power diagnosis here.
- ContextDaddy owns skills/plugins/MCP, context/invocation policy, token history,
  provider allowance and run telemetry. Do not grow inbox or context-management
  features in PerformanceDaddy.
- Use XcodeBuildMCP for build, test, run, logging, and native UI verification.
- Run focused tests before the full package suite.
- Do not commit, push, sign, package, publish, or release without explicit
  owner approval.
