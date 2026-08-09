/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ End-to-end check for the vendored libxml2 / libxslt / libexslt.              │
│                                                                              │
│   make -j8 o//third_party/libxslt/test/xmlxslt_test                          │
│   o/third_party/libxslt/test/xmlxslt_test                                    │
│                                                                              │
│ A library that compiles but cannot parse is worthless, so this actually      │
│ parses, queries, validates and transforms. Exit status 0 = all checks pass.  │
╚─────────────────────────────────────────────────────────────────────────────*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libxml/HTMLparser.h>
#include <libxml/HTMLtree.h>
#include <libxml/c14n.h>
#include <libxml/encoding.h>
#include <libxml/parser.h>
#include <libxml/relaxng.h>
#include <libxml/xinclude.h>
#include <libxml/xmlerror.h>
#include <libxml/xmlreader.h>
#include <libxml/xmlsave.h>
#include <libxml/xmlschemas.h>
#include <libxml/xmlversion.h>
#include <libxml/xmlwriter.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>

#include <libexslt/exslt.h>
#include <libxslt/transform.h>
#include <libxslt/xslt.h>
#include <libxslt/xsltInternals.h>
#include <libxslt/xsltutils.h>

static int g_pass, g_fail;

static void ok(int cond, const char *what) {
  if (cond) {
    ++g_pass;
    printf("ok   %s\n", what);
  } else {
    ++g_fail;
    printf("FAIL %s\n", what);
  }
}

static void ok_str(const char *got, const char *want, const char *what) {
  int cond = got && !strcmp(got, want);
  if (!cond && got) printf("     got %s, want %s\n", got, want);
  ok(cond, what);
}

