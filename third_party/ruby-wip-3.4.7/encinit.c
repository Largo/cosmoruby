/* encinit.c - Initialize statically-linked encodings for Cosmopolitan Ruby */

void Init_encdb(void);

void
Init_enc(void)
{
    Init_encdb();
}
