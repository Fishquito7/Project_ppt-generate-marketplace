# PPTX Generate Marketplace

简体中文 | [English](README.EN.md)

欧耶欧耶伐垦地！孩子们，PPTX Generate 是一个本地 Codex 插件和标准 STDIO MCP Server，其中包含 `PPTX Generate` 插件的完整运行包用于通过 PptxGenJS 创建可编辑的 PowerPoint 演示文稿。通常agent生成pptx的方式是通过Python脚本，虽然比较通用，但相较于JavaScript的PptxGenJs库来说，Python对于复杂样式与图表的生成还是具有局限性，视觉效果也会打折。本项目实现了通过PptxGenJs生成脚本创建视觉效果更好的ppt的同时加入了视觉审查机制，其依赖于wps的wpp.exe，Codex可通过后台调用接口自主输出pdf，通过无头浏览器导出png进行视觉预览和审查（谁会不装wps呢？应该是不会的）。全程静默运行，无前台窗口。

## 功能

PPTX Generate 使用：

- PptxGenJS 生成可编辑 PPTX。
- WPS 演示通过 COM 静默导出 QA PDF。
- PDF.js 与 Edge/Chrome 生成逐页 PNG 预览图。
- Codex Skill 指导 Agent 完成生成、检查、返工和发布流程。

## 环境要求

- Windows 11
- Codex
- Node.js 22+
- WPS 演示
- Microsoft Edge 或 Google Chrome

如果缺少 Node.js，插件内的 `scripts/bootstrap.ps1` 可以通过 Winget 安装 Node.js LTS。插件不会自动安装 WPS。

## 从 GitHub 安装

Codex Desktop用户请在'插件-添加插件市场-来源'位置填写本项目地址以安装:
```
https://github.com/Fishquito7/Project_ppt-generate-marketplace
```

Codex CLI用户运行：
```powershell
codex plugin add ppt-generate@fishq-ppt-generate
```

安装后请重启 Codex 或开启新会话。

## 从本地目录安装

克隆或解压此目录后，在仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-local.ps1
```

安装脚本只会：

1. 将当前目录添加为 Codex Marketplace。
2. 从该 Marketplace 安装 `ppt-generate`。
3. 显示插件安装状态。

## 仓库结构

```text
.
├─ .agents/
│  └─ plugins/
│     └─ marketplace.json
├─ plugins/
│  └─ ppt-generate/
│     ├─ .codex-plugin/
│     ├─ dist/
│     ├─ scripts/
│     ├─ skills/
│     ├─ .mcp.json
│     └─ README.zh-CN.md
├─ scripts/
│  └─ install-local.ps1
├─ LICENSE
├─ README.md
└─ README.zh-CN.md
```

`plugins/ppt-generate/` 是可直接运行的插件包，不包含项目源码和开发依赖。

## 使用

安装并重启 Codex 后，可以直接描述需要的演示文稿，也可以输入 `@` 并选择 PPTX Generate。

示例：

```text
使用 PPTX Generate 创建一份五页的项目汇报 PPT，并完成 WPS 视觉核验。
```
