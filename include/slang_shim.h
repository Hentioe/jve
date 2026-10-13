#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// 持有 Slang 的引用计数 blob，data 直接指向 Slang 的内存，不拷贝。
typedef struct SlangShimBlob {
    const void* data;
    size_t size;
    void* handle; // 内部使用：ISlangBlob*
} SlangShimBlob;

// 编译器：内部持有 IGlobalSession（重，全程序只需要一个）。
typedef struct SlangShimCompiler SlangShimCompiler;

// 失败返回 NULL。
SlangShimCompiler* slang_shim_compiler_create(void);

// 销毁前应先 release 所有 blob。
void slang_shim_compiler_destroy(SlangShimCompiler* compiler);

// 成功返回 0。
// out_diag 仅在有诊断信息（错误或警告）时被设置，需用 slang_shim_free 释放。
int slang_shim_compile_spirv(
    SlangShimCompiler* compiler,
    const char* name,        // 模块名，同时也是诊断信息里显示的文件名
    const char* source,      // NUL 结尾的 Slang 源码
    const char* entry_name,
    const char* profile,     // 如 "spirv_1_5"
    SlangShimBlob* out_code,
    char** out_diag);

void slang_shim_blob_release(SlangShimBlob* blob);
void slang_shim_free(void* p);

#ifdef __cplusplus
}
#endif
