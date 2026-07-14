# Development Orchestration Template TODO

## Template Hardening

- [ ] Keep root orchestration scripts driven by `config/workspace.json`.
- [ ] Keep product-specific child repository names out of upstream template docs.
- [ ] Add product fork examples only under explicit example/profile paths.
- [ ] Expand merge-gate configuration when real product forks need additional
  evidence types.
- [ ] Keep handoff templates generic and role-based.

## Product Fork Checklist

- [ ] Set the workspace name in `config/workspace.json`.
- [ ] Replace default child repository paths with product-local paths.
- [ ] Confirm each stage has one owning repository and one execution skill.
- [ ] Add child repository instructions for product behavior, contracts,
  implementation, and validation.
- [ ] Add any product-specific runtime or tool-writing guardrails in the fork,
  not in the central template.

## Future Workspace Discovery

- [ ] Add optional authenticated GitHub, GitLab, and Bitbucket inventory adapters
  after the local-first workspace bootstrap workflow has production evidence.
