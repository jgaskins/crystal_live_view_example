require "http"
require "./route"
require "./live_view"

module LiveViewExample
  VERSION = "0.1.0"

  class App
    include HTTP::Handler
    include Route

    def call(context)
      route context do |r, response|
        r.root { HomePage.new(response).to_s response }

        r.on "live-view" do
          r.websocket context do |socket|
            LiveView.handle socket
          end
        end
      end
    end
  end
end

class HomePage
  include LiveView

  def initialize(@io : IO)
    @count = 0
  end

  ECR.def_to_s("views/home_page.ecr")

  def mount(socket)
    every(1.second) { update(socket) }
  end

  def unmount(socket)
  end

  def handle_event(name : String, socket : HTTP::WebSocket)
    case name
    when "increment"
      update(socket) { @count += 1 }
    when "decrement"
      update(socket) { @count -= 1 }
    end
  end
end

server = HTTP::Server.new([
  HTTP::StaticFileHandler.new("public", directory_listing: false),
  LiveViewExample::App.new,
])
puts "Listening on 8080"
server.listen 8080
