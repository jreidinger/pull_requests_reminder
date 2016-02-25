#! /usr/bin/env ruby

require "open-uri"
require "json"
require "ostruct"

def usage
<<-END
  #{$0} <github organization> [repo-name-1] [repo-name-2] ...  [repo-name-n]
  Tool to print report about pending pull request of given organization
END
end

def print_usage
  $stdout.puts usage
end

if ARGV.empty?
  print_usage
  exit 1
end

class Repository < OpenStruct
  def self.all(organization)
    result = []
    i = 1
    cont = true
    begin
      tmp = load_part(organization, i)
      if tmp.empty?
        cont = false
      else
        result.concat tmp
      end
      i += 1
    end while (cont)
    return result
  end

  def any_pull_requests?
    # approximate with issues as there is no quick check for pull request
    # used only for quick decision if we need to inspect it
    open_issues_count > 0
  end
private
  def self.load_part(organization, part)
    url = "https://api.github.com/orgs/#{organization}/repos?page=#{part}"
    open(url) do |f|
      repos = JSON.load(f.gets)
      return repos.map{ |r| Repository.new(r) }
    end
  end
end

class PullRequest < OpenStruct
  def self.all(repository)
    url = "https://api.github.com/repos/#{repository.full_name}/pulls"
    open(url) do |f|
      prs = JSON.load(f.gets)
      return prs.map{ |p| PullRequest.new(p) }
    end
  end

  def updated
    @updated ||= Time.parse(updated_at)
  end

  def pending_more_then?(days)
    pending_days > days
  end

  def pending_days
    ((Time.now - updated)/24/3600).floor
  end
end

organization = ARGV[0]
repos = Repository.all(organization)
if ARGV.size > 1
  reponames = ARGV[1, ARGV.size]
  repos.select! { |repo| reponames.include?(repo.name) }
end
repos.select!(&:any_pull_requests?)

result_message = ""
repos.each do |repo|
  begin
    pull_requests = PullRequest.all(repo)
  rescue OpenURI::HTTPError
    result_message << "\n\n ERROR: API query limit exceeded"
    break
  end
  pull_requests.select! do |pr|
    # do not count weekend in pending time
    days = (Time.now.monday? || Time.now.tuesday?) ? 5 : 3
    pr.pending_more_then? days
  end
  next if pull_requests.empty?

  msg = "\nPending requests in repository #{repo.name}:\n"
  pull_requests.reduce(msg) do |msg, pr|
    msg << "  - #{pr.title} (#{pr.pending_days} days)\n"
    msg << "    #{pr.html_url}\n\n"
  end

  #visual splitter
  result_message << msg
end

puts result_message
