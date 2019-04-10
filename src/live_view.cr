require "uuid"
require "uuid/json"
require "json"
require "http/web_socket"

module LiveView
  CHANNELS = Hash(String, Channel).new

  # spawn do
  #   loop do
  #     pp channels: CHANNELS.size
  #     sleep 1
  #   end
  # end
  spawn do
    loop do
      sleep 5
      CHANNELS.delete_if do |key, channel|
        !channel.connected?
      end
    end
  end
  @__mounted__ = false

  macro live_view(id = UUID.random, &block)
    @live_view_id = {{id}}
    %stuff = ->() {
      __io__ = IO::Memory.new
      {{ block.body }}
      __io__.to_s
    }
    CHANNELS[live_view_id.to_s] = Channel.new(self, %stuff)
    @io << %{<div data-live-view="#{live_view_id}">}
    {{ yield }}
    @io << %{</div>}
  end

  def __mount__(socket)
    @__mounted__ = true
    mount socket
  end

  def __unmount__(socket)
    @__mounted__ = false
    unmount socket
  end

  abstract def mount(socket : HTTP::WebSocket)
  abstract def unmount(socket : HTTP::WebSocket)
  abstract def handle_event(event_name : String, socket : HTTP::WebSocket)

  macro update(socket, &block)
    @io = SocketWrapper.new({{socket}})
    {{ block.body unless block.is_a? Nop }}

    %json = {
      render: CHANNELS[live_view_id.to_s].render,
      id: live_view_id,
    }.to_json
    {{socket}}.send(%json)
  end

  def live_view_id
    (@live_view_id ||= UUID.random).not_nil!
  end

  def every(duration : Time::Span, &block)
    spawn do
      while mounted?
        block.call
        sleep duration
      end
    rescue ex
      STDERR.puts ex
      STDERR.puts ex.backtrace
    end
  end

  def mounted?
    @__mounted__
  end

  def self.handle(socket)
    channel = nil

    socket.on_message do |msg|
      json = JSON.parse(msg)
      if channel.nil? && (channel = json["subscribe"]?)
        LiveView::CHANNELS[channel.not_nil!.as_s].mount(socket)
      elsif event_name = json["event"]?
        LiveView::CHANNELS[channel.not_nil!.as_s]
          .handle_event(event_name.as_s, socket)
      end
    rescue JSON::ParseException
      # Fuck this message
    end

    socket.on_close do |wat|
      if channel
        channel_name = channel.not_nil!.as_s
        ::LiveView::CHANNELS[channel_name].unmount(socket)
        ::LiveView::CHANNELS.delete channel_name
      end
    end
  end

  class SocketWrapper < IO
    def initialize(@socket : HTTP::WebSocket)
    end

    def inspect(io)
      io << "#<SocketWrapper>"
    end

    def read(slice : Bytes)
      raise Exception.new("NOPE")
    end

    # def write(string : String)
    #   write string.to_slice
    # end

    def write(bytes : Bytes)
      @socket.send bytes
    end
  end

  class Channel
    def initialize(@live_view : LiveView, @render : -> String)
      @sockets = Set(HTTP::WebSocket).new
    end

    def mount(socket : HTTP::WebSocket)
      @sockets << socket
      @live_view.__mount__ socket
    end

    def unmount(socket : HTTP::WebSocket)
      @sockets.delete socket
      @live_view.__unmount__ socket
    end

    def handle_event(message, socket)
      @live_view.handle_event(message, socket)
    end

    def connected?
      !@sockets.empty?
    end

    def render
      @render.call
    end
  end
end
