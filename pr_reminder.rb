#! /usr/bin/env ruby
require 'open-uri'
require 'json'
require 'ostruct'

class GitHubAPI
  @@api_token_file = File.expand_path(File.dirname(__FILE__)) + "/api_token"
  @@api_token = nil

  def self.token
    if !@@api_token
      if ENV['GH_API_TOKEN']
        @@api_token = ENV['GH_API_TOKEN']
      elsif File.exists?(@@api_token_file)
        @@api_token = File.open(@@api_token_file).read.gsub("\n", "")
      end
    end

    @@api_token
  end

  def self.load_repos_in_page(organization, page)
    url = "https://api.github.com/orgs/#{organization}/repos?page=#{page}&per_page=100"

    if self.token
      url += "&access_token=#{self.token}"
    end

    open(url) do |json_file|
      JSON.load(json_file.gets).map { |repo_data| Repository.new(repo_data) }
    end
  end

  def self.pending_pull_requests(repository)
    pull_requests = []
    url = "https://api.github.com/repos/#{repository}/pulls"

    if self.token
      url += "?access_token=#{self.token}"
    end

    open(url) do |json_file|
      pull_requests = JSON.load(json_file.gets).map { |pr_data|
        PullRequest.new(pr_data)
      }
    end

    pull_requests.select do |pull_request|
      next false if pull_request.draft
      days = (Time.now.monday? || Time.now.tuesday?) ? 5 : 3 # do not count weekend in pending time
      pull_request.pending_days > days
    end
  end
end

# Represents an Organization in GitHub
class Organization
  attr_reader :name

  def initialize(name)
    @name = name
  end

  # Retrieves all the repositories of the organization (with PRs by default)
  def repositories_with_pull_requests(reponames = [])
    repositories = []
    page = 1
    loop do
      repositories_in_page = load_repos_in_page(page)
      break if repositories_in_page.empty?
      repositories.concat(repositories_in_page)
      page += 1
    end
    repositories.select! { |repo| reponames.include?(repo.name) } unless reponames.empty?
    repositories.select!(&:any_pull_requests?)
    repositories
  end

  private

  # Load repositories in the page from GitHub
  def load_repos_in_page(page)
    GitHubAPI.load_repos_in_page(name, page)
  end
end

# Represents a Repository in GitHub
class Repository < OpenStruct
  def pending_pull_requests
    GitHubAPI.pending_pull_requests(full_name)
  end

  def any_pull_requests?
    # approximate with issues as there is no quick check for pull request
    # used only for quick decision if we need to inspect it
    open_issues_count > 0
  end
end

# Represents a PullRequest in GitHub
class PullRequest < OpenStruct
  def updated
    @updated ||= Time.parse(updated_at)
  end

  def pending_days
    ((Time.now - updated) / 24 / 3600).floor
  end
end

def usage
  <<-END
    #{$PROGRAM_NAME} <github organization> [repo-name-1] [repo-name-2] ...  [repo-name-n]
    Tool to print report about pending pull request of given organization repositories.
    If a whitelist of repository names is passed then the tool will filter the results by them.
  END
end

if ARGV.empty?
  puts usage
  exit 1
end

organization, *reponames = ARGV
message = ""
begin
  Organization.new(organization).repositories_with_pull_requests(reponames).each do |repository|
    pending_pull_requests = repository.pending_pull_requests
    next if pending_pull_requests.empty?

    message << "\nPending requests in repository #{repository.name}:\n"
    pending_pull_requests.each do |pull_request|
      message << "  - "
      pull_request.labels.each { |label| message << "[#{label["name"]}] " }

      message << "#{pull_request.title} (#{pull_request.pending_days} days)\n"
      message << "    #{pull_request.html_url}\n\n"
    end
  end
rescue OpenURI::HTTPError
  message << "\n\n ERROR: API query limit exceeded"
end
puts message
