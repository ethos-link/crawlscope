# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "bundler/setup"
require "crawlscope"
require "json"
require "socket"

class DelayedSitemapServer
  attr_reader :base_url

  def initialize(child_count:, delay_seconds:)
    @child_count = child_count
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
      write_response(socket, sitemap_index, content_type: "application/xml")
    else
      sleep @delay_seconds
      write_response(socket, child_sitemap(path), content_type: "application/xml")
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

  def sitemap_index
    children = (1..@child_count).map do |index|
      "<sitemap><loc>#{@base_url}/sitemaps/#{index}.xml</loc></sitemap>"
    end.join

    %(<?xml version="1.0" encoding="UTF-8"?><sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{children}</sitemapindex>)
  end

  def child_sitemap(path)
    index = File.basename(path, ".xml")

    %(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>#{@base_url}/pages/#{index}</loc></url></urlset>)
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

  urls = Crawlscope::Sitemap.new(
    path: "#{base_url}/sitemap.xml",
    concurrency: concurrency,
    fetch_executor: fetch_executor,
    timeout_seconds: 5
  ).urls(base_url: base_url)

  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  [name, {seconds: elapsed.round(3), urls: urls.size}]
end

server = DelayedSitemapServer.new(child_count: 24, delay_seconds: 0.08)
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

  abort "sitemap benchmark failed: threaded parallelism was not at least 2x faster" unless threaded < sequential * 0.5
  abort "sitemap benchmark failed: async parallelism was not at least 2x faster" unless async < sequential * 0.5

  puts JSON.pretty_generate(results)
ensure
  server.stop
end
