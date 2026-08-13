def safe: tostring | gsub("[\\r\\n]+"; " ") | gsub("`"; "'");
def bullets($items): if ($items|length)==0 then "- None\n" else ($items|map("- "+.)|join("\n"))+"\n" end;
def evidence_ids($gate):
  ($gate.evidence_ids // ([$gate.evidence_id] | map(select(. != null)))) | sort;
def evidence_refs($gate):
  evidence_ids($gate) as $ids |
  if ($ids | length) == 0 then "`none`"
  else $ids | map("`\(. | safe)`") | join(", ") end;
($readiness[0]) as $r | ($scope[0]) as $s | ($plan[0]) as $p |
"## Quality decision: \($r.decision | safe)\n\n" +
"**Outcome:** `\($r.status | safe)`\n\n" +
"### Candidate subjects\n\n" + bullets(($s.repositories|sort_by(.id)|map("`\(.id | safe)`: `\(.subject | safe)`"))) + "\n" +
"### Resolved impacts\n\n" + bullets(($p.impacts.all|sort|map("`\(. | safe)`"))) + "\n" +
"### Applicable evidence\n\n" + bullets(($r.gates|sort_by(.id)|map(. as $gate | "`\(.id | safe)`: `\(.status | safe)`; evidence \(evidence_refs($gate))"))) + "\n" +
"### Failures, blockers, and gaps\n\n" + bullets((($r.findings + $r.known_gaps)|sort_by(.id // .message // "")|map("`\(.id // "gap" | safe)` — \(.message // . | safe)"))) + "\n" +
"### Architecture\n\n" + bullets(($r.advisory_architecture_constraint_ids // []|sort|map("Advisory `\(. | safe)`"))) + "\n" +
"### Waivers\n\n" + bullets(($r.waivers|sort_by(.waiver_id)|map("`\(.waiver_id | safe)` for `\(.gate_id | safe)` — \(.reason | safe)")))
