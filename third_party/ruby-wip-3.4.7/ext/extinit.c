#include "ruby/ruby.h"

// Modular extension system using weak symbols
// Extensions are only initialized if their .a files are linked
#define init(func, name) {	\
    extern void func(void) __attribute__((weak));	\
    if (func) ruby_init_ext(name".so", func); \
}

void ruby_init_ext(const char *name, void (*init)(void));

void Init_ext(void)
{
    init(Init_date_core, "date_core");
    init(Init_digest, "digest");
    init(Init_md5, "digest/md5");
    init(Init_sha1, "digest/sha1");
    init(Init_sha2, "digest/sha2");
    init(Init_etc, "etc");
    init(Init_nonblock, "io/nonblock");
    init(Init_generator, "json/ext/generator");
    init(Init_parser, "json/ext/parser");
    init(Init_mbedtls, "mbedtls");
    init(Init_monitor, "monitor");
    init(Init_pathname, "pathname");
    init(Init_psych, "psych");
    init(Init_socket, "socket");
    init(Init_stringio, "stringio");
    init(Init_zlib, "zlib");
}
