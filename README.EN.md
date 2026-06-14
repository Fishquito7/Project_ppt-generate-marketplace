# PPTX Generate Marketplace

[简体中文](README.md) | English

**PPTX Generate** is a local Codex plugin and a standard STDIO MCP Server. It includes the complete runtime package for the PPTX Generate plugin, enabling the creation of editable PowerPoint presentations through PptxGenJS.

Typically, agents generate PPTX files using Python scripts. While this approach is fairly universal, Python still has limitations compared with PptxGenJS when it comes to complex styling and chart generation, and the final visual quality may be compromised.

This project uses PptxGenJS scripts to create visually superior PowerPoint presentations while also introducing a visual review mechanism. The review workflow depends on WPS’s `wpp.exe`: Codex can silently call the backend interface to export PDFs, then use a headless browser to export PNG previews for visual inspection and review. Soon I will add the support of powerpoint's calling.

The entire process runs silently, with no foreground windows appearing.

## Requirements

- Windows 11
- Codex
- Node.js 22+
- WPS Presentation
- Microsoft Edge or Google Chrome

## Install from GitHub

Codex CLI:
```powershell
codex plugin marketplace add <github-owner>/<repository>
codex plugin add ppt-generate@fishq-ppt-generate
```

Codex Desktop:
When adding plugin,paste the url in the source box:
```
https://github.com/Fishquito7/Project_ppt-generate-marketplace
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

