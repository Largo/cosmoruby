# Minimal RbConfig for Cosmopolitan Libc
# This file provides build configuration information to Ruby programs

# Not cross-compiling for Cosmopolitan (it's "build-once run-anywhere")
CROSS_COMPILING = nil

module RbConfig
  # Base directory - use /tmp for Cosmopolitan (portable)
  TOPDIR = '/zip'

  # Platform configuration hash
  CONFIG = {
    'host_os' => 'linux-gnu',
    'host_cpu' => 'x86_64',
    'target_os' => 'cosmopolitan',
    'target_cpu' => 'x86_64',
    'RUBY_VERSION' => '3.4.7',
    'ruby_version' => '3.4.0',
    'MAJOR' => '3',
    'MINOR' => '4',
    'TEENY' => '7',
    'platform' => 'x86_64-cosmo',
    'arch' => 'x86_64-cosmo',

    # Installation directories
    'prefix' => TOPDIR,
    'bindir' => "#{TOPDIR}/bin",
    'rubylibprefix' => "#{TOPDIR}/lib/ruby",
    'libdir' => "#{TOPDIR}/lib/ruby/3.4.0",
    'rubylibdir' => "#{TOPDIR}/lib/ruby/3.4.0",
    'archdir' => "#{TOPDIR}/lib/ruby/3.4.0/x86_64-linux",
    'sitedir' => "#{TOPDIR}/lib/ruby/site_ruby",
    'sitelibdir' => "#{TOPDIR}/lib/ruby/site_ruby/3.4.0",
    'sitearchdir' => "#{TOPDIR}/lib/ruby/site_ruby/3.4.0/x86_64-linux",
    'vendordir' => "#{TOPDIR}/lib/ruby/vendor_ruby",
    'vendorlibdir' => "#{TOPDIR}/lib/ruby/vendor_ruby/3.4.0",
    'vendorarchdir' => "#{TOPDIR}/lib/ruby/vendor_ruby/3.4.0/x86_64-linux",
    'topdir' => TOPDIR,
    'configure_args' => '--disable-shared --with-static-linked-ext',
    'LDFLAGS' => '',
    'CFLAGS' => '',
    'CXXFLAGS' => '',
    'CC' => 'gcc',
    'CXX' => 'g++',
    'DLEXT' => 'so',
    'EXEEXT' => '',
    'ruby_install_name' => 'ruby',
    'RUBY_INSTALL_NAME' => 'ruby',
    'RUBY_SO_NAME' => 'ruby',
    'LIBRUBY' => 'libruby.a',
    'LIBRUBY_A' => 'libruby.a',
    'LIBS' => '-lm -lpthread -lz',
    'DLDFLAGS' => '',
    'SOLIBS' => '',
    'ENABLE_SHARED' => 'no'
  }

  # Provide Ruby version information
  RUBY_VERSION = '3.4.7'

  # Provide configuration
  def self.ruby
    CONFIG['ruby_install_name']
  end
end
