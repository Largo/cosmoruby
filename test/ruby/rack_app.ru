# Rack application config file
# Run with: rackup rack_app.ru -p 9292

require 'rack'

# Simple Rack app
app = Rack::Builder.new do
  use Rack::CommonLogger
  use Rack::ShowExceptions
  use Rack::Lint

  map "/" do
    run lambda { |env|
      [
        200,
        { "Content-Type" => "text/html" },
        [<<~HTML
          <!DOCTYPE html>
          <html>
          <head><title>Cosmopolitan Ruby + Rack</title></head>
          <body>
            <h1>🎉 Hello from Cosmopolitan Ruby + Rack! 🎉</h1>
            <p><strong>Ruby Version:</strong> #{RUBY_VERSION}</p>
            <p><strong>Rack Version:</strong> #{Rack::VERSION}</p>
            <p><strong>Request Method:</strong> #{env['REQUEST_METHOD']}</p>
            <p><strong>Request Path:</strong> #{env['PATH_INFO']}</p>
            <p><strong>Query String:</strong> #{env['QUERY_STRING']}</p>
            <hr>
            <h2>Environment Variables:</h2>
            <ul>
              #{env.sort.map { |k, v| "<li><strong>#{k}:</strong> #{v}</li>" }.join("\n              ")}
            </ul>
          </body>
          </html>
        HTML
        ]
      ]
    end
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
      [200, { "Content-Type" => "application/json" }, [data.to_json]]
    }
  end
end

run app
