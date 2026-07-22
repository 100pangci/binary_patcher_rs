# Binary Patcher

[中文](README.md) | [English](README.en.md)

---

バイナリパッチを作成・適用するためのツールです。ディレクトリ全体のパッチワークフローに対応しています。
パッチエンジンには [HDiffPatch](https://github.com/sisong/HDiffPatch)（`hdiffz` / `hpatchz`）を使用しています。

実行時には `hdiffz` および `hpatchz` のバイナリが必要です（詳しくは[インストール](#インストール)を参照）。

## 機能

- **単一ファイルパッチ** — 2 つのファイル間でパッチの作成・適用
- **ディレクトリバンドル** — `Old/` と `New/` を比較し、`manifest.json` + パッチ + 新規ファイルを自動生成
- **ワンクリック適用** — `apply_patch` がマニフェストを読み取り、SHA256 検証、バックアップ、パッチ適用を実行
- **ワンクリックロールバック** — `rollback_patch` がバックアップを復元し、追加されたファイルを削除
- **安全保証**：
  - パストラバーサル対策（`../` を拒否）
  - パッチ前後での SHA256 検証
  - 検証失敗時に自動ロールバック
  - タイムスタンプ付きバックアップ（上書き防止）
  - マニフェストのフォーマット検証

## バイナリ

| ファイル | 用途 |
|----------|------|
| `binary_patcher` | パッチの作成（単一ファイルおよびディレクトリバンドル） |
| `apply_patch` | パッチバンドルをターゲットディレクトリに適用 |
| `rollback_patch` | 適用済みのパッチバンドルをロールバック |

## インストール

### プレビルドバイナリ

> **TODO**: プレビルドバイナリはまだ提供されていません。リリース状況は [#1](https://github.com/100pangci/binary_patcher/issues/1) を参照してください。

### ソースからビルド

```sh
git clone https://github.com/100pangci/binary_patcher.git
cd binary_patcher
cargo build --release
```

コンパイルされたバイナリは `target/release/` に配置されます。

### HDiffPatch 依存

[HDiffPatch リリースページ](https://github.com/sisong/HDiffPatch/releases) から `hdiffz` と `hpatchz` をダウンロードし、以下のいずれかの場所に配置してください：

| 配置場所 | 例 |
|----------|-----|
| 実行ファイルと同じディレクトリ | `.` |
| `bin/` サブディレクトリ | `./bin/` |
| `PATH` が通ったディレクトリ | — |

## クイックスタート

### 1. ディレクトリパッチバンドルを生成

ディレクトリ構成：

```
Old/          ← 旧バージョンを配置
New/          ← 新バージョンを配置
Patch/        ← 自動生成
```

**初回実行：**

```sh
binary_patcher
```

`Old/`、`New/`、`Patch/` ディレクトリが自動生成されます。`Old/` に旧バージョン、`New/` に新バージョンを配置してください。

**2 回目の実行：**

```sh
binary_patcher
```

`Old/` と `New/` をスキャンし、各ファイルの SHA256 を計算して比較し、以下を生成します：

- `Patch/manifest.json` — 変更マニフェスト
- `Patch/**/*.patch` — 変更ファイルのバイナリパッチ
- `Patch/**/*.new` — 新規ファイルのコピー
- `Patch/README.txt` — エンドユーザー向け説明書

### 2. パッチバンドルを適用

```
旧バージョンのルート/
├── apply_patch
├── Patch/
│   ├── manifest.json
│   ├── ... .patch
│   └── ... .new
```

```sh
./apply_patch
```

以下の処理が実行されます：

1. 各ファイルが `old_sha256` と一致するか検証
2. 元のファイルを `*.backup_before_patch` としてバックアップ
3. `hpatchz` でパッチを適用
4. 出力が `new_sha256` と一致するか検証
5. 新規ファイルをコピー、削除されたファイルを削除

### 3. ロールバック

```sh
./rollback_patch
```

`*.backup_before_patch` バックアップを復元し、パッチで追加されたファイルを削除します。

## CLI リファレンス

### `binary_patcher`

| コマンド | 説明 |
|----------|------|
| （引数なし） | ワークスペースモード：`Old/`/`New/`/`Patch/` を初期化し、バンドルを生成 |
| `create <旧> <新> <パッチ>` | 2 つのファイルから単一のパッチファイルを作成 |
| `apply <旧> <パッチ> <出力>` | 単一のパッチファイルを適用 |
| `bundle --base-dir <パス>` | 指定したワークスペースディレクトリでバンドルを生成 |

### `apply_patch`

```sh
./apply_patch
```

### `rollback_patch`

```sh
./rollback_patch
```

## プロジェクト構造

```
.
├── .github/workflows/
│   ├── ci.yml               # CI: cargo check + test（マルチプラットフォーム）
│   └── build.yml            # Release: lint → test → ビルド → GitHub Release
├── scripts/
│   └── build.ps1            # Windows ワンクリックビルド + HDiffPatch ダウンロード + パッケージ
├── Cargo.toml
├── src/
│   ├── main.rs              # binary_patcher エントリポイント
│   ├── bin/
│   │   ├── apply_patch.rs   # apply_patch エントリポイント
│   │   └── rollback_patch.rs# rollback_patch エントリポイント
│   ├── cli.rs               # コマンドライン引数解析（clap）
│   ├── utils.rs             # SHA256、ファイル操作、パス安全性、バックアップ
│   ├── hdiffpatch.rs        # hdiffz/hpatchz の検出と実行
│   ├── manifest.rs          # マニフェスト型、JSON シリアライズ、検証
│   ├── bundle.rs            # バンドル作成（Old/New → Patch）
│   ├── apply.rs             # バンドル適用ロジック
│   └── rollback.rs          # バンドルロールバックロジック
└── tests/
    └── integration_test.rs  # 20 のテスト（ユニット + 全フロー）
```

## セキュリティ

| 機能 | 説明 |
|------|------|
| **パストラバーサル対策** | マニフェスト内の全パスを検証し、`../` によるエスケープを拒否 |
| **マニフェスト検証** | ロード時にスキーマ、フィールド型、フォーマットバージョンを検証 |
| **SHA256 検証** | パッチ前後でファイルの SHA256 を検証し、不一致時は自動ロールバック |
| **安全なバックアップ** | `.backup_before_patch` サフィックスを使用し、既存時はタイムスタンプを追加 |

## 開発

### 環境要件

- Rust 2024 edition（MSRV 1.85+）

### コマンド

```sh
# ビルド
cargo build

# テスト実行
cargo test

# リリースビルド
cargo build --release
```

### Windows ワンクリックビルド

```powershell
.\scripts\build.ps1
```

スクリプトの自動処理：
1. `cargo build --release` で 3 つのバイナリをコンパイル
2. GitHub から最新の HDiffPatch をダウンロード（`hdiffz.exe` / `hpatchz.exe`）
3. `Releases/binary_patcher_toolkit.zip` にパッケージ

### CI / CD

このプロジェクトは GitHub Actions を使用しています：

| ワークフロー | トリガー | 内容 |
|-------------|----------|------|
| **CI** | push / PR | `cargo check` + `cargo test`（Windows / Linux / macOS） |
| **Build & Release** | tag `v*` / 手動 | check → test → `cargo build --release` → HDiffPatch ダウンロード → パッケージ → GitHub Release に公開 |

### TODO

- [ ] プレビルドバイナリの提供
- [ ] Windows バイナリ署名

## 技術スタック

| 分野 | 選定 |
|------|------|
| 言語 | Rust（edition 2024） |
| CLI フレームワーク | clap（derive モード） |
| シリアライズ | serde + serde_json |
| ハッシュ | sha2 |
| ディレクトリ走査 | walkdir |
| エラーハンドリング | anyhow |
| パッチエンジン | [HDiffPatch](https://github.com/sisong/HDiffPatch)（外部バイナリ） |

## ライセンス

[Mozilla Public License 2.0](LICENSE) のもとで公開されています。

## 謝辞

- [HDiffPatch](https://github.com/sisong/HDiffPatch) — バイナリ差分・パッチエンジン
- オリジナルの [binary_patcher](https://github.com/100pangci/binary_patcher) Python プロジェクト
