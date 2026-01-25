#include "ruby.h"

#define init(n) {void Init_##n(VALUE klass); Init_##n(klass);}

void
Init_rb_call_super_kw(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_module_under(mBug, "CallSuperKw");
    (void)klass;
    TEST_INIT_FUNCS(init);
}