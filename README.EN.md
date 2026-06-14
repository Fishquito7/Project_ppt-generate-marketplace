# PPTX Generate Marketplace

[简体中文](README.md) | English

This repository is a Codex plugin marketplace containing the complete runtime package for `PPTX Generate`.

## Requirements

- Windows 11
- Codex
- Node.js 22+
- WPS Presentation
- Microsoft Edge or Google Chrome

## Install from GitHub

After publishing this directory as a GitHub repository:

```powershell
codex plugin marketplace add <github-owner>/<repository>
codex plugin add ppt-generate@fishq-ppt-generate
```

Restart Codex or start a new thread after installation.

## Install from a local checkout

Run this command from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-local.ps1
```

## Structure

```text
.agents/plugins/marketplace.json
plugins/ppt-generate/
scripts/install-local.ps1
```

The `plugins/ppt-generate/` directory is the complete runtime plugin bundle. It excludes project source code and development dependencies.

## Update

Replace `plugins/ppt-generate/` with the complete new runtime bundle, commit the change, then ask users to run:

```powershell
codex plugin marketplace upgrade fishq-ppt-generate
codex plugin add ppt-generate@fishq-ppt-generate
```
