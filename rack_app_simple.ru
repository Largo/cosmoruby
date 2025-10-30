# Rack application config file
# Run with: ruby.com -e "require 'rack'; app = Rack::Builder.parse_file('rack_app_simple.ru'); Rack::Handler::WEBrick.run(app, Port: 9292)"

require 'rack'

# Simple Rack app
app = Rack::Builder.new do
  use Rack::CommonLogger
  use Rack::ShowExceptions
  use Rack::Lint

  map "/" do
    run lambda { |env|
      html = <<-HTML
        <!DOCTYPE html>
        <html>
        <head><title>Cosmopolitan Ruby + Rack</title></head>
        <body>
          <h1>Hello from Cosmopolitan Ruby + Rack!</h1>
          <p><strong>Ruby Version:</strong> #{RUBY_VERSION}</p>
          <p><strong>Rack Version:</strong> #{Rack::VERSION}</p>
          <p><strong>Request Method:</strong> #{env['REQUEST_METHOD']}</p>
          <p><strong>Request Path:</strong> #{env['PATH_INFO']}</p>
          <p><strong>Query String:</strong> #{env['QUERY_STRING']}</p>
          <hr>
          <h2>Test Links:</h2>
          <ul>
            <li><a href="/">Home</a></li>
            <li><a href="/json">JSON API</a></li>
            <li><a href="/?name=World">Query String Test</a></li>
          </ul>
        </body>
        </html>
      HTML

      [200, { "content-type" => "text/html" }, [html]]
    }
  end

  map "/json" do
    run lambda { |env|
      require 'json'
      data = {
        message: "Hello from Cosmopolitan Ruby!",
        ruby_version: RUBY_VERSION,
        rack_version: Rack::VERSION,
        timestamp: Time.now.to_s
      }
      [200, { "content-type" => "application/json" }, [data.to_json]]
    }
  end
end

run app
