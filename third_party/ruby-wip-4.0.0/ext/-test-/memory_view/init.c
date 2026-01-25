#include "ruby.h"

#define init(n) {void Init_##n(VALUE klass); Init_##n(klass);}

void
Init_memory_view(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_module_under(mBug, "MemoryView");
    (void)klass;
    TEST_INIT_FUNCS(init);
}