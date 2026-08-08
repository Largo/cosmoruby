#include "internal.h"
#include "internal/array.h"
#include "internal/box.h"
#include "internal/eval.h"
#include "iseq.h"
#include "vm_core.h"
#include "builtin.h"

#include "miniprelude.c"

static VALUE
prelude_ast_value(VALUE name, VALUE code, int line)
{
    rb_ast_t *ast;
    VALUE ast_value = rb_parser_compile_string_path(rb_parser_new(), name, code, line);
    ast = rb_ruby_ast_data_get(ast_value);
    if (!ast || !ast->body.root) {
        if (ast) rb_ast_dispose(ast);
        rb_exc_raise(rb_errinfo());
    }
    return ast_value;
}

static void
pm_prelude_load(pm_parse_result_t *result, VALUE name, VALUE code, int line)
{
    pm_options_line_set(&result->options, line);
    VALUE error = pm_parse_string(result, code, name, NULL);

    if (!NIL_P(error)) {
        pm_parse_result_free(result);
        rb_exc_raise(error);
    }
}

static const rb_iseq_t *
builtin_iseq_load(const char *feature_name, const struct rb_builtin_function *table)
{
    VALUE name_str = 0;
    int start_line;
    const rb_iseq_t *iseq;
    VALUE code = rb_builtin_find(feature_name, &name_str, &start_line);
    if (NIL_P(code)) {
        rb_fatal("builtin_iseq_load: can not find %s; "
                 "probably miniprelude.c is out of date",
                 feature_name);
    }

    rb_vm_t *vm = GET_VM();
    static const rb_compile_option_t optimization = {
        .inline_const_cache = TRUE,
        .peephole_optimization = TRUE,
        .tailcall_optimization = FALSE,
        .specialized_instruction = TRUE,
        .operands_unification = TRUE,
        .instructions_unification = TRUE,
        .frozen_string_literal = TRUE,
        .debug_frozen_string_literal = FALSE,
        .coverage_enabled = FALSE,
        .debug_level = 0,
    };

    if (rb_ruby_prism_p()) {
        pm_parse_result_t result = { 0 };
        pm_prelude_load(&result, name_str, code, start_line);

        vm->builtin_function_table = table;
        int error_state;
        iseq = pm_iseq_new_with_opt(&result.node, name_str, name_str, Qnil, 0, NULL, 0, ISEQ_TYPE_TOP, &optimization, &error_state);

        vm->builtin_function_table = NULL;
        pm_parse_result_free(&result);

        if (error_state) {
            RUBY_ASSERT(iseq == NULL);
            rb_jump_tag(error_state);
        }
    }
    else {
        VALUE ast_value = prelude_ast_value(name_str, code, start_line);
        rb_ast_t *ast = rb_ruby_ast_data_get(ast_value);

        vm->builtin_function_table = table;
        iseq = rb_iseq_new_with_opt(ast_value, name_str, name_str, Qnil, 0, NULL, 0, ISEQ_TYPE_TOP, &optimization, Qnil);

        vm->builtin_function_table = NULL;
        rb_ast_dispose(ast);
    }

    // for debug
    if (0 && strcmp("prelude", feature_name) == 0) {
        rb_io_write(rb_stdout, rb_iseq_disasm((const rb_iseq_t *)iseq));
    }

    BUILTIN_LOADED(feature_name, iseq);

    return iseq;
}

void
rb_load_with_builtin_functions(const char *feature_name, const struct rb_builtin_function *table)
{
    const rb_iseq_t *iseq = builtin_iseq_load(feature_name, table);
    rb_iseq_eval(iseq, rb_root_box());
}

VALUE
rb_define_gem_modules(VALUE flags_value, VALUE _)
{
#ifdef __COSMOPOLITAN__
    /* CosmoRuby builds the full interpreter through the mini_builtin
       path (builtin_binary.rbbin is a stub), so the Gem modules must be
       defined here too. Mirrors rb_define_gem_modules in builtin.c. */
    rb_box_gem_flags_t *flags = (rb_box_gem_flags_t *)flags_value;

    if (flags->gem) {
        rb_define_module("Gem");
        if (flags->error_highlight) {
            rb_define_module("ErrorHighlight");
        }
        if (flags->did_you_mean) {
            rb_define_module("DidYouMean");
        }
        if (flags->syntax_suggest) {
            rb_define_module("SyntaxSuggest");
        }
    }
#endif
    // upstream: do nothing - miniruby doesn't load gem_prelude.rb.
    return Qnil;
}

void
rb_load_gem_prelude(VALUE box)
{
#ifdef __COSMOPOLITAN__
    /* CosmoRuby: load gem_prelude from miniprelude.c into the given box
       (mirrors rb_load_gem_prelude in builtin.c). */
    const rb_iseq_t *iseq = builtin_iseq_load("gem_prelude", NULL);
    rb_iseq_eval(iseq, (const rb_box_t *)box);
#endif
    // upstream: do nothing - miniruby doesn't support loading RubyGems.
}