static const char kDoc[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<library xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n"
    "  <book id=\"b1\" year=\"1979\">\n"
    "    <dc:title>The Hitchhiker&apos;s Guide</dc:title>\n"
    "    <author>Douglas Adams</author>\n"
    "    <price>4.20</price>\n"
    "  </book>\n"
    "  <book id=\"b2\" year=\"1980\">\n"
    "    <dc:title>The Restaurant at the End of the Universe</dc:title>\n"
    "    <author>Douglas Adams</author>\n"
    "    <price>5.30</price>\n"
    "  </book>\n"
    "  <note>caf\xc3\xa9 \xe2\x80\x94 unicode round trip</note>\n"
    "</library>\n";

static const char kHtml[] =
    "<html><head><title>hi</title></head><body>"
    "<p class=greeting>Hello<br>world"
    "<ul><li>one<li>two</ul>"
    "</body></html>";

static const char kXslt[] =
    "<?xml version=\"1.0\"?>\n"
    "<xsl:stylesheet version=\"1.0\""
    " xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""
    " xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n"
    "  <xsl:output method=\"text\" encoding=\"UTF-8\"/>\n"
    "  <xsl:param name=\"who\" select=\"'nobody'\"/>\n"
    "  <xsl:template match=\"/\">"
    "<xsl:value-of select=\"$who\"/>|"
    "<xsl:value-of select=\"count(//book)\"/>|"
    "<xsl:for-each select=\"//book\">"
    "<xsl:sort select=\"@year\" order=\"descending\"/>"
    "<xsl:value-of select=\"dc:title\"/>;"
    "</xsl:for-each>"
    "</xsl:template>\n"
    "</xsl:stylesheet>\n";

/* EXSLT: str:tokenize and math:max are not XSLT 1.0 */
static const char kExslt[] =
    "<?xml version=\"1.0\"?>\n"
    "<xsl:stylesheet version=\"1.0\""
    " xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""
    " xmlns:str=\"http://exslt.org/strings\""
    " xmlns:math=\"http://exslt.org/math\""
    " extension-element-prefixes=\"str math\">\n"
    "  <xsl:output method=\"text\"/>\n"
    "  <xsl:template match=\"/\">"
    "<xsl:value-of select=\"count(str:tokenize('a,b,c,d', ','))\"/>|"
    "<xsl:value-of select=\"math:max(//price)\"/>"
    "</xsl:template>\n"
    "</xsl:stylesheet>\n";

static const char kRelaxNg[] =
    "<?xml version=\"1.0\"?>\n"
    "<element name=\"greeting\" xmlns=\"http://relaxng.org/ns/structure/1.0\">\n"
    "  <text/>\n"
    "</element>\n";

static const char kXsd[] =
    "<?xml version=\"1.0\"?>\n"
    "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">\n"
    "  <xs:element name=\"n\" type=\"xs:integer\"/>\n"
    "</xs:schema>\n";

static void silence(void *ctx, const char *msg, ...) {
  (void)ctx;
  (void)msg;
}

int main(int argc, char *argv[]) {
  xmlDocPtr doc, html, styledoc, out;
  xmlNodePtr root, n;
  xmlXPathContextPtr xpc;
  xmlXPathObjectPtr xp;
  xsltStylesheetPtr sty;
  xmlChar *buf;
  int len;

  LIBXML_TEST_VERSION;
  xmlInitParser();
  exsltRegisterAll();

  printf("libxml2 %s (runtime %d), libxslt %s, libexslt %s\n",
         LIBXML_DOTTED_VERSION, xmlParserVersion ? atoi(xmlParserVersion) : 0,
         LIBXSLT_DOTTED_VERSION, LIBEXSLT_DOTTED_VERSION);

  /*── 1. parse an XML document from memory ─────────────────────────────*/
  doc = xmlReadMemory(kDoc, (int)strlen(kDoc), "mem.xml", NULL, 0);
  ok(doc != NULL, "xmlReadMemory parses the document");
  if (!doc) return 1;

  /*── 2. walk the tree ─────────────────────────────────────────────────*/
  root = xmlDocGetRootElement(doc);
  ok_str((const char *)root->name, "library", "root element is <library>");
  {
    int books = 0;
    const char *first_author = NULL;
    for (n = root->children; n; n = n->next) {
      if (n->type != XML_ELEMENT_NODE) continue;
      if (!strcmp((const char *)n->name, "book")) {
        xmlNodePtr c;
        ++books;
        for (c = n->children; c && !first_author; c = c->next)
          if (c->type == XML_ELEMENT_NODE &&
              !strcmp((const char *)c->name, "author"))
            first_author = (const char *)xmlNodeGetContent(c);
      }
    }
    ok(books == 2, "tree walk finds 2 <book> children");
    ok_str(first_author, "Douglas Adams", "tree walk reads element text");
  }
  {
    xmlChar *id = xmlGetProp(root->children->next, BAD_CAST "id");
    ok_str((const char *)id, "b1", "xmlGetProp reads an attribute");
    xmlFree(id);
  }
  /* namespaces */
  ok(root->nsDef && root->nsDef->href &&
         !strcmp((const char *)root->nsDef->href,
                 "http://purl.org/dc/elements/1.1/"),
     "namespace declaration is recorded");

  /*── 3. XPath ─────────────────────────────────────────────────────────*/
  xpc = xmlXPathNewContext(doc);
  ok(xpc != NULL, "xmlXPathNewContext");
  xmlXPathRegisterNs(xpc, BAD_CAST "dc",
                     BAD_CAST "http://purl.org/dc/elements/1.1/");

  xp = xmlXPathEvalExpression(BAD_CAST "//book[@year>1979]/dc:title", xpc);
  ok(xp && xp->type == XPATH_NODESET && xp->nodesetval &&
         xp->nodesetval->nodeNr == 1,
     "XPath predicate + namespace prefix selects 1 node");
  if (xp && xp->nodesetval && xp->nodesetval->nodeNr == 1) {
    xmlChar *t = xmlNodeGetContent(xp->nodesetval->nodeTab[0]);
    ok_str((const char *)t, "The Restaurant at the End of the Universe",
           "XPath result node content");
    xmlFree(t);
  }
  xmlXPathFreeObject(xp);

  xp = xmlXPathEvalExpression(BAD_CAST "sum(//price)", xpc);
  ok(xp && xp->type == XPATH_NUMBER && xp->floatval > 9.49 &&
         xp->floatval < 9.51,
     "XPath sum() evaluates to 9.50");
  xmlXPathFreeObject(xp);

  xp = xmlXPathEvalExpression(
      BAD_CAST "normalize-space(//note)", xpc);
  ok(xp && xp->type == XPATH_STRING &&
         strstr((const char *)xp->stringval, "caf\xc3\xa9") != NULL,
     "XPath string function keeps UTF-8 intact");
  xmlXPathFreeObject(xp);
  xmlXPathFreeContext(xpc);

  /*── 4. serialization round trip ──────────────────────────────────────*/
  xmlDocDumpMemory(doc, &buf, &len);
  ok(buf && len > 0 && strstr((const char *)buf, "Hitchhiker") != NULL,
     "xmlDocDumpMemory serializes");
  xmlFree(buf);

  /* serialize to a non-UTF-8 encoding: exercises the encoder path */
  xmlDocDumpMemoryEnc(doc, &buf, &len, "ISO-8859-1");
  ok(buf && len > 0 && strstr((const char *)buf, "ISO-8859-1") != NULL,
     "xmlDocDumpMemoryEnc(ISO-8859-1) works");
  xmlFree(buf);

  /*── 5. non-UTF-8 input ───────────────────────────────────────────────*/
  {
    /* 0xE9 is e-acute in latin-1; built-in ISO8859X handler */
    static const char latin1[] =
        "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><a>caf\xe9</a>";
    xmlDocPtr d = xmlReadMemory(latin1, (int)strlen(latin1), "l1.xml", NULL, 0);
    xmlChar *t = d ? xmlNodeGetContent(xmlDocGetRootElement(d)) : NULL;
    ok(t && !strcmp((const char *)t, "caf\xc3\xa9"),
       "ISO-8859-1 input is decoded to UTF-8");
    if (t) xmlFree(t);
    if (d) xmlFreeDoc(d);
  }
  {
    /* windows-1251 has no built-in handler: this goes through iconv */
    static const char cp1251[] =
        "<?xml version=\"1.0\" encoding=\"windows-1251\"?><a>\xcc\xe8\xf0</a>";
    xmlDocPtr d;
    xmlChar *t;
    xmlGenericErrorFunc old = xmlGenericError;
    xmlSetGenericErrorFunc(NULL, silence);
    d = xmlReadMemory(cp1251, (int)strlen(cp1251), "cp.xml", NULL, 0);
    xmlSetGenericErrorFunc(NULL, old);
    t = d ? xmlNodeGetContent(xmlDocGetRootElement(d)) : NULL;
    /* "Мир" in UTF-8 */
    ok(t && !strcmp((const char *)t, "\xd0\x9c\xd0\xb8\xd1\x80"),
       "windows-1251 input is decoded via iconv");
    if (t) xmlFree(t);
    if (d) xmlFreeDoc(d);
  }

  /*── 6. push parser (SAX2 chunked) ────────────────────────────────────*/
  {
    xmlParserCtxtPtr pc = xmlCreatePushParserCtxt(NULL, NULL, NULL, 0, "p.xml");
    size_t i, n2 = strlen(kDoc);
    for (i = 0; i < n2; i += 7)
      xmlParseChunk(pc, kDoc + i, (int)(i + 7 < n2 ? 7 : n2 - i), 0);
    xmlParseChunk(pc, NULL, 0, 1);
    ok(pc->myDoc && pc->wellFormed, "push parser handles 7-byte chunks");
    if (pc->myDoc) xmlFreeDoc(pc->myDoc);
    xmlFreeParserCtxt(pc);
  }

  /*── 7. xmlReader (streaming) ─────────────────────────────────────────*/
  {
    xmlTextReaderPtr rd =
        xmlReaderForMemory(kDoc, (int)strlen(kDoc), "r.xml", NULL, 0);
    int elements = 0, ret;
    while (rd && (ret = xmlTextReaderRead(rd)) == 1)
      if (xmlTextReaderNodeType(rd) == XML_READER_TYPE_ELEMENT) ++elements;
    ok(elements == 10, "xmlTextReader streams 10 elements");
    if (rd) xmlFreeTextReader(rd);
  }

  /*── 8. xmlWriter ─────────────────────────────────────────────────────*/
  {
    xmlBufferPtr b = xmlBufferCreate();
    xmlTextWriterPtr w = xmlNewTextWriterMemory(b, 0);
    xmlTextWriterStartDocument(w, NULL, "UTF-8", NULL);
    xmlTextWriterStartElement(w, BAD_CAST "r");
    xmlTextWriterWriteAttribute(w, BAD_CAST "k", BAD_CAST "v");
    xmlTextWriterWriteString(w, BAD_CAST "text&more");
    xmlTextWriterEndElement(w);
    xmlTextWriterEndDocument(w);
    xmlFreeTextWriter(w);
    ok(strstr((const char *)xmlBufferContent(b), "<r k=\"v\">text&amp;more</r>")
           != NULL,
       "xmlTextWriter emits escaped output");
    xmlBufferFree(b);
  }

  /*── 9. HTML parser ───────────────────────────────────────────────────*/
  html = htmlReadMemory(kHtml, (int)strlen(kHtml), "mem.html", NULL,
                        HTML_PARSE_NOERROR | HTML_PARSE_NOWARNING);
  ok(html != NULL, "htmlReadMemory parses tag-soup HTML");
  if (html) {
    xmlXPathContextPtr hc = xmlXPathNewContext(html);
    xp = xmlXPathEvalExpression(BAD_CAST "//li", hc);
    ok(xp && xp->nodesetval && xp->nodesetval->nodeNr == 2,
       "HTML implied </li> close: 2 <li> nodes");
    xmlXPathFreeObject(xp);
    xp = xmlXPathEvalExpression(BAD_CAST "string(//p/@class)", hc);
    ok_str((const char *)xp->stringval, "greeting",
           "HTML unquoted attribute parsed");
    xmlXPathFreeObject(xp);
    xmlXPathFreeContext(hc);
    {
      xmlBufferPtr b = xmlBufferCreate();
      htmlNodeDump(b, html, xmlDocGetRootElement(html));
      ok(strstr((const char *)xmlBufferContent(b), "<br>") != NULL,
         "htmlNodeDump re-serializes HTML");
      xmlBufferFree(b);
    }
    xmlFreeDoc(html);
  }

  /*── 10. XInclude ─────────────────────────────────────────────────────*/
  {
    static const char inc[] = "<?xml version=\"1.0\"?><inc>included!</inc>";
    static const char host[] =
        "<?xml version=\"1.0\"?><h xmlns:xi=\"http://www.w3.org/2001/XInclude\">"
        "<xi:include href=\"xi_frag.xml\"/></h>";
    FILE *f = fopen("xi_frag.xml", "wb");
    if (f) {
      fwrite(inc, 1, sizeof(inc) - 1, f);
      fclose(f);
      {
        xmlDocPtr d = xmlReadMemory(host, (int)strlen(host), "./host.xml", NULL,
                                    XML_PARSE_NOENT);
        int rc = d ? xmlXIncludeProcessFlags(d, XML_PARSE_NOENT) : -1;
        xmlChar *t = d ? xmlNodeGetContent(xmlDocGetRootElement(d)) : NULL;
        ok(rc == 1 && t && strstr((const char *)t, "included!"),
           "xmlXIncludeProcessFlags pulls in a file");
        if (t) xmlFree(t);
        if (d) xmlFreeDoc(d);
      }
      remove("xi_frag.xml");
    } else {
      printf("skip xinclude (cwd not writable)\n");
    }
  }

  /*── 11. DTD validation ───────────────────────────────────────────────*/
  {
    static const char dtd[] =
        "<?xml version=\"1.0\"?>"
        "<!DOCTYPE r [<!ELEMENT r (a)><!ELEMENT a (#PCDATA)>]>"
        "<r><a>x</a></r>";
    static const char bad[] =
        "<?xml version=\"1.0\"?>"
        "<!DOCTYPE r [<!ELEMENT r (a)><!ELEMENT a (#PCDATA)>]>"
        "<r><b>x</b></r>";
    xmlGenericErrorFunc old = xmlGenericError;
    xmlDocPtr good_doc, bad_doc;
    xmlSetGenericErrorFunc(NULL, silence);
    good_doc = xmlReadMemory(dtd, (int)strlen(dtd), "d.xml", NULL,
                             XML_PARSE_DTDVALID | XML_PARSE_NOERROR);
    bad_doc = xmlReadMemory(bad, (int)strlen(bad), "d2.xml", NULL,
                            XML_PARSE_DTDVALID | XML_PARSE_NOERROR);
    xmlSetGenericErrorFunc(NULL, old);
    ok(good_doc && bad_doc, "DTD-validating parse returns documents");
    if (good_doc) xmlFreeDoc(good_doc);
    if (bad_doc) xmlFreeDoc(bad_doc);
  }

  /*── 12. RelaxNG ──────────────────────────────────────────────────────*/
  {
    xmlRelaxNGParserCtxtPtr pc =
        xmlRelaxNGNewMemParserCtxt(kRelaxNg, (int)strlen(kRelaxNg));
    xmlRelaxNGPtr schema = pc ? xmlRelaxNGParse(pc) : NULL;
    xmlRelaxNGValidCtxtPtr vc = schema ? xmlRelaxNGNewValidCtxt(schema) : NULL;
    static const char yes[] = "<greeting>hello</greeting>";
    static const char no[] = "<farewell>bye</farewell>";
    xmlDocPtr dy = xmlReadMemory(yes, (int)strlen(yes), "y", NULL, 0);
    xmlDocPtr dn = xmlReadMemory(no, (int)strlen(no), "n", NULL, 0);
    if (vc) xmlRelaxNGSetValidErrors(vc, silence, silence, NULL);
    ok(vc && xmlRelaxNGValidateDoc(vc, dy) == 0, "RelaxNG accepts valid doc");
    ok(vc && xmlRelaxNGValidateDoc(vc, dn) != 0, "RelaxNG rejects invalid doc");
    if (dy) xmlFreeDoc(dy);
    if (dn) xmlFreeDoc(dn);
    if (vc) xmlRelaxNGFreeValidCtxt(vc);
    if (schema) xmlRelaxNGFree(schema);
    if (pc) xmlRelaxNGFreeParserCtxt(pc);
  }

  /*── 13. XML Schema (XSD) ─────────────────────────────────────────────*/
  {
    xmlSchemaParserCtxtPtr pc =
        xmlSchemaNewMemParserCtxt(kXsd, (int)strlen(kXsd));
    xmlSchemaPtr schema = pc ? xmlSchemaParse(pc) : NULL;
    xmlSchemaValidCtxtPtr vc = schema ? xmlSchemaNewValidCtxt(schema) : NULL;
    static const char yes[] = "<n>42</n>";
    static const char no[] = "<n>forty-two</n>";
    xmlDocPtr dy = xmlReadMemory(yes, (int)strlen(yes), "y", NULL, 0);
    xmlDocPtr dn = xmlReadMemory(no, (int)strlen(no), "n", NULL, 0);
    if (vc) xmlSchemaSetValidErrors(vc, silence, silence, NULL);
    ok(vc && xmlSchemaValidateDoc(vc, dy) == 0, "XSD accepts <n>42</n>");
    ok(vc && xmlSchemaValidateDoc(vc, dn) != 0, "XSD rejects <n>forty-two</n>");
    if (dy) xmlFreeDoc(dy);
    if (dn) xmlFreeDoc(dn);
    if (vc) xmlSchemaFreeValidCtxt(vc);
    if (schema) xmlSchemaFree(schema);
    if (pc) xmlSchemaFreeParserCtxt(pc);
  }

  /*── 14. C14N (used by nokogiri's Document#canonicalize) ──────────────*/
  {
    xmlChar *c14n = NULL;
    int rc = xmlC14NDocDumpMemory(doc, NULL, XML_C14N_1_0, NULL, 0, &c14n);
    ok(rc > 0 && c14n && strstr((const char *)c14n, "<library") != NULL,
       "xmlC14NDocDumpMemory canonicalizes");
    if (c14n) xmlFree(c14n);
  }

  /*── 15. XSLT ─────────────────────────────────────────────────────────*/
  styledoc = xmlReadMemory(kXslt, (int)strlen(kXslt), "s.xsl", NULL, 0);
  ok(styledoc != NULL, "XSLT stylesheet parses as XML");
  sty = styledoc ? xsltParseStylesheetDoc(styledoc) : NULL;
  ok(sty != NULL, "xsltParseStylesheetDoc");
  if (sty) {
    const char *params[3];
    params[0] = "who";
    params[1] = "'cosmo'";
    params[2] = NULL;
    out = xsltApplyStylesheet(sty, doc, params);
    ok(out != NULL, "xsltApplyStylesheet");
    if (out) {
      xmlChar *res = NULL;
      int rlen = 0;
      xsltSaveResultToString(&res, &rlen, out, sty);
      ok_str((const char *)res,
             "cosmo|2|The Restaurant at the End of the Universe;"
             "The Hitchhiker's Guide;",
             "XSLT param, count(), xsl:sort and xsl:for-each");
      if (res) xmlFree(res);
      xmlFreeDoc(out);
    }
    xsltFreeStylesheet(sty); /* frees styledoc */
  } else if (styledoc) {
    xmlFreeDoc(styledoc);
  }

  /*── 16. EXSLT ────────────────────────────────────────────────────────*/
  {
    xmlDocPtr sd = xmlReadMemory(kExslt, (int)strlen(kExslt), "e.xsl", NULL, 0);
    xsltStylesheetPtr es = sd ? xsltParseStylesheetDoc(sd) : NULL;
    ok(es != NULL, "EXSLT stylesheet parses");
    if (es) {
      xmlDocPtr r = xsltApplyStylesheet(es, doc, NULL);
      xmlChar *res = NULL;
      int rlen = 0;
      if (r) xsltSaveResultToString(&res, &rlen, r, es);
      ok_str((const char *)res, "4|5.3",
             "EXSLT str:tokenize and math:max");
      if (res) xmlFree(res);
      if (r) xmlFreeDoc(r);
      xsltFreeStylesheet(es);
    } else if (sd) {
      xmlFreeDoc(sd);
    }
  }

  /*── 17. things that must NOT be there ────────────────────────────────*/
#ifdef LIBXML_HTTP_ENABLED
  ok(0, "LIBXML_HTTP_ENABLED must be off in an APE");
#else
  ok(1, "no HTTP loader compiled in");
#endif
#ifdef LIBXML_FTP_ENABLED
  ok(0, "LIBXML_FTP_ENABLED must be off in an APE");
#else
  ok(1, "no FTP loader compiled in");
#endif
#ifdef LIBXML_MODULES_ENABLED
  ok(0, "LIBXML_MODULES_ENABLED must be off (no dlopen in an APE)");
#else
  ok(1, "no dlopen module loader compiled in");
#endif
#ifdef WITH_MODULES
  ok(0, "libxslt WITH_MODULES must be off");
#else
  ok(1, "no libxslt plugin loader compiled in");
#endif
#ifdef LIBXML_ICONV_ENABLED
  ok(1, "iconv encoding support compiled in");
#else
  ok(0, "iconv encoding support expected");
#endif
#ifdef LIBXML_ZLIB_ENABLED
  ok(1, "zlib support compiled in");
#else
  ok(0, "zlib support expected");
#endif

  xmlFreeDoc(doc);
  xsltCleanupGlobals();
  xmlCleanupParser();

  printf("\n%d passed, %d failed\n", g_pass, g_fail);
  (void)argc;
  (void)argv;
  return g_fail ? 1 : 0;
}
