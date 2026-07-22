# Binary Patcher

[English](README.en.md) | [日本語](README.ja.md)

---

一个用于生成和应用二进制补丁的工具，支持整目录补丁工作流。
底层补丁引擎使用 [HDiffPatch](https://github.com/sisong/HDiffPatch)（`hdiffz` / `hpatchz`）。

运行时需要 `hdiffz` 和 `hpatchz` 二进制文件（详见[安装](#安装)）。

## 功能

- **单文件补丁** — 对两个文件生成/应用补丁
- **整目录打包** — 对比 `Old/` 与 `New/`，自动生成 `manifest.json` + 补丁文件 + 新增文件
- **一键应用** — `apply_patch` 读取清单、校验 SHA256、备份原文件、执行补丁
- **一键回滚** — `rollback_patch` 恢复备份、删除新增文件
- **安全保障**：
  - 路径穿越防护（拒绝 `../` 逃逸）
  - 补丁前后 SHA256 校验
  - 校验失败自动回滚
  - 备份文件使用时间戳后缀（不静默覆盖）
  - Manifest 格式校验

## 二进制文件

| 文件 | 用途 |
|------|------|
| `binary_patcher` | 创建补丁（单文件和整目录打包） |
| `apply_patch` | 将补丁包应用到目标目录 |
| `rollback_patch` | 回滚已应用的补丁包 |

## 安装

### 预编译二进制

> **TODO**: 预编译包尚未发布。关注 [#1](https://github.com/100pangci/binary_patcher/issues/1) 了解发布状态。

### 从源码编译

```sh
git clone https://github.com/100pangci/binary_patcher.git
cd binary_patcher
cargo build --release
```

编译后的可执行文件位于 `target/release/`。

### HDiffPatch 依赖

从 [HDiffPatch 发布页](https://github.com/sisong/HDiffPatch/releases) 下载 `hdiffz` 和 `hpatchz`，放在以下任一位置：

| 位置 | 示例 |
|------|------|
| 与可执行文件同目录 | `.` |
| `bin/` 子目录 | `./bin/` |
| `PATH` 中的任意目录 | — |

## 快速开始

### 1. 生成整目录补丁

准备目录结构：

```
Old/          ← 放入旧版本
New/          ← 放入新版本
Patch/        ← 自动生成
```

**首次运行：**

```sh
binary_patcher
```

程序自动创建 `Old/`、`New/`、`Patch/` 目录。将旧版本文件放入 `Old/`，新版本文件放入 `New/`。

**再次运行：**

```sh
binary_patcher
```

程序扫描 `Old/` 和 `New/`，计算每个文件的 SHA256，对比后生成：

- `Patch/manifest.json` — 变更清单
- `Patch/**/*.patch` — 变更文件的二进制补丁
- `Patch/**/*.new` — 新增文件的副本
- `Patch/README.txt` — 使用说明

### 2. 应用整包补丁

```
旧版本根目录/
├── apply_patch
├── Patch/
│   ├── manifest.json
│   ├── ... .patch
│   └── ... .new
```

```sh
./apply_patch
```

程序会：

1. 校验每个文件是否匹配 `old_sha256`
2. 将原文件备份为 `*.backup_before_patch`
3. 通过 `hpatchz` 应用补丁
4. 验证输出是否匹配 `new_sha256`
5. 复制新增文件，删除已移除的文件

### 3. 回滚补丁

```sh
./rollback_patch
```

恢复 `*.backup_before_patch` 备份文件，删除补丁新增的文件。

## CLI 参考

### `binary_patcher`

| 命令 | 说明 |
|------|------|
| （无参数） | 工作区模式：初始化 `Old/`/`New/`/`Patch/`，然后打包 |
| `create <旧文件> <新文件> <补丁文件>` | 对两个文件创建单个补丁 |
| `apply <旧文件> <补丁文件> <输出文件>` | 应用单个补丁 |
| `bundle --base-dir <路径>` | 指定工作目录执行打包 |

### `apply_patch`

```sh
./apply_patch
```

### `rollback_patch`

```sh
./rollback_patch
```

## 项目结构

```
.
├── .github/workflows/
│   ├── ci.yml               # CI: cargo check + test（多平台）
│   └── build.yml            # Release: lint → test → 构建 → GitHub Release
├── scripts/
│   └── build.ps1            # Windows 一键构建 + HDiffPatch 下载 + 打包
├── Cargo.toml
├── src/
│   ├── main.rs              # binary_patcher 入口
│   ├── bin/
│   │   ├── apply_patch.rs   # apply_patch 入口
│   │   └── rollback_patch.rs# rollback_patch 入口
│   ├── cli.rs               # 命令行参数解析（clap）
│   ├── utils.rs             # SHA256、文件操作、路径安全、备份
│   ├── hdiffpatch.rs        # hdiffz/hpatchz 查找与调用
│   ├── manifest.rs          # Manifest 类型、JSON 序列化、校验
│   ├── bundle.rs            # 整目录打包（Old/New → Patch）
│   ├── apply.rs             # 补丁应用逻辑
│   └── rollback.rs          # 补丁回滚逻辑
└── tests/
    └── integration_test.rs  # 20 个测试（单元 + 全流程）
```

## 安全

| 特性 | 说明 |
|------|------|
| **路径穿越防护** | 所有 manifest 中的路径均经过校验，拒绝 `../` 逃逸 |
| **Manifest 校验** | 加载时验证字段完整性和类型，拒绝格式错误的清单 |
| **SHA256 校验** | 补丁前后均校验文件完整性，失败自动回滚 |
| **安全备份** | 备份文件使用 `.backup_before_patch` 后缀，已存在时追加时间戳 |

## 开发

### 环境要求

- Rust 2024 edition（最低支持 1.85+）

### 常用命令

```sh
# 构建
cargo build

# 运行测试
cargo test

# 发布构建
cargo build --release
```

### Windows 一键构建

```powershell
.\scripts\build.ps1
```

脚本自动：
1. `cargo build --release` 编译三个二进制文件
2. 从 GitHub 下载最新 HDiffPatch（`hdiffz.exe` / `hpatchz.exe`）
3. 打包为 `Releases/binary_patcher_toolkit.zip`

### CI / CD

本项目使用 GitHub Actions：

| 工作流 | 触发条件 | 内容 |
|--------|---------|------|
| **CI** | push / PR | `cargo check` + `cargo test`（Windows / Linux / macOS） |
| **Build & Release** | tag `v*` / 手动 | check → test → `cargo build --release` → 下载 HDiffPatch → 打包 → 发布到 GitHub Release |

### TODO

- [ ] 提供预编译二进制下载
- [ ] Windows 二进制签名

## 技术栈

| 领域 | 选型 |
|------|------|
| 语言 | Rust（edition 2024） |
| CLI 框架 | clap（derive 模式） |
| 序列化 | serde + serde_json |
| 哈希 | sha2 |
| 目录遍历 | walkdir |
| 错误处理 | anyhow |
| 补丁引擎 | [HDiffPatch](https://github.com/sisong/HDiffPatch)（外部二进制） |

## 许可证

本项目基于 [Mozilla Public License 2.0](LICENSE) 开源。

## 致谢

- [HDiffPatch](https://github.com/sisong/HDiffPatch) — 二进制差异/补丁引擎
- 原 [binary_patcher](https://github.com/100pangci/binary_patcher) Python 项目
