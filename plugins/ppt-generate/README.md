# PPTX Generate v0.3.2

[简体中文](README.zh-CN.md) | English

PPTX Generate is a local Codex plugin and standard STDIO MCP server for creating editable PowerPoint presentations with PptxGenJS.

## Runtime

- Node.js 22+
- WPS Presentation for high-fidelity visual validation
- Microsoft Edge or Google Chrome for converting the WPS QA PDF into PNG previews
- No LibreOffice, Pandoc, Python, Microsoft PowerPoint, or bundled fonts

If Node.js is missing, an agent can run `scripts/bootstrap.ps1` to install Node.js LTS through Winget. System installation requires normal Codex tool approval.
WPS is never installed automatically. Without WPS, drafts can still be created, but publishing requires an explicit unverified override.

## WPS Discovery

`check_environment` reports WPS installation discovery separately from COM automation readiness:

- `installed=true, automationReady=true`: the `PowerPoint.Application` ProgID chain resolves to an existing `wpp.exe` in the matching 32-bit or 64-bit registry view. WPS PDF export is allowed.
- `installed=true, automationReady=false`: WPS was found only through a known CLSID, Kingsoft installation metadata, App Paths, Windows shell shortcuts, a running process, or bounded filesystem patterns. The result is diagnostic only and export remains blocked.
- `installed=false`: no WPS candidate was found.

The detector queries HKCU/HKLM with .NET `RegistryView`, rejects Microsoft `POWERPNT.EXE`, and rechecks the primary COM chain before every export. As a diagnostic fallback, it reads local `.lnk` files from the user/common Start Menu, desktops, and taskbar pinned directory without launching their targets or accessing network paths. It does not parse Windows pinned-item databases, repair the registry, start or close WPS during discovery, or recursively scan entire disks. Windows PowerShell launch and WPS discovery remain functional when the MCP process does not inherit `WINDIR` or `SystemRoot`.

## Distribution

`pnpm release` creates both the runtime directory and a shareable ZIP:

```text
release/ppt-generate/
release/ppt-generate-0.3.2.zip
```

The ZIP contains one top-level `ppt-generate/` directory and excludes source code, tests, development dependencies, and obsolete renderers.

## Workflow

1. Execute a PptxGenJS ESM script in an isolated Node child process.
2. Save the draft under `%USERPROFILE%\.ppt-generate\tmp\<operationId>`.
3. Validate the final PPTX archive and inspect Windows-registered fonts.
4. Use WPS COM to export a high-fidelity QA PDF without publishing it.
5. Use bundled PDF.js with headless Edge/Chrome to create per-slide PNG previews and a contact sheet.
6. Review previews, revise the script, and publish the approved PPTX.
7. Delete operation files only after user confirmation.

Each operation stores `operation.json` with its visual-validation state. Unverified operations are blocked from publishing unless `allowUnverified` is explicitly enabled.

## CLI

```powershell
node dist\ppt-generate-cli.js doctor
node dist\ppt-generate-cli.js presentation create --script examples\presentation.mjs --out example
node dist\ppt-generate-cli.js presentation validate C:\path\deck.pptx
node dist\ppt-generate-cli.js presentation publish --operation <operation-id> --out-dir C:\path
node dist\ppt-generate-cli.js presentation publish --operation <operation-id> --allow-unverified
node dist\ppt-generate-cli.js fonts inspect C:\path\deck.pptx
node dist\ppt-generate-cli.js cleanup <operation-id>
```
