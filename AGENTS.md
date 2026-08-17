# AI Agent Instructions

These instructions apply to every AI coding agent working anywhere in this repository, regardless of vendor or runtime.

## Odin formatting is prohibited

- Never run `odinfmt` in this repository.
- Never run `odin fmt` or any other command, script, editor action, hook, or tool that automatically formats Odin source files.
- Do not format an entire Odin file as a side effect of making a change.
- Preserve the existing formatting of surrounding code. Make only the smallest manual formatting adjustments required for the requested change.
- This prohibition applies even when formatting would normally be part of validation, cleanup, or a skill's standard workflow.

Running builds, checks, and tests is allowed as long as they do not invoke a formatter.
