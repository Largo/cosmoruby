# frozen_string_literal: true
#
# CosmoRuby nokogiri test.
#
#   ruby.com third_party/ruby/cosmo_tests/test_nokogiri.rb
#
# Exercises the statically linked nokogiri extension against
# third_party/libxml2 (2.13.9) and third_party/libxslt (1.1.43):
# XML and HTML4 parsing, CSS and XPath queries, namespaces, node
# mutation and serialization, HTML5 (gumbo), XSD/RelaxNG validation,
# XSLT and encodings. Exit status 0 means every check passed.

require "nokogiri"

$pass = 0
$fail = 0

def check(name)
  got = yield
  if got
    $pass += 1
    puts "PASS: #{name}#{got == true ? "" : " :: #{got.inspect}"}"
  else
    $fail += 1
    puts "FAIL: #{name}"
  end
rescue => e
  $fail += 1
  puts "FAIL: #{name} :: #{e.class}: #{e.message}"
end

XML = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <library xmlns:dc="http://purl.org/dc/elements/1.1/">
    <book id="b1" year="1979">
      <dc:title>The Hitchhiker's Guide</dc:title>
      <author>Douglas Adams</author>
      <price>4.20</price>
    </book>
    <book id="b2" year="1980">
      <dc:title>The Restaurant at the End of the Universe</dc:title>
      <author>Douglas Adams</author>
      <price>5.30</price>
    </book>
    <note>café — unicode round trip</note>
  </library>
XML

HTML = <<~HTML
  <html><head><title>hi</title></head><body>
  <p class="greeting">Hello<br>world
  <ul><li>one<li>two</ul>
  <a href="/x" id="link">click</a>
  </body></html>
HTML

XSLT = <<~XSL
  <?xml version="1.0"?>
  <xsl:stylesheet version="1.0"
      xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
      xmlns:dc="http://purl.org/dc/elements/1.1/">
    <xsl:output method="text" encoding="UTF-8"/>
    <xsl:param name="who" select="'nobody'"/>
    <xsl:template match="/"><xsl:value-of select="$who"/>|<xsl:value-of
      select="count(//book)"/>|<xsl:for-each select="//book"><xsl:sort
      select="@year" order="descending"/><xsl:value-of
      select="dc:title"/>;</xsl:for-each></xsl:template>
  </xsl:stylesheet>
XSL

XSD = <<~XSD
  <?xml version="1.0"?>
  <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
    <xs:element name="n" type="xs:integer"/>
  </xs:schema>
XSD

RELAXNG = <<~RNG
  <?xml version="1.0"?>
  <element name="greeting" xmlns="http://relaxng.org/ns/structure/1.0">
    <text/>
  </element>
RNG

puts "nokogiri #{Nokogiri::VERSION}"
puts "libxml2  compiled=#{Nokogiri::VERSION_INFO["libxml"]["compiled"]} " \
     "loaded=#{Nokogiri::VERSION_INFO["libxml"]["loaded"]}"
puts "libxslt  compiled=#{Nokogiri::VERSION_INFO["libxslt"]["compiled"]} " \
     "loaded=#{Nokogiri::VERSION_INFO["libxslt"]["loaded"]}"
puts

check("no load warnings") { Nokogiri::VERSION_INFO["warnings"] == [] }
check("libxml2 iconv enabled") { Nokogiri::VERSION_INFO["libxml"]["iconv_enabled"] == true }
check("libxml2 http loader disabled") { Nokogiri::VERSION_INFO["libxml"]["http_enabled"] == false }

doc = Nokogiri::XML(XML)
check("XML parses without errors") { doc.errors.empty? && doc.root.name == "library" }
check("XPath with namespace") do
  doc.xpath("//dc:title", "dc" => "http://purl.org/dc/elements/1.1/").size == 2
end
check("XPath predicate") { doc.xpath("//book[@year>1979]/@id").first.value == "b2" }
check("XPath function") { doc.xpath("sum(//price)").round(2) == 9.5 }
check("CSS selector") { doc.css("book > author").map(&:text).uniq == ["Douglas Adams"] }
check("CSS attribute selector") { doc.css("book[id='b1']").size == 1 }
check("CSS pseudo-class :first-child") { doc.css("book:first-child").size == 1 }
check("at_css shorthand") { doc.at_css("note").text.include?("café") }
check("UTF-8 round trip") { doc.at_xpath("//note").text.include?("—") }
check("namespace introspection") do
  doc.root.namespace_definitions.map(&:href) == ["http://purl.org/dc/elements/1.1/"]
end

