# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "bundler/setup"
require "crawlscope"
require "json"
require "socket"

class MatrixHttpServer
  attr_reader :base_url

  def initialize(page_count:, delay_seconds:, link_targets: false)
    @page_count = page_count
    @delay_seconds = delay_seconds
    @link_targets = link_targets
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
    paths = @link_targets ? ["/seed"] : (1..@page_count).map { |index| "/pages/#{index}" }
    urls = paths.map { |path| "<url><loc>#{@base_url}#{path}</loc></url>" }.join

    %(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{urls}</urlset>)
  end

  def page_html(path)
    links = if @link_targets && path == "/seed"
      (1..@page_count).map { |index| %(<a href="/targets/#{index}">Target #{index}</a>) }.join
    else
      ""
    end

    <<~HTML
      <html>
        <head>
          <title>#{path}</title>
          <meta name="robots" content="noindex">
        </head>
        <body>
          <main><h1>#{path}</h1><p>#{path} benchmark page</p>#{links}</main>
        </body>
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

def measure(base_url:, concurrency:, fetch_executor:, rules:)
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  result = Crawlscope::Crawl.new(
    base_url: base_url,
    sitemap_path: "#{base_url}/sitemap.xml",
    rules: rules,
    schema_registry: Crawlscope::SchemaRegistry.default,
    concurrency: concurrency,
    fetch_executor: fetch_executor
  ).call

  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  {seconds: elapsed, pages: result.pages.size, issues: result.issues.size}
end

def median(values)
  sorted = values.sort
  sorted[sorted.length / 2]
end

def run_case(name:, page_count:, delay_seconds:, concurrency:, link_targets: false)
  server = MatrixHttpServer.new(page_count: page_count, delay_seconds: delay_seconds, link_targets: link_targets)
  server.start

  rules = link_targets ? [Crawlscope::Rules::Links.new] : []
  threaded = []
  async = []

  3.times do
    threaded << measure(base_url: server.base_url, concurrency: concurrency, fetch_executor: :threaded, rules: rules)
    async << measure(base_url: server.base_url, concurrency: concurrency, fetch_executor: :async, rules: rules)
  end

  threaded_seconds = median(threaded.map { |result| result.fetch(:seconds) })
  async_seconds = median(async.map { |result| result.fetch(:seconds) })

  {
    name: name,
    page_count: page_count,
    delay_seconds: delay_seconds,
    concurrency: concurrency,
    link_targets: link_targets,
    threaded_seconds: threaded_seconds.round(3),
    async_seconds: async_seconds.round(3),
    async_vs_threaded: (threaded_seconds / async_seconds).round(2),
    pages: async.first.fetch(:pages),
    issues: async.first.fetch(:issues)
  }
ensure
  server&.stop
end

cases = [
  {name: "direct_pages_c8", page_count: 48, delay_seconds: 0.02, concurrency: 8},
  {name: "direct_pages_c16", page_count: 48, delay_seconds: 0.02, concurrency: 16},
  {name: "slow_direct_pages_c8", page_count: 48, delay_seconds: 0.08, concurrency: 8},
  {name: "slow_direct_pages_c16", page_count: 48, delay_seconds: 0.08, concurrency: 16},
  {name: "link_targets_c8", page_count: 48, delay_seconds: 0.02, concurrency: 8, link_targets: true},
  {name: "slow_link_targets_c8", page_count: 48, delay_seconds: 0.08, concurrency: 8, link_targets: true}
]

puts JSON.pretty_generate(cases.map { |attributes| run_case(**attributes) })
