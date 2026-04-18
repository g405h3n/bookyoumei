# bookmarknot — Agent Instructions

`bookmarknot` is a cross-browser bookmark sync tool (Chrome ↔ Safari via iCloud); this harness guides agents through its design and implementation phases.

## Startup Workflow

`./harness` is a symlink of another project that serves as engineering harness of this project, which has its own repository (version control). Consequently:
- `AGENTS.md` (this file) is always delegated to another file `./harness/AGENTS.md`.
- Proceed git operations for that harness project under its own root directory.
