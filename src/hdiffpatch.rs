use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

const HDIFFZ_NAME: &str = "hdiffz";
const HPATCHZ_NAME: &str = "hpatchz";
const DEFAULT_THREADS: u32 = 4;

#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x08000000;

fn binary_names(name: &str) -> Vec<String> {
    if cfg!(windows) {
        vec![format!("{name}.exe"), format!("{name}.bat"), name.to_string()]
    } else {
        vec![name.to_string()]
    }
}

fn candidate_dirs() -> Vec<PathBuf> {
    let mut candidates = Vec::new();

    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(parent) = exe_path.parent() {
            candidates.push(parent.to_path_buf());
            candidates.push(parent.join("bin"));
        }
    }

    if let Ok(cwd) = std::env::current_dir() {
        candidates.push(cwd.clone());
        candidates.push(cwd.join("bin"));
    }

    candidates
}

fn find_hdiffpatch_tool(executable_name: &str) -> anyhow::Result<PathBuf> {
    let names = binary_names(executable_name);

    let mut seen = std::collections::HashSet::new();
    for exe_name in &names {
        for dir in candidate_dirs() {
            let candidate = dir.join(exe_name);
            if candidate.exists() {
                let resolved = candidate.canonicalize().ok();
                if let Some(ref r) = resolved {
                    if seen.insert(r.clone()) {
                        return Ok(candidate);
                    }
                } else if seen.insert(candidate.clone()) {
                    return Ok(candidate);
                }
            }
        }
    }

    for name in &names {
        if let Ok(path) = which::which(name) {
            return Ok(path);
        }
    }

    anyhow::bail!(
        "未找到 {}。请先下载 HDiffPatch，或把它放到程序同目录 / bin 目录 / PATH 中。",
        names[0]
    )
}

pub fn get_recommended_thread_count() -> u32 {
    let cpu_count = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(DEFAULT_THREADS as usize);
    (cpu_count.saturating_sub(1)).max(1) as u32
}

fn run_subprocess(cmd: &mut Command, description: &str) -> anyhow::Result<()> {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }

    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());

    let mut child = cmd.spawn().map_err(|e| anyhow::anyhow!("{description} 启动失败: {e}"))?;

    let timeout = Duration::from_secs(300);
    let start = std::time::Instant::now();
    let max_poll = Duration::from_millis(100);
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let stderr = child
                    .wait_with_output()
                    .ok()
                    .map(|o| String::from_utf8_lossy(&o.stderr).trim().to_string())
                    .filter(|s| !s.is_empty());
                if !status.success() {
                    let code = status.code().unwrap_or(-1);
                    match stderr {
                        Some(msg) => anyhow::bail!("{description} 失败 (返回码 {code}):\n{msg}"),
                        None => anyhow::bail!("{description} 失败 (返回码 {code})"),
                    }
                }
                return Ok(());
            }
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    anyhow::bail!("错误: {description} 超时 (300s)");
                }
                std::thread::sleep(max_poll);
            }
            Err(e) => {
                anyhow::bail!("{description} 执行出错: {e}");
            }
        }
    }
}

fn file_name_or(path: &Path) -> String {
    path.file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "?".to_string())
}

pub fn run_hdiffz(
    old_file: &Path,
    new_file: &Path,
    patch_file: &Path,
) -> anyhow::Result<u32> {
    let executable = find_hdiffpatch_tool(HDIFFZ_NAME)?;
    let thread_count = get_recommended_thread_count();
    let description = format!("HDiffPatch ({})", file_name_or(patch_file));

    let mut cmd = Command::new(&executable);
    cmd.arg(format!("-p-{thread_count}"))
        .arg(old_file)
        .arg(new_file)
        .arg(patch_file);

    run_subprocess(&mut cmd, &description)?;
    Ok(thread_count)
}

pub fn run_hpatchz(old_file: &Path, patch_file: &Path, output_file: &Path) -> anyhow::Result<()> {
    let executable = find_hdiffpatch_tool(HPATCHZ_NAME)?;
    let description = format!("应用补丁 ({})", file_name_or(patch_file));

    let mut cmd = Command::new(&executable);
    cmd.arg("-f")
        .arg(old_file)
        .arg(patch_file)
        .arg(output_file);

    run_subprocess(&mut cmd, &description)
}
