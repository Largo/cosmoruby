/*
 * Test runner for test_bjson.js with statically linked bjson module.
 * Registers the bjson C module before evaluating the test bytecode.
 */
#include "quickjs.h"
#include "quickjs-libc.h"

extern const uint8_t qjsc_test_bjson[];
extern const uint32_t qjsc_test_bjson_size;
extern JSModuleDef *js_init_module_bjson(JSContext *ctx,
                                         const char *module_name);

int main(int argc, char **argv)
{
    JSRuntime *rt;
    JSContext *ctx;
    rt = JS_NewRuntime();
    js_std_init_handlers(rt);
    ctx = JS_NewContext(rt);
    if (!ctx)
        return 1;
    /* add modules */
    js_init_module_std(ctx, "std");
    js_init_module_os(ctx, "os");
    js_init_module_bjson(ctx, "third_party/quickjs/tests/bjson.so");
    js_std_add_helpers(ctx, argc, argv);
    js_std_eval_binary(ctx, qjsc_test_bjson, qjsc_test_bjson_size, 0);
    js_std_loop(ctx);
    js_std_free_handlers(rt);
    JS_FreeContext(ctx);
    JS_FreeRuntime(rt);
    return 0;
}
