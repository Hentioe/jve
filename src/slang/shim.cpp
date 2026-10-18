#include "shim.h"
#include <slang.h>
#include <slang-com-ptr.h>
#include <cstdlib>
#include <cstring>
#include <string>

using Slang::ComPtr;

struct SlangShimCompiler {
    ComPtr<slang::IGlobalSession> global;
};

namespace {

struct DiagLog {
    std::string text;
    void add(ISlangBlob* b) {
        if (b && b->getBufferSize())
            text.append((const char*)b->getBufferPointer(), b->getBufferSize());
    }
};

int compile(slang::IGlobalSession* global,
            const char* name, const char* source,
            const char* entry_name, const char* profile,
            SlangShimBlob* out, DiagLog& log)
{
    slang::TargetDesc target = {};
    target.format = SLANG_SPIRV;
    target.profile = global->findProfile(profile);
    if (target.profile == SLANG_PROFILE_UNKNOWN) return -2;

    slang::SessionDesc desc = {};
    desc.targets = &target;
    desc.targetCount = 1;

    ComPtr<slang::ISession> session;
    if (SLANG_FAILED(global->createSession(desc, session.writeRef()))) return -3;

    ComPtr<ISlangBlob> diag;

    slang::IModule* module = session->loadModuleFromSourceString(
        name, name, source, diag.writeRef());
    log.add(diag);
    if (!module) return -4;

    ComPtr<slang::IEntryPoint> entry;
    if (SLANG_FAILED(module->findEntryPointByName(entry_name, entry.writeRef())))
        return -5;

    slang::IComponentType* parts[] = {module, entry};
    ComPtr<slang::IComponentType> composed;
    diag = nullptr;
    SlangResult r = session->createCompositeComponentType(
        parts, 2, composed.writeRef(), diag.writeRef());
    log.add(diag);
    if (SLANG_FAILED(r)) return -6;

    ComPtr<slang::IComponentType> linked;
    diag = nullptr;
    r = composed->link(linked.writeRef(), diag.writeRef());
    log.add(diag);
    if (SLANG_FAILED(r)) return -7;

    ComPtr<ISlangBlob> code;
    diag = nullptr;
    r = linked->getEntryPointCode(0, 0, code.writeRef(), diag.writeRef());
    log.add(diag);
    if (SLANG_FAILED(r)) return -8;

    out->data = code->getBufferPointer();
    out->size = code->getBufferSize();
    out->handle = code.detach(); // 把引用计数的所有权交给调用方
    return 0;
}

} // namespace

#ifdef EMBEDDED_GLSLANG
extern "C" void slang_glslang_install_embedded(void* globalSession); // 经过改造后 glslang 是嵌入的
#endif

extern "C" SlangShimCompiler* slang_shim_compiler_create(void) {
    auto* c = new SlangShimCompiler;
    if (SLANG_FAILED(slang_createGlobalSession(SLANG_API_VERSION, c->global.writeRef()))) {
        delete c;
        return nullptr;
    }
    #ifdef EMBEDDED_GLSLANG
    slang_glslang_install_embedded(c->global.get()); // 避免运行时加载
    #endif
    return c;
}

extern "C" void slang_shim_compiler_destroy(SlangShimCompiler* compiler) {
    delete compiler;
}

extern "C" int slang_shim_compile_spirv(
    SlangShimCompiler* compiler,
    const char* name, const char* source,
    const char* entry_name, const char* profile,
    SlangShimBlob* out_code, char** out_diag)
{
    *out_code = SlangShimBlob{};
    *out_diag = nullptr;

    DiagLog log;
    int rc = compile(compiler->global.get(), name, source, entry_name, profile,
                     out_code, log);

    if (!log.text.empty()) {
        char* p = (char*)malloc(log.text.size() + 1);
        memcpy(p, log.text.c_str(), log.text.size() + 1);
        *out_diag = p;
    }
    return rc;
}

extern "C" void slang_shim_blob_release(SlangShimBlob* blob) {
    if (!blob) return;
    if (blob->handle)
        static_cast<ISlangBlob*>(blob->handle)->release();
    *blob = SlangShimBlob{};
}

extern "C" void slang_shim_free(void* p) { free(p); }
