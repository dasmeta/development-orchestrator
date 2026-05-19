# Quickstart: Template Fork Contract

## Verify Upstream Template State

```bash
git ls-files config/workspace.json
git ls-files config/workspace.example.json
bash tests/orchestration/test-template-agnostic.sh
```

Expected result:

- `config/workspace.json` is not tracked.
- `config/workspace.example.json` is tracked.
- Template conformance passes.

## Verify Orchestration Tests

```bash
bash tests/orchestration/test-init-feature.sh
bash tests/orchestration/test-render-manifest.sh
bash tests/orchestration/test-collect-github-state.sh
bash tests/orchestration/test-advance-stage.sh
bash tests/orchestration/test-run-speckit-stage.sh
bash tests/orchestration/test-evaluate-mergeability.sh
bash tests/orchestration/test-collect-github-state-live.sh
bash tests/orchestration/test-run-speckit-stage-live.sh
```

Expected result: all scripts exit successfully.

## Verify Product-Agnostic Scan

```bash
PRODUCT_PATTERN='<set-product-or-local-path-pattern>'
rg -n -i --hidden --no-ignore --glob '!/.git/*' "$PRODUCT_PATTERN" .
```

Expected result: no matches.
