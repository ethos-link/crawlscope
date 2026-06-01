# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "bundler/setup"
require "crawlscope"
require "json"
require "socket"
require "time"

class DelayedHttpServer
  attr_reader :base_url

  def initialize(page_count:, delay_seconds:)
    @page_count = page_count
    @delay_seconds = delay_seconds
    @server = TCPServer.new("127.0.0.1", 0)
    @base_url = "http://127.0.0.1:#{@server.addr[1]}"
    @threads = []
  end

  def start
    @thread = Thread.new do
      loop do
        socket = @server.accept
        @threads << Thread.new(socket) { |client| respond(client) }
      rescue IOError
        break
      end
    end
  end

  def stop
    @server.close
    @thread&.join
    @threads.each(&:join)
  end

  private

  def respond(socket)
    request_line = socket.gets.to_s
    path = request_line.split[1].to_s
    read_headers(socket)

    if path == "/sitemap.xml"
      write_response(socket, sitemap_xml, content_type: "application/xml")
    else
      sleep @delay_seconds
      write_response(socket, page_html(path), content_type: "text/html")
    end
  ensure
    socket.close
  end

  def read_headers(socket)
    loop do
      line = socket.gets
      break if line.nil? || line == "\r\n"
    end
  end

  def sitemap_xml
    urls = (1..@page_count).map do |index|
      "<url><loc>#{@base_url}/pages/#{index}</loc></url>"
    end.join

    %(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{urls}</urlset>)
  end

  def page_html(path)
    <<~HTML
      <html>
        <head><title>#{path}</title></head>
        <body><main><h1>#{path}</h1><p>#{path} benchmark page</p></main></body>
      </html>
    HTML
  end

  def write_response(socket, body, content_type:)
    socket.write "HTTP/1.1 200 OK\r\n"
    socket.write "Content-Type: #{content_type}\r\n"
    socket.write "Content-Length: #{body.bytesize}\r\n"
    socket.write "Connection: close\r\n"
    socket.write "\r\n"
    socket.write body
  end
end

def measure(name, base_url:, concurrency:, fetch_executor:)
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  result = Crawlscope::Crawl.new(
    base_url: base_url,
    sitemap_path: "#{base_url}/sitemap.xml",
    rules: [],
    schema_registry: Crawlscope::SchemaRegistry.default,
    concurrency: concurrency,
    fetch_executor: fetch_executor
  ).call

  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  [name, {seconds: elapsed.round(3), pages: result.pages.size, issues: result.issues.size}]
end

server = DelayedHttpServer.new(page_count: 24, delay_seconds: 0.08)
server.start

begin
  results = {}
  [
    measure("threaded_concurrency_1", base_url: server.base_url, concurrency: 1, fetch_executor: :threaded),
    measure("threaded_concurrency_8", base_url: server.base_url, concurrency: 8, fetch_executor: :threaded),
    measure("async_concurrency_8", base_url: server.base_url, concurrency: 8, fetch_executor: :async)
  ].each { |name, result| results[name] = result }

  sequential = results.fetch("threaded_concurrency_1").fetch(:seconds)
  threaded = results.fetch("threaded_concurrency_8").fetch(:seconds)
  async = results.fetch("async_concurrency_8").fetch(:seconds)

  abort "async benchmark failed: async was not meaningfully faster than sequential" unless async < sequential * 0.6
  abort "async benchmark failed: async was more than 2x slower than threaded" if async > threaded * 2.0

  puts JSON.pretty_generate(results)
ensure
  server.stop
end
