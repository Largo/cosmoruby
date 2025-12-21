/* Simple test extension for cosmo plugin loader */
#include "third_party/ruby/include/ruby/ruby.h"

static VALUE hello_world(VALUE self) {
  return rb_str_new_cstr("Hello from plugin!");
}

static VALUE hello_add(VALUE self, VALUE a, VALUE b) {
  int ia = NUM2INT(a);
  int ib = NUM2INT(b);
  return INT2NUM(ia + ib);
}

void Init_test_hello(void) {
  VALUE mod = rb_define_module("TestHello");
  rb_define_module_function(mod, "world", hello_world, 0);
  rb_define_module_function(mod, "add", hello_add, 2);
}
