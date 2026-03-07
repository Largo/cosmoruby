#!/usr/bin/env ruby
# frozen_string_literal: true

# CosmoRuby Cross-Platform Results Summariser
#
# Reads *-results.json files produced by platform_diagnostic.rb --json
# and produces a summary table in markdown, JSON, or CSV.
#
# Usage:
#   ruby summarise_results.rb [options] <result-files...>
#   ruby summarise_results.rb results/*.json
#   ruby summarise_results.rb --format csv linux-x86-results.json macos-arm64-results.json
#
# Options:
#   --format FORMAT   Output format: markdown, json, csv (default: markdown)
#   --expected FILE   JSON file with expected failure registry (optional)
#   --help            Show this help

require 'json'

class ResultsSummariser
  def initialize(format: 'markdown', expected_file: nil)
    @format = format
    @expected = expected_file ? JSON.parse(File.read(expected_file)) : nil
    @results = []
  end

  def load_file(path)
    data = JSON.parse(File.read(path))
    @results << data
  rescue JSON::ParserError => e
    $stderr.puts "Warning: skipping #{path} -- invalid JSON: #{e.message}"
  rescue Errno::ENOENT => e
    $stderr.puts "Warning: skipping #{path} -- #{e.message}"
  end

  def summarise
    case @format
    when 'markdown' then output_markdown
    when 'json'     then output_json
    when 'csv'      then output_csv
    else
      $stderr.puts "Error: unknown format '#{@format}'"
      exit 1
    end
  end

  private

  def platform_label(result)
    p = result['platform'] || {}
    os = p['os'] || 'unknown'
    arch = p['arch'] || 'unknown'
    "#{os}-#{arch}"
  end

  def output_markdown
    puts "| Platform | Result | Pass | Fail | Expected Fail | Warn | Skip | Time |"
    puts "|----------|--------|------|------|---------------|------|------|------|"

    @results.sort_by { |r| platform_label(r) }.each do |result|
      s = result['summary'] || {}
      label = platform_label(result)
      verdict = s['verdict'] || 'UNKNOWN'
      pass = s['pass'] || 0
      fail_count = s['fail'] || 0
      ef = s['expected_fail'] || 0
      warn_count = s['warn'] || 0
      skip = s['skip'] || 0
      duration = s['duration_seconds'] || 0

      # Annotate verdict
      display_verdict = verdict
      display_verdict = "#{verdict} (expected)" if fail_count == 0 && ef > 0

      puts "| #{label} | #{display_verdict} | #{pass} | #{fail_count} | #{ef} | #{warn_count} | #{skip} | #{duration}s |"
    end

    # Overall
    total_fail = @results.sum { |r| (r.dig('summary', 'fail') || 0) }
    puts
    if total_fail == 0
      puts "**Overall: PASS** (#{@results.size} platforms tested)"
    else
      puts "**Overall: FAIL** (#{total_fail} unexpected failures across #{@results.size} platforms)"
    end
  end

  def output_json
    summary = {
      generated_at: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S+00:00'),
      platform_count: @results.size,
      platforms: @results.map { |r|
        s = r['summary'] || {}
        {
          platform: platform_label(r),
          verdict: s['verdict'],
          pass: s['pass'],
          fail: s['fail'],
          expected_fail: s['expected_fail'],
          warn: s['warn'],
          skip: s['skip'],
          duration_seconds: s['duration_seconds']
        }
      },
      overall: {
        total_failures: @results.sum { |r| (r.dig('summary', 'fail') || 0) },
        verdict: @results.all? { |r| (r.dig('summary', 'fail') || 0) == 0 } ? 'PASS' : 'FAIL'
      }
    }
    puts JSON.pretty_generate(summary)
  end

  def output_csv
    puts "platform,verdict,pass,fail,expected_fail,warn,skip,duration_seconds"
    @results.sort_by { |r| platform_label(r) }.each do |result|
      s = result['summary'] || {}
      label = platform_label(result)
      fields = [
        label,
        s['verdict'] || 'UNKNOWN',
        s['pass'] || 0,
        s['fail'] || 0,
        s['expected_fail'] || 0,
        s['warn'] || 0,
        s['skip'] || 0,
        s['duration_seconds'] || 0
      ]
      puts fields.join(',')
    end
  end
end

# ── CLI ───────────────────────────────────────────────────────────────

if __FILE__ == $0
  format = 'markdown'
  expected_file = nil
  files = []

  i = 0
  while i < ARGV.length
    case ARGV[i]
    when '--format'
      i += 1
      format = ARGV[i]
    when '--expected'
      i += 1
      expected_file = ARGV[i]
    when '--help', '-h'
      puts <<~HELP
        CosmoRuby Cross-Platform Results Summariser

        Usage: ruby summarise_results.rb [options] <result-files...>

        Options:
          --format FORMAT   Output format: markdown, json, csv (default: markdown)
          --expected FILE   JSON file with expected failure registry
          --help            Show this help

        Examples:
          ruby summarise_results.rb results/*.json
          ruby summarise_results.rb --format csv linux-x86.json macos-arm64.json
          ruby summarise_results.rb --format json --expected expected.json *.json
      HELP
      exit 0
    else
      files << ARGV[i]
    end
    i += 1
  end

  if files.empty?
    $stderr.puts "Error: no result files specified"
    $stderr.puts "Usage: ruby summarise_results.rb [options] <result-files...>"
    exit 1
  end

  summariser = ResultsSummariser.new(format: format, expected_file: expected_file)
  files.each { |f| summariser.load_file(f) }
  summariser.summarise
end
