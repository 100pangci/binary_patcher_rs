use std::ffi::c_void;
use std::ptr::null_mut;

unsafe extern "C" {
    fn hdiffpatch_create(
        old_data: *const u8,
        old_size: usize,
        new_data: *const u8,
        new_size: usize,
        out_patch: *mut *mut u8,
        out_patch_size: *mut usize,
        thread_num: i32,
    ) -> i32;

    fn hdiffpatch_apply(
        old_data: *const u8,
        old_size: usize,
        patch_data: *const u8,
        patch_size: usize,
        out_new_data: *mut *mut u8,
        out_new_size: *mut usize,
        thread_num: i32,
    ) -> i32;

    fn hdiffpatch_free(ptr: *mut c_void);
}

pub fn create_patch(
    old_data: &[u8],
    new_data: &[u8],
    thread_num: u32,
) -> Result<Vec<u8>, String> {
    let mut out_patch: *mut u8 = null_mut();
    let mut out_patch_size: usize = 0;

    let ret = unsafe {
        hdiffpatch_create(
            old_data.as_ptr(),
            old_data.len(),
            new_data.as_ptr(),
            new_data.len(),
            &mut out_patch,
            &mut out_patch_size,
            thread_num as i32,
        )
    };

    if ret != 0 {
        return Err("创建补丁失败".to_string());
    }

    let patch = unsafe {
        std::slice::from_raw_parts(out_patch, out_patch_size).to_vec()
    };

    unsafe { hdiffpatch_free(out_patch as *mut c_void); }

    Ok(patch)
}

pub fn apply_patch(
    old_data: &[u8],
    patch_data: &[u8],
    thread_num: u32,
) -> Result<Vec<u8>, String> {
    let mut out_new_data: *mut u8 = null_mut();
    let mut out_new_size: usize = 0;

    let ret = unsafe {
        hdiffpatch_apply(
            old_data.as_ptr(),
            old_data.len(),
            patch_data.as_ptr(),
            patch_data.len(),
            &mut out_new_data,
            &mut out_new_size,
            thread_num as i32,
        )
    };

    if ret != 0 {
        return Err("应用补丁失败".to_string());
    }

    let new_data = unsafe {
        std::slice::from_raw_parts(out_new_data, out_new_size).to_vec()
    };

    unsafe { hdiffpatch_free(out_new_data as *mut c_void); }

    Ok(new_data)
}
