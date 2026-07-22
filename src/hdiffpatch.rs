use std::path::Path;
use crate::ffi;

const DEFAULT_THREADS: u32 = 4;

pub fn get_recommended_thread_count() -> u32 {
    let cpu_count = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(DEFAULT_THREADS as usize);
    (cpu_count.saturating_sub(1)).max(1) as u32
}

pub fn run_hdiffz(
    old_file: &Path,
    new_file: &Path,
    patch_file: &Path,
    use_compression: bool,
) -> anyhow::Result<u32> {
    let thread_count = get_recommended_thread_count();

    let old_data = std::fs::read(old_file)
        .map_err(|e| anyhow::anyhow!("读取旧文件失败 {}: {e}", old_file.display()))?;
    let new_data = std::fs::read(new_file)
        .map_err(|e| anyhow::anyhow!("读取新文件失败 {}: {e}", new_file.display()))?;

    let patch_data = ffi::create_patch(&old_data, &new_data, thread_count, use_compression)
        .map_err(|e| anyhow::anyhow!("创建补丁失败: {e}"))?;

    crate::utils::ensure_parent_dir(patch_file)?;
    std::fs::write(patch_file, &patch_data)
        .map_err(|e| anyhow::anyhow!("写入补丁文件失败 {}: {e}", patch_file.display()))?;

    Ok(thread_count)
}

pub fn run_hpatchz(old_file: &Path, patch_file: &Path, output_file: &Path) -> anyhow::Result<()> {
    let thread_count = get_recommended_thread_count();

    let old_data = std::fs::read(old_file)
        .map_err(|e| anyhow::anyhow!("读取旧文件失败 {}: {e}", old_file.display()))?;
    let patch_data = std::fs::read(patch_file)
        .map_err(|e| anyhow::anyhow!("读取补丁文件失败 {}: {e}", patch_file.display()))?;

    let new_data = ffi::apply_patch(&old_data, &patch_data, thread_count)
        .map_err(|e| anyhow::anyhow!("应用补丁失败: {e}"))?;

    crate::utils::ensure_parent_dir(output_file)?;
    std::fs::write(output_file, &new_data)
        .map_err(|e| anyhow::anyhow!("写入输出文件失败 {}: {e}", output_file.display()))?;

    Ok(())
}
