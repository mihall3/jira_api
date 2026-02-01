#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'optparse'

class JiraClient
  BASE_URL = 'https://jira-eng-rtp1.cisco.com/jira'
  API_PATH = '/rest/api/2/search'

  def initialize
    @username = ENV.fetch('JIRA_USERNAME') do
      raise 'JIRA_USERNAME environment variable is not set'
    end
    @token = ENV.fetch('JIRA_TOKEN') do
      raise 'JIRA_TOKEN environment variable is not set'
    end
  end

  def search_issues(jql, max_results: 50, fields: %w[summary status assignee priority created updated])
    uri = URI.parse("#{BASE_URL}#{API_PATH}")
    uri.query = URI.encode_www_form(
      jql: jql,
      maxResults: max_results,
      fields: fields.join(',')
    )

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'

    response = make_request(uri, request)
    parse_response(response)
  end

  def find_issues_assigned_to(username)
    jql = "assignee = #{username} ORDER BY updated DESC"
    search_issues(jql)
  end

  def find_issues_by_label(label)
    jql = "labels = \"#{label}\" ORDER BY updated DESC"
    search_issues(jql)
  end

  def find_issues_by_labels(labels, match_all: false)
    operator = match_all ? ' AND ' : ' OR '
    conditions = labels.map { |l| "labels = \"#{l}\"" }.join(operator)
    jql = "(#{conditions}) ORDER BY updated DESC"
    search_issues(jql)
  end

  private

  def make_request(uri, request)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 30

    http.request(request)
  end

  def parse_response(response)
    case response.code.to_i
    when 200
      JSON.parse(response.body)
    when 401
      raise "Authentication failed. Check your JIRA_TOKEN."
    when 403
      raise "Access forbidden. You may not have permission to access this resource."
    when 404
      raise "Resource not found. Check the Jira URL."
    else
      raise "Request failed with status #{response.code}: #{response.body}"
    end
  end
end

def display_issues(result, title: nil)
  issues = result['issues'] || []
  total = result['total'] || 0

  puts "=" * 80
  puts title.nil? ? "Found #{total} issue(s)" : "Found #{total} issue(s) for: #{title}"
  puts "=" * 80
  puts

  if issues.empty?
    puts "No issues found."
    return
  end

  issues.each_with_index do |issue, index|
    key = issue['key']
    fields = issue['fields']
    summary = fields['summary']
    status = fields.dig('status', 'name') || 'Unknown'
    priority = fields.dig('priority', 'name') || 'None'
    updated = fields['updated']

    puts "#{index + 1}. [#{key}] #{summary}"
    puts "   Status: #{status} | Priority: #{priority}"
    puts "   Updated: #{updated}"
    puts "   URL: #{JiraClient::BASE_URL}/browse/#{key}"
    puts
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    options = {
      assignee: 'mihall3',
      label: nil,
      labels: nil,
      match_all: false
    }

    OptionParser.new do |opts|
      opts.on('--assignee USERNAME') { |v| options[:assignee] = v }
      opts.on('--label LABEL') { |v| options[:label] = v }
      opts.on('--labels LABEL1,LABEL2') { |v| options[:labels] = v.split(',').map(&:strip).reject(&:empty?) }
      opts.on('--match-all') { options[:match_all] = true }
    end.parse!(ARGV)

    client = JiraClient.new
    result = if options[:label]
               client.find_issues_by_label(options[:label])
             elsif options[:labels]&.any?
               client.find_issues_by_labels(options[:labels], match_all: options[:match_all])
             else
               client.find_issues_assigned_to(options[:assignee])
             end

    title = if options[:label]
              "label=#{options[:label]}"
            elsif options[:labels]&.any?
              mode = options[:match_all] ? 'all' : 'any'
              "labels(#{mode})=#{options[:labels].join(',')}"
            else
              "assignee=#{options[:assignee]}"
            end

    display_issues(result, title: title)
  rescue StandardError => e
    puts "Error: #{e.message}"
    exit 1
  end
end
