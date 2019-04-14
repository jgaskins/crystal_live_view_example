require "http"
require "http/server/handlers/websocket_handler"
require "json"
require "ecr"

module Route
  def route(context, &block : Request, Response ->)
    request = Request.new(context.request)
    response = Response.new(context.response)

    yield request, response

    unless request.handled?
      not_found! request, response
    end
  end

  # def route(context, &block : Request, Response, HTTP::Session ->)
  #   request = Request.new(context.request)
  #   response = Response.new(context.response)

  #   yield request, response, context.session

  #   unless request.handled?
  #     not_found! request, response
  #   end
  # end

  def not_found!(request, response)
    response.status_code = 404
    # render "not_found", to: response
  end

  macro render(template, to io)
    # I'd like to have it render the template to the same IO as the layout, but
    # I can't figure out how to do that yet.
    __template__ = ECR.render "views/{{template.id}}.ecr"
    ECR.embed "views/layout.ecr", {{io}}
  end

  class Request
    delegate headers, :headers=, status, :status=, body, to: @request

    @handled = false

    def initialize(@request : HTTP::Request)
    end

    def params
      @request.query_params
    end

    def root
      return if handled?

      is("/") { yield }
      is("") { yield }
    end

    def post
      return if @handled

      if @request.method == "POST"
        yield
        handled!
      end
    end

    def post(path : String)
      is(path) { post { yield } }
    end

    def get(path : String)
      is(path) { get { yield } }
    end

    def get
      return if handled?

      if @request.method == "GET"
        yield
        handled!
      end
    end

    def delete
      return if handled?

      if @request.method == "DELETE"
        yield
        handled!
      end
    end

    def is(path : String = "")
      return if handled?

      if path.sub(%r(/), "") == @request.path.sub(%r(/), "")
        yield
        handled!
      end
    end

    def on(path : String)
      return if handled?

      if match?(path)
        begin
          old_path = @request.path
          @request.path = @request.path.sub(/\A\/?#{path}/, "")
          yield
          handled!
        ensure
          @request.path = old_path
        end
      end
    end

    def on(capture : Symbol)
      return if handled?

      old_path = @request.path
      match = %r(\A/?[^/]+).match @request.path.sub(%r(\A/), "")
      if match
        @request.path = @request.path.sub(%r(\A/#{match[0]}), "")

        yield match[0]
        handled!
      end
      @request.path = old_path
    end

    def miss
      return if handled?

      yield
      handled!
    end

    def url : URI
      @uri ||= URI.parse("https://#{@request.host_with_port}/#{@request.path}")
    end

    private def match?(path : String)
      @request.path.starts_with?(path) || @request.path.starts_with?("/#{path}")
    end

    def handled?
      @handled
    end

    def handled!
      @handled = true
    end
  end

  class Response < IO
    @response : HTTP::Server::Response

    delegate headers, read, write, :status_code=, to: @response

    def initialize(@response)
    end

    def json(serializer)
      @response.headers["Content-Type"] = "application/json"
      serializer.to_json @response
    end

    def json(**stuff)
      @response.headers["Content-Type"] = "application/json"
      stuff.to_json @response
    end
  end

  class UnauthenticatedException < Exception
  end

  class RequestHandled < Exception
  end
end
