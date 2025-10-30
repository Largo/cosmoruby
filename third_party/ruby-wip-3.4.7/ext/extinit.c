#include "ruby/ruby.h"

#define init(func, name) {	\
    extern void func(void);	\
    ruby_init_ext(name".so", func); \
}

void ruby_init_ext(const char *name, void (*init)(void));

void Init_ext(void)
{
    init(Init_monitor, "monitor");
    init(Init_pathname, "pathname");
    init(Init_socket, "socket");
    init(Init_stringio, "stringio");
    init(Init_zlib, "zlib");
}