check("node mutation + serialize") do
  d = Nokogiri::XML(XML)
  d.at_css("library").add_child("<extra>new</extra>")
  d.at_xpath("//book[@id='b1']")["year"] = "1978"
  d.to_xml.include?("<extra>new</extra>") && d.at_xpath("//book[@id='b1']/@year").value == "1978"
end

check("builder") do
  b = Nokogiri::XML::Builder.new { |x| x.root { x.child("hi", attr: "1") } }
  b.to_xml.include?('<child attr="1">hi</child>')
end

check("document fragment") do
  Nokogiri::XML::DocumentFragment.parse("<a/><b/>").children.size == 2
end

html = Nokogiri::HTML4(HTML)
check("HTML4 parses tag soup") { html.css("li").size == 2 }
check("HTML4 CSS class selector") { html.css("p.greeting").first.text.include?("Hello") }
check("HTML4 attribute read") { html.at_css("#link")["href"] == "/x" }
check("HTML4 serialize") { html.to_html.include?("<br>") }

check("HTML5 (gumbo) parses") do
  d = Nokogiri::HTML5("<html><body><table><tr><td>x</table></body></html>")
  d.css("td").first.text == "x"
end
check("HTML5 fragment") do
  Nokogiri::HTML5.fragment("<p>a<p>b").css("p").size == 2
end

check("SAX parser") do
  klass = Class.new(Nokogiri::XML::SAX::Document) do
    attr_reader :names
    def initialize = (@names = [])
    def start_element(name, _attrs) = @names << name
  end
  h = klass.new
  Nokogiri::XML::SAX::Parser.new(h).parse(XML)
  h.names.count("book") == 2
end

check("Reader (streaming)") do
  n = 0
  Nokogiri::XML::Reader(XML).each { |node| n += 1 if node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT }
  n == 10
end

check("XSD validation") do
  schema = Nokogiri::XML::Schema(XSD)
  schema.validate(Nokogiri::XML("<n>42</n>")).empty? &&
    !schema.validate(Nokogiri::XML("<n>forty-two</n>")).empty?
end

check("RelaxNG validation") do
  schema = Nokogiri::XML::RelaxNG(RELAXNG)
  schema.validate(Nokogiri::XML("<greeting>hi</greeting>")).empty? &&
    !schema.validate(Nokogiri::XML("<farewell>bye</farewell>")).empty?
end

check("DTD validation errors are reported") do
  bad = Nokogiri::XML("<!DOCTYPE r [<!ELEMENT r (a)><!ELEMENT a (#PCDATA)>]><r><b/></r>") do |cfg|
    cfg.dtdvalid
  end
  !bad.errors.empty?
end

check("XSLT transform") do
  xslt = Nokogiri::XSLT(XSLT)
  out = xslt.transform(doc, Nokogiri::XSLT.quote_params(["who", "cosmo"]))
  xslt.serialize(out) ==
    "cosmo|2|The Restaurant at the End of the Universe;The Hitchhiker's Guide;"
end

check("XInclude") do
  require "tmpdir"
  frag = File.join(Dir.tmpdir, "noko_xi_frag.xml")
  File.write(frag, "<inc>included!</inc>")
  href = frag.tr("\\", "/")
  d = Nokogiri::XML(
    %(<h xmlns:xi="http://www.w3.org/2001/XInclude"><xi:include href="#{href}"/></h>)
  ) { |c| c.noent }
  d.do_xinclude
  d.to_xml.include?("included!")
ensure
  File.delete(frag) if frag && File.exist?(frag)
end

check("canonicalize (C14N)") { doc.canonicalize.start_with?("<library") }

check("ISO-8859-1 input decoded") do
  Nokogiri::XML(%(<?xml version="1.0" encoding="ISO-8859-1"?><a>caf\xE9</a>)).text == "café"
end
check("windows-1251 input decoded via iconv") do
  Nokogiri::XML(%(<?xml version="1.0" encoding="windows-1251"?><a>\xCC\xE8\xF0</a>)).text == "Мир"
end
check("serialize to ISO-8859-1") do
  Nokogiri::XML("<a>café</a>").to_xml(encoding: "ISO-8859-1").include?("ISO-8859-1")
end
check("EncodingHandler is available") { !Nokogiri::EncodingHandler["UTF-8"].nil? }

check("syntax errors are raised in strict mode") do
  begin
    Nokogiri::XML("<a><b></a>") { |c| c.strict }
    false
  rescue Nokogiri::XML::SyntaxError
    true
  end
end

check("registered as a default gem") do
  Gem::Specification.find_all_by_name("nokogiri").map { |s| [s.version.to_s, s.default_gem?] } ==
    [["1.19.4", true]]
end

puts
puts "RESULT: pass=#{$pass} fail=#{$fail}"
exit($fail.zero? ? 0 : 1)
