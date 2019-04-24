require "http"
require "live_view"
require "neo4j"
require "pool/connection"
require "uuid"

# The top-level Data Access Object for our DB needs
abstract struct Query
  DEFAULT_POOL = ConnectionPool(Neo4j::Bolt::Connection).new(capacity: 100) do
    Neo4j::Bolt::Connection.new(ENV["NEO4J_URL"], ssl: !!ENV["NEO4J_USE_SSL"]?)
  end

  def initialize(@pool = DEFAULT_POOL)
  end

  def stream(query)
    connection do |c|
      results = c.stream(query)
      yield(results).tap do
        results.each {} # Consume the rest just in case it hasn't been done
      end
    end
  end

  def connection
    @pool.connection do |c|
      yield c
    end
  end
end

# Main app, just renders the layout that renders all of the other components
class App
  include HTTP::Handler

  def call(context)
    ECR.embed "views/home_page.ecr", context.response
  end
end

# ClickCounter has increment/decrement buttons and a counter. Each time you
# click one of the buttons, `handle_event` is invoked with the associated
# action name. We ignore the `data` argument here because there isn't any useful
# data associated with a button click.
#
# After each event is handled, we update the socket.
class ClickCounter < LiveView
  @count = 0

  template "views/click_counter.ecr"

  def handle_event(name : String, data : String, socket : HTTP::WebSocket)
    case name
    when "increment"
      update(socket) { @count += 1 }
    when "decrement"
      update(socket) { @count -= 1 }
    end
  end
end

# CurrentTime shows off how we can perform an action at specified intervals.
# After the view is mounted, we tell it to update every second, which will tell
# the client to rerender itself with our updated markup.
#
# This example also shows how we can use `render` instead of `template` to
# define our markup inline in cases where ECR templates are too much ceremony.
class CurrentTime < LiveView
  render "<time>#{Time.now}</time>"

  def mount(socket)
    every(1.second) { update socket }
  end
end

# The CheckboxExample is a component that shows off how we can work with the
# `data` argument to `handle_event`. We receive it as a string, so we go ahead
# and parse that string however it makes sense. This example uses a JSON mapping
# rather than working with `JSON::Any` and casting types.
#
# Note that the data's `value` property is the `checked` property of the
# checkbox.
class CheckboxExample < LiveView
  @checked = false

  template "views/checkbox.ecr"

  def handle_event(name, data, socket)
    change = Change.from_json data
    update(socket) { @checked = change.value }
  end

  struct Change
    JSON.mapping value: Bool
  end
end

# This example uses a text input the same way we use a checkbox above. Not much
# difference between the two - just showing that we can use text just as easily
# as booleans.
#
# We use this example to show off that we can't just use `innerHTML` on the
# client - it would *replace* the input element rather than updating it in
# place.
class TextBoxExample < LiveView
  @value = ""

  template "views/text_box.ecr"

  def handle_event(name, data, socket)
    change = Change.from_json data
    update(socket) { @value = change.value }
  end

  struct Change
    JSON.mapping value: String
  end
end

# This one's a bit more complicated. The way the states and actions work together on user interactions in an autocomplete component requires a bit more planning:
#
# - query: the text in the search box
# - results: the set of values that the query matches
# - open: whether the autocomplete box is open
class AutocompleteExample < LiveView
  @query = ""
  @results = Array(String).new
  @open = false
  @set_value = false

  # Need to have something to query against. This would normally be something
  # like a DB connection or whatever but we're just using a known list of words.
  WORDS = File.read_lines("words.txt").map(&.chomp)

  template "views/autocomplete.ecr"

  def handle_event(message, data, socket)
    case message
    when "search" # The user has typed something into the search box
      @query = Query.from_json(data).value
      @open = !@query.empty?
      if @open
        @results = WORDS.each.select(&.includes?(@query)).first(20).to_a
      else
        @results = Array(String).new
      end

      # We can also call `update` without a block, as shown here, to just update
      # the UI with whatever state we have.
      update socket
    when "select" # The user has selected an item from the dropdown
      @query = Query.from_json(data).value
      @open = false
      set_value { update socket }
    end
  end

  def set_value
    @set_value = true
    yield
    @set_value = false
  end

  struct Query
    JSON.mapping value: String
  end
end

# Here we use the `mount` callback to defer loading a bunch of data until after
# the initial page load. This is an optimization you may or may not want to
# perform sometimes when loading everything you need up front would delay
# displaying *anything* to the user until absolutely everything is loaded.
class ProductCatalogExample < LiveView
  @products = Array(Product).new

  template "views/products.ecr"

  def mount(socket)
    spawn do
      start = Time.now
      @products = ListProducts.new.call
      update socket

      puts "Sent products in #{Time.now - start}"
    end
  end

  # Build a DAO specifically for loading products.
  struct ListProducts < Query
    def call
      stream(<<-CYPHER) do |results|
        MATCH (product : Product)
        RETURN product
        ORDER BY product.price_cents
      CYPHER
        results.map do |(product)|
          Product.new(product.as Neo4j::Node)
        end
      end
    end
  end

  # The product model we'll be using in this component
  struct Product
    Neo4j.map_node(
      id: UUID,
      name: String,
      description: String,
      price_cents: Int32,
    )
  end
end

server = HTTP::Server.new([
  HTTP::WebSocketHandler.new { |socket, context| LiveView.handle socket },
  HTTP::CompressHandler.new,
  HTTP::StaticFileHandler.new("public", directory_listing: false),
  HTTP::LogHandler.new,
  App.new,
])
port = (ENV["PORT"]? || 8080).to_i
puts "Listening on #{port}"
server.listen "0.0.0.0", port
