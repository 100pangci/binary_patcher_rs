#include "hdiffpatch_wrapper.h"
#include <cstring>
#include <cstdlib>

#include "libHDiffPatch/HDiff/diff.h"
#include "libHDiffPatch/HPatch/patch.h"

// Enable zlib compression plugin
#define _CompressPlugin_zlib 1
#define _IsNeedIncludeDefaultCompressHead 1
#include "compress_plugin_demo.h"
#include "decompress_plugin_demo.h"

struct Cache {
    unsigned char* data;
};

static hpatch_BOOL on_diff_info(sspatch_listener_t* listener,
                                const hpatch_singleCompressedDiffInfo* info,
                                hpatch_TDecompress** out_decompressPlugin,
                                unsigned char** out_temp_cache,
                                unsigned char** out_temp_cacheEnd)
{
    // Use zlib decompress plugin for compressed patches
    if (info->compressedSize > 0) {
        *out_decompressPlugin = &zlibDecompressPlugin;
    } else {
        *out_decompressPlugin = nullptr;
    }

    size_t cacheSize = (size_t)info->stepMemSize + hpatch_kStreamCacheSize * 3;
    auto* cache = (Cache*)listener->import;
    cache->data = (unsigned char*)std::malloc(cacheSize);
    if (!cache->data && cacheSize > 0)
        return hpatch_FALSE;
    *out_temp_cache = cache->data;
    *out_temp_cacheEnd = cache->data + cacheSize;
    return hpatch_TRUE;
}

static void on_patch_finish(sspatch_listener_t* listener,
                            unsigned char* temp_cache,
                            unsigned char* temp_cacheEnd)
{
    auto* cache = (Cache*)listener->import;
    if (cache->data) {
        std::free(cache->data);
        cache->data = nullptr;
    }
}

int hdiffpatch_create(
    const unsigned char* old_data, size_t old_size,
    const unsigned char* new_data, size_t new_size,
    unsigned char** out_patch, size_t* out_patch_size,
    int thread_num,
    int use_compression)
{
    try {
        std::vector<unsigned char> diff;
        const hdiff_TCompress* compress = nullptr;
        if (use_compression) {
            // zlibCompressPlugin has hdiff_TCompress as its first member; safe cast
            compress = (const hdiff_TCompress*)&zlibCompressPlugin;
        }
        create_single_compressed_diff(
            new_data, new_data + new_size,
            old_data, old_data + old_size,
            diff,
            compress,
            1024 * 256, 4, false,
            (size_t)thread_num
        );
        *out_patch_size = diff.size();
        *out_patch = (unsigned char*)std::malloc(diff.size());
        if (!*out_patch) return -1;
        std::memcpy(*out_patch, diff.data(), diff.size());
        return 0;
    } catch (...) {
        return -1;
    }
}

int hdiffpatch_apply(
    const unsigned char* old_data, size_t old_size,
    const unsigned char* patch_data, size_t patch_size,
    unsigned char** out_new_data, size_t* out_new_size,
    int thread_num)
{
    try {
        hpatch_singleCompressedDiffInfo diffInfo;
        if (!getSingleCompressedDiffInfo_mem(&diffInfo, patch_data, patch_data + patch_size))
            return -1;

        size_t new_size = (size_t)diffInfo.newDataSize;
        *out_new_size = new_size;
        *out_new_data = (unsigned char*)std::malloc(new_size);
        if (!*out_new_data) return -1;

        Cache cache = { nullptr };
        sspatch_listener_t listener;
        std::memset(&listener, 0, sizeof(listener));
        listener.import = &cache;
        listener.onDiffInfo = on_diff_info;
        listener.onPatchFinish = on_patch_finish;

        hpatch_BOOL result = patch_single_stream_mem(
            &listener,
            *out_new_data, *out_new_data + new_size,
            old_data, old_data + old_size,
            patch_data, patch_data + patch_size,
            nullptr,
            (size_t)thread_num
        );

        if (!result) {
            if (cache.data) std::free(cache.data);
            std::free(*out_new_data);
            *out_new_data = nullptr;
            *out_new_size = 0;
            return -1;
        }
        return 0;
    } catch (...) {
        if (*out_new_data) {
            std::free(*out_new_data);
            *out_new_data = nullptr;
        }
        *out_new_size = 0;
        return -1;
    }
}

void hdiffpatch_free(void* ptr)
{
    std::free(ptr);
}
