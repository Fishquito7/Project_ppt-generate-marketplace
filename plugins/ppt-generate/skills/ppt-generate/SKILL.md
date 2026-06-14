---
name: ppt-generate
description: Generate, render, review, revise, validate, and publish editable PPTX presentations with PptxGenJS. Use for creating PowerPoint decks from scratch or validating generated PPTX files.
---

# PPTX Generate

Use the `ppt-generate` MCP tools for editable PowerPoint creation.

## Runtime Bootstrap

If the PPTX Generate MCP server is unavailable, first check whether Node.js 22+ exists.

On Windows, after explaining that this changes installed system applications and obtaining normal tool approval, run:

```powershell
powershell -ExecutionPolicy Bypass -File "<plugin-root>\scripts\bootstrap.ps1"
```

After Node.js installation, tell the user to restart Codex so the MCP server can load.

## Mandatory Workflow

1. Call `check_environment`.
   - Treat `tools.wps.automationReady=true` with `discoverySource="com-progid"` as the only WPS export-ready state.
   - If `tools.wps.installed=true` but `automationReady=false`, explain that WPS was found but its `PowerPoint.Application` COM registration is incomplete or unusable. Do not claim WPS is absent and do not use diagnostic candidates for export.
2. Create a task-specific PptxGenJS ESM script. It must export one default async build function and use the injected `pptx`, `PptxGenJS`, `baseDir`, `assets`, `tmpDir`, and `log` values.
3. Explain that `create_presentation` executes arbitrary JavaScript that can read user files and access the network, then call it after approval.
4. Inspect the WPS QA PDF, every generated PNG preview, and the contact sheet. Do not treat structural validity alone as visual success.
5. Revise the script and create a new draft when text is clipped, elements overlap, fonts are missing, or the composition is weak.
6. Call `publish_presentation` only after the user-facing result is acceptable and WPS visual validation completed.
7. Preserve the operation directory for likely revisions. Ask the user before calling `cleanup_operation`.

## Script Contract

```js
export default async function build({ pptx, PptxGenJS, baseDir, assets, tmpDir, log }) {
  pptx.layout = "LAYOUT_WIDE";
  const slide = pptx.addSlide();
  slide.addText("Editable presentation", { x: 0.8, y: 0.7, w: 6, h: 0.7, fontSize: 30 });
  return pptx;
}
```

## Rules

- Prefer editable PptxGenJS text, shapes, charts, tables, and images.
- Use meaningful output names and never overwrite an existing final PPTX.
- WPS Presentation is the only PPTX layout renderer. Edge/Chrome only rasterizes the WPS QA PDF.
- WPS discovery fallbacks are diagnostic only. Do not repair COM registration, launch a discovered `wpp.exe` directly, or run an unbounded filesystem search.
- A `shell-shortcut` result means a local Windows shortcut located WPS. Treat it as installed but not automation-ready, and never launch the shortcut or its target.
- WPS is not installed automatically. If WPS validation fails or is unavailable, explain the failure and ask for explicit confirmation before publishing with `allowUnverified: true`.
- Prefer common Windows Chinese fonts such as `Microsoft YaHei`, `SimSun`, `KaiTi`, and `DengXian`. `Noto Sans SC` is acceptable only when it is installed.
- Missing fonts are reported with replacement suggestions. Do not download, install, or automatically replace fonts.
- The QA PDF remains inside the operation directory and is not a default published output.
- Do not claim Microsoft PowerPoint fidelity. For high-risk delivery, mention that Microsoft PowerPoint has not been adapted yet.
- PPTX Generate does not provide report generation, existing PPTX editing, or template cloning.
