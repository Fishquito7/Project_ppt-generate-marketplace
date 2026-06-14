# PPTX Generate v0.3.2

简体中文 | [English](README.md)

欧耶欧耶伐垦地！孩子们，PPTX Generate 是一个本地 Codex 插件和标准 STDIO MCP Server，用于通过 PptxGenJS 创建可编辑的 PowerPoint 演示文稿。通常agent生成pptx的方式是通过Python脚本，虽然比较通用，但相较于PptxGenJs来说，Python对于复杂样式与图表的生成还是具有局限性，视觉效果也有打折。本项目实现了通过PptxGenJs生成脚本创建视觉效果更好的ppt的同时加入了视觉审查机制，其依赖于wps的wpp.exe，Codex可通过后台调用接口自主输出pdf，通过无头浏览器导出png进行视觉预览和审查（谁会不装wps呢？应该是不会的）。全程静默运行，无前台窗口。

## 运行环境

- Node.js 22+
- WPS 演示，用于高保真视觉核验
- Microsoft Edge 或 Google Chrome，用于将 WPS 导出的 QA PDF 转换为 PNG 预览图
- 不依赖 LibreOffice、Pandoc、Python、Microsoft PowerPoint，也不内置字体

如果缺少 Node.js，Agent 可以运行 `scripts/bootstrap.ps1`，通过 Winget 安装 Node.js LTS。系统安装操作仍需经过正常的 Codex 工具审批。

插件不会自动安装 WPS。没有 WPS 时仍可生成草稿，但发布未经视觉核验的文件需要显式允许。

## WPS 检索

`check_environment` 会分别报告 WPS 安装发现状态和 COM 自动化可用状态：

- `installed=true, automationReady=true`：`PowerPoint.Application` ProgID 注册链在匹配的 32 位或 64 位注册表视图中解析到真实存在的 `wpp.exe`，允许执行 WPS PDF 导出。
- `installed=true, automationReady=false`：仅通过已知 CLSID、Kingsoft 安装注册表、App Paths、Windows 快捷方式、运行中的进程或有界目录搜索发现 WPS。结果仅用于诊断，仍禁止执行导出。
- `installed=false`：未发现任何 WPS 候选。

检测器使用 .NET `RegistryView` 查询 HKCU/HKLM，拒绝 Microsoft `POWERPNT.EXE`，并在每次导出前重新检查主 COM 注册链。

作为诊断回退，检测器会只读解析用户和公共开始菜单、桌面及任务栏固定目录中的本地 `.lnk` 文件；不会启动快捷方式目标，也不会访问网络路径。检测器不会解析 Windows 固定项数据库、修复注册表、在检测阶段启动或关闭 WPS，也不会递归扫描整个磁盘。

即使 MCP 子进程没有继承 `WINDIR` 或 `SystemRoot`，Windows PowerShell 启动与 WPS 检测仍可正常工作。

## 发布包

运行 `pnpm release` 会同时生成运行目录和可分享的 ZIP：

```text
release/ppt-generate/
release/ppt-generate-0.3.2.zip
```

ZIP 内包含一个顶层 `ppt-generate/` 目录，不包含源码、测试、开发依赖或已废弃的渲染器。

## 工作流程

1. 在独立 Node 子进程中执行 PptxGenJS ESM 脚本。
2. 将草稿保存在 `%USERPROFILE%\.ppt-generate\tmp\<operationId>`。
3. 检查最终 PPTX 压缩包结构，并审计 Windows 已注册字体。
4. 使用 WPS COM 静默导出高保真 QA PDF，但不将 PDF 作为默认发布文件。
5. 使用内置 PDF.js 与无头 Edge/Chrome 生成逐页 PNG 预览图和总览图。
6. 审阅预览、修改脚本并发布通过核验的 PPTX。
7. 仅在用户确认后删除 operation 临时文件。

每次 operation 都会保存包含视觉核验状态的 `operation.json`。未经核验的 operation 默认禁止发布，除非显式启用 `allowUnverified`。

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
