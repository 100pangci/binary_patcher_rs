use std::path::Path;
use crate::manifest::Manifest;
use crate::utils::{resolve_safe_path, restore_backup};

pub fn rollback_bundle(base_dir: &Path) -> anyhow::Result<()> {
    let patch_dir = base_dir.join("Patch");

    if !patch_dir.exists() {
        anyhow::bail!(
            "当前目录下未找到 Patch 文件夹: {}\n\
             请把 Patch 文件夹复制到旧版本根目录后，再运行 rollback_patch。",
            patch_dir.display()
        );
    }

    let manifest = Manifest::load(&patch_dir)?;

    let changed = &manifest.changed;
    let added = &manifest.added;
    let deleted = &manifest.deleted;

    println!("检测到可回滚内容: 变更 {}，新增 {}，删除 {}", changed.len(), added.len(), deleted.len());

    let mut restored_count = 0u32;
    let mut removed_count = 0u32;

    for item in changed {
        let target_path = resolve_safe_path(base_dir, &item.path)?;
        println!("[恢复变更] {}", item.path);
        if restore_backup(&target_path)? {
            restored_count += 1;
        } else {
            println!("  跳过：未找到备份文件");
        }
    }

    for item in deleted {
        let target_path = resolve_safe_path(base_dir, &item.path)?;
        println!("[恢复删除] {}", item.path);
        if restore_backup(&target_path)? {
            restored_count += 1;
        } else {
            println!("  跳过：未找到备份文件");
        }
    }

    for item in added {
        let target_path = resolve_safe_path(base_dir, &item.path)?;
        println!("[删除新增] {}", item.path);
        if target_path.exists() {
            if target_path.is_file() {
                std::fs::remove_file(&target_path)?;
                removed_count += 1;
                println!("  已删除新增文件: {}", target_path.display());
            } else {
                println!("  跳过：目标是目录，未删除 {}", target_path.display());
            }
        } else {
            println!("  跳过：新增文件不存在 {}", target_path.display());
        }
    }

    println!("\n补丁回滚完成！");
    println!("- 恢复备份文件: {restored_count}");
    println!("- 删除新增文件: {removed_count}");
    println!("说明：已恢复的 *.backup_before_patch 备份文件会被自动删除。");

    Ok(())
}
