# Product direction: remove the human prompt bottleneck

`BAR BOY` can remain a working title. The durable idea is not another usage meter and not another general chat window. It is the place where parallel AI work returns to the human.

## The wedge

**Keep every agent moving without becoming the full-time scheduler for your own AI tools.**

The Mac status-bar app is the local scanner and control surface. MOMO RELAY on iPhone is the portable return queue. The physical Momo Labz character is the ambient surface. All three show the same priority order, and coral is reserved for moments that require intervention.

```text
Codex / Claude / Gemini / Cursor / Grok
                    |
       model + MCP + plugin + skill provenance
                    |
                YOUR TURN
        Mac / iPhone / desk display
                    |
       answer / approve / recover / route
                    |
             exact source session
```

## Defensible differences

1. **Attention, not activity.** Rank approval requests, questions, failures, and completed work above raw token charts.
2. **Provider-neutral session graph.** Codex, Claude, Gemini, Cursor, Grok, main agents, and subagents become one project-centric timeline.
3. **A physical presence.** The 3D-printed screen gives remote agents an ambient place on the desk and makes the product recognizable in a way software-only utilities are not.
4. **Outcome accounting.** Add commits, tests, deployments, files changed, and user wait time so the useful unit becomes finished work rather than tokens consumed.
5. **A visible trust ladder.** Every action is classified as suggest, prepare, ask-to-run, or pre-approved automation. Keep a local audit trail and a one-click stop switch.
6. **Return-to-work routing.** An alert should focus the exact task, terminal, IDE pane, or approval—not just announce that something happened.
7. **Local-first by default.** Session titles and project context stay on the Mac; cloud sync is optional and encrypted if it is ever added.
8. **Capability receipts.** Each return carries the model, MCP servers, plugins, and skills actually recorded in that session—not merely everything installed on the machine.
9. **One permission map.** Momo grants access once per supported provider or MCP server, sees the scope, and can revoke it without hunting through individual agent apps.
10. **Human-latency accounting.** Measure how long agents waited for a person, which questions caused the delay, and how much parallel work the return queue recovered. That makes BAR BOY an orchestration product rather than a decorative activity monitor.

## Authorization ladder

1. **Local session access:** no provider account required; the Mac reads enabled local adapters.
2. **Organization usage:** OpenAI and Anthropic usage endpoints require organization-level administrative credentials. Store them in Keychain and request the minimum scope.
3. **Remote MCP:** follow MCP OAuth discovery, OAuth 2.1, PKCE, resource binding, refresh-token rotation, and secure token storage.
4. **Consumer accounts:** only add ChatGPT, Claude, Cursor, Gemini, or Grok subscription data when the provider publishes a supported delegated interface. Never scrape cookies or collect provider passwords.

## What version 0.4 proves

- The Mac return queue, compact model strip, expandable tabs, and capability provenance are implemented.
- The same queue is exposed to the 3D-print display and the buildable iOS companion.
- Home, Agents, and Tools use one information model across Mac and iPhone.
- iOS pairing data is stored in Keychain and local alerts fire when foreground polling discovers a new return.
- Account access is mapped honestly; organization usage fetching, cloud relay, APNs, and write-back to source sessions remain next-stage work.

## Suggested build order

### Now — dependable attention

- Provider event fixtures and state adapters
- Click-to-focus the source app/session
- Snooze, pin, group by project, and alert escalation
- Honest linked quota adapters where providers officially support them

### Next — voice and command surface

- Talk, Text, Dictate, and Hands-free shortcuts
- Screen-context capture that is explicit and previewable
- Fast provider routing and compare mode
- Personal commands such as “summarize everything waiting on me”

### Later — delegated operator

- Prepare replies, patches, calendar events, and follow-ups
- Action allowlists per project and provider
- Confirmation receipts, undo where possible, and complete action history
- Encrypted phone/watch relay for urgent approvals away from the desk

## Naming territories

- **MOMO RELAY** — strongest fit for routing attention between people and agents
- **AGENT DESK** — clearest descriptive name and strong fit for the hardware
- **MOMO OPS** — more technical and expandable into teams
- **BAR BOY** — memorable working title, but less immediately legible as an AI product

Keep the application display name in one build setting and the in-product wordmark in one component so a rename does not require an architectural change.
