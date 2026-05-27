# Plan Lifecycle

Use `.cursor/plans/` only for active work and `.cursor/plans/done/` for completed plans.

## Required status conventions

- Every plan must define `todos` in frontmatter.
- Every todo must include a `status` value: `pending`, `in_progress`, `completed`, or `cancelled`.
- A plan stays in `.cursor/plans/` while any todo is `pending` or `in_progress`.
- Move a plan to `.cursor/plans/done/` when all todos are `completed` or `cancelled`.

## Hygiene checks

- Keep script references aligned with current numbered filenames.
- Treat files under `.cursor/plans/done/` as historical snapshots; they are not source-of-truth for current script names.
