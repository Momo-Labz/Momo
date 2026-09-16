#!/usr/bin/env bash
# Compile and exercise the shared relay contract on Linux with the open-source
# Swift toolchain. This is the portable slice of MOMO that runs off macOS: the
# versioned JSON transport in Shared/RelayContract.swift that the Desk Display
# server emits and MOMO RELAY consumes. It verifies encode -> decode round-trip
# and v1 backward-compatible decoding.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/swift/current/usr/bin:${PATH}"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Run Scripts/cloud-agent-setup.sh first." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "${work}/main.swift" <<'SWIFT'
import Foundation

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + msg + "\n").utf8))
    exit(1)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let demo = RelayStatus.demo
guard let encoded = try? encoder.encode(demo) else { fail("encode demo") }
print("Encoded RelayStatus.demo (\(encoded.count) bytes)")

let decoder = JSONDecoder()
guard let roundTrip = try? decoder.decode(RelayStatus.self, from: encoded) else { fail("decode round-trip") }
guard roundTrip.activeCount == demo.activeCount,
      roundTrip.providers.count == demo.providers.count,
      roundTrip.sessions.count == demo.sessions.count else { fail("round-trip invariants") }
print("Round-trip OK: \(roundTrip.providers.count) providers, \(roundTrip.sessions.count) sessions, activeCount=\(roundTrip.activeCount)")

let v1JSON = """
{
  "updated": "2026-09-16T00:00:00Z",
  "activeCount": 1,
  "attentionCount": 0,
  "providers": [
    {"id":"claude","name":"Claude","mark":"A","active":1,"tokens":100,"usage":"100","short":null,"week":null,"sessionCount":1,"needsAttention":0}
  ],
  "sessions": [
    {"id":"1","provider":"Claude","mark":"A","role":"Main","title":"t","project":"p","live":true,"age":"LIVE","attention":"working","attentionLabel":"WORKING","attentionReason":null,"urgent":false,"model":null,"mcpServers":null,"skills":null,"plugins":null,"capabilityCount":null}
  ]
}
""".data(using: .utf8)!
guard let v1 = try? decoder.decode(RelayStatus.self, from: v1JSON) else { fail("decode v1 payload") }
guard v1.schemaVersion == nil, v1.usageObservations.isEmpty, v1.evidence.isEmpty else { fail("v1 defaults") }
print("v1 backward-compat decode OK (schemaVersion=nil, empty usageObservations/evidence)")

print("ALL_RELAY_CHECKS_PASSED (currentSchemaVersion=\(RelayStatus.currentSchemaVersion))")
SWIFT

swiftc -o "${work}/relaycheck" \
  "${REPO_ROOT}/Shared/RelayContract.swift" \
  "${REPO_ROOT}/iOS/Sources/RelayModels.swift" \
  "${work}/main.swift"

"${work}/relaycheck"
