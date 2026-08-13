def safe: tostring | gsub("[\\r\\n]+"; " ") | gsub("`"; "'");
def bullets($items):
  if ($items | length) == 0 then "- None\n"
  else ($items | map("- " + .) | join("\n")) + "\n" end;

($readiness[0]) as $r | ($scope[0]) as $s |
"# Readiness: \($r.feature_id | safe) / \($r.decision | safe)\n\n" +
"- Status: `\($r.status | safe)`\n" +
"- Evaluated: `\($r.evaluated_at | safe)`\n" +
"- Subject fingerprint: `\($r.subject_fingerprint | safe)`\n\n" +
"## Repository subjects\n\n" +
bullets(($s.repositories | sort_by(.id) | map("`\(.id | safe)`: `\(.subject | safe)`"))) + "\n" +
"## Acceptance coverage\n\n" +
bullets(($r.gates | sort_by(.id) | map("`\(.id | safe)`: `\(.status | safe)`"))) + "\n" +
"## Architecture conformance\n\n" +
bullets(($r.advisory_architecture_constraint_ids // [] | sort | map("Advisory: `\(. | safe)`"))) + "\n" +
"## Gate results\n\n" +
bullets(($r.gates | sort_by(.id) | map("`\(.id | safe)` — `\(.status | safe)` (\(.reason | safe)); evidence: `\(.evidence_id // "none" | safe)`"))) + "\n" +
"## Documentation disposition\n\n" +
bullets(([$r.gates[] | select(.id | test("documentation|docs";"i"))] | map("`\(.id | safe)`: `\(.status | safe)`"))) + "\n" +
"## Failures and blockers\n\n" +
bullets(($r.findings | sort_by(.id) | map("`\(.id | safe)` — \(.message | safe)"))) + "\n" +
"## Known gaps\n\n" +
bullets(($r.known_gaps | sort_by(.id // .message // "") | map("`\(.id // "gap" | safe)` — \(.message // . | safe)"))) + "\n" +
"## Waivers\n\n" +
bullets(($r.waivers | sort_by(.waiver_id) | map("`\(.waiver_id | safe)` for `\(.gate_id | safe)` — \(.reason | safe)"))) + "\n" +
"## Evidence\n\n" +
bullets(([$r.gates[] | select(.evidence_id != null)] | sort_by(.evidence_id) | map("`\(.evidence_id | safe)` satisfies `\(.id | safe)`")))
