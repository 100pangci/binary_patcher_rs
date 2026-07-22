use std::path::{Path, PathBuf};

const HDIFFPATCH_REPO_API: &str = "https://api.github.com/repos/sisong/HDiffPatch/releases/latest";

fn main() {
    let manifest_dir = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let cache_dir = manifest_dir.join("target").join(".hdiffpatch-cache");
    let hd_path = cache_dir.join("src");
    let zip_path = cache_dir.join("hdiffpatch.zip");

    if !hd_path.exists() {
        download_and_extract(&zip_path, &hd_path);
    }

    let src_dir = hd_path.join("libHDiffPatch");
    let parallel_dir = hd_path.join("libParallel");

    let mut build = cc::Build::new();

    build
        .cpp(true)
        .flag_if_supported("-std=c++11")
        .flag_if_supported("/std:c++11")
        .include(&hd_path)
        .include(&src_dir)
        .include(&src_dir.join("HDiff"))
        .include(&src_dir.join("HPatch"))
        .include(&src_dir.join("HPatch").join("hpatch_mt"))
        .include(&src_dir.join("HPatchLite"))
        .include(&parallel_dir)
        .include(&hd_path.join("dirDiffPatch"))
        .include(&hd_path.join("bsdiff_wrapper"))
        .include(&hd_path.join("vcdiff_wrapper"));

    // C source files
    build.file(src_dir.join("HPatch").join("patch.c"));
    build.file(src_dir.join("HPatchLite").join("hpatch_lite.c"));
    build.file(hd_path.join("file_for_patch.c"));
    build.file(src_dir.join("HDiff").join("private_diff").join("limit_mem_diff").join("adler_roll.c"));

    // C++ source files
    build.file(src_dir.join("HDiff").join("diff.cpp"));
    build.file(src_dir.join("HDiff").join("private_diff").join("suffix_string.cpp"));
    build.file(src_dir.join("HDiff").join("private_diff").join("bytes_rle.cpp"));
    build.file(src_dir.join("HDiff").join("private_diff").join("compress_detect.cpp"));
    build.file(src_dir.join("HDiff").join("private_diff").join("match_block.cpp"));
    build.file(src_dir.join("HDiff").join("private_diff").join("match_inplace.cpp"));
    build.file(src_dir.join("HDiff").join("private_diff").join("limit_mem_diff").join("digest_matcher.cpp"));
    build.file(src_dir.join("HDiff").join("private_diff").join("limit_mem_diff").join("stream_serialize.cpp"));
    build.file(src_dir.join("HDiff").join("private_diff").join("window_diff").join("window_matcher.cpp"));
    build.file(src_dir.join("HDiff").join("private_diff").join("window_diff").join("covers_range.cpp"));
    build.file(src_dir.join("HDiff").join("private_diff").join("libdivsufsort").join("divsufsort.cpp"));
    build.file(src_dir.join("HDiff").join("private_diff").join("libdivsufsort").join("divsufsort64.cpp"));

    // Multi-threading
    build.file(src_dir.join("HPatch").join("hpatch_mt").join("_hpatch_mt.c"));
    build.file(src_dir.join("HPatch").join("hpatch_mt").join("_houtput_mt.c"));
    build.file(src_dir.join("HPatch").join("hpatch_mt").join("_hinput_mt.c"));
    build.file(src_dir.join("HPatch").join("hpatch_mt").join("_hcache_window_old_mt.c"));
    build.file(src_dir.join("HPatch").join("hpatch_mt").join("_hcache_old_mt.c"));
    build.file(src_dir.join("HPatch").join("hpatch_mt").join("hpatch_mt.c"));
    build.file(parallel_dir.join("parallel_import_c.c"));
    build.file(parallel_dir.join("parallel_channel.cpp"));
    build.file(hd_path.join("compress_parallel.cpp"));

    // Wrapper
    let wrapper_dir = Path::new("vendor").join("hdiffpatch-sys");
    build.include(&wrapper_dir);
    build.file(wrapper_dir.join("hdiffpatch_wrapper.cpp"));

    build.compile("hdiffpatch");

    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=vendor/hdiffpatch-sys/hdiffpatch_wrapper.cpp");
    println!("cargo:rerun-if-changed=vendor/hdiffpatch-sys/hdiffpatch_wrapper.h");
}

fn download_and_extract(zip_path: &PathBuf, expected_dir: &PathBuf) {
    println!("cargo:warning=Fetching latest HDiffPatch release...");

    let client = reqwest::blocking::Client::builder()
        .user_agent("BinaryPatcher-BuildScript/2.0")
        .build()
        .expect("Failed to create HTTP client");

    let release: serde_json::Value = client
        .get(HDIFFPATCH_REPO_API)
        .send()
        .expect("Failed to send release API request")
        .json()
        .expect("Failed to parse release API response");

    let tag_name = release["tag_name"]
        .as_str()
        .expect("Failed to get tag_name from release API");

    println!("cargo:warning=Latest HDiffPatch release: {tag_name}");

    let download_url = format!(
        "https://github.com/sisong/HDiffPatch/archive/refs/tags/{tag_name}.zip"
    );

    println!("cargo:warning=Downloading HDiffPatch {tag_name}...");

    let response = client
        .get(&download_url)
        .send()
        .expect("Failed to download HDiffPatch");

    let zip_bytes = response
        .bytes()
        .expect("Failed to read response bytes");

    std::fs::create_dir_all(zip_path.parent().unwrap())
        .expect("Failed to create cache directory");
    std::fs::write(zip_path, &zip_bytes)
        .expect("Failed to save HDiffPatch archive");

    // Clear expected_dir if it exists
    if expected_dir.exists() {
        std::fs::remove_dir_all(expected_dir).ok();
    }

    let cursor = std::io::Cursor::new(&zip_bytes);
    let mut archive = zip::ZipArchive::new(cursor)
        .expect("Failed to read HDiffPatch zip archive");

    // GitHub strips the "v" prefix from tag names in archive root directory names.
    // e.g. tag "v5.1.0" produces archive root "HDiffPatch-5.1.0/"
    let archive_version = tag_name.strip_prefix('v').unwrap_or(tag_name);
    let root_prefix = format!("HDiffPatch-{archive_version}/");

    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).unwrap();
        let entry_name = entry.name().to_string();
        let entry_name_norm = entry_name.replace('\\', "/");

        if let Some(rest) = entry_name_norm.strip_prefix(&root_prefix) {
            if rest.is_empty() || rest.ends_with('/') { continue; }
            let out_path = expected_dir.join(rest);
            if let Some(p) = out_path.parent() {
                std::fs::create_dir_all(p).ok();
            }
            let mut out_file = std::fs::File::create(&out_path)
                .unwrap_or_else(|e| panic!("Failed to create {}: {e}", out_path.display()));
            std::io::copy(&mut entry, &mut out_file)
                .unwrap_or_else(|e| panic!("Failed to extract {}: {e}", entry_name_norm));
        }
    }

    // Verify extraction
    let check_file = expected_dir.join("libHDiffPatch").join("HPatch").join("patch.h");
    if !check_file.exists() {
        panic!("HDiffPatch extraction failed: {} not found", check_file.display());
    }

    println!("cargo:warning=HDiffPatch {tag_name} extracted to {}", expected_dir.display());
}
