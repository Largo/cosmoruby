#include "prism/extension.h"
#include "ruby/config.h"

void ruby_init_ext(const char *name, void (*init)(void));

void
Init_Prism(void)
{
    ruby_init_ext("prism/prism" DLEXT, Init_prism);
}
