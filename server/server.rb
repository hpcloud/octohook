require 'sinatra'
require 'json'
require 'octokit'
require 'typhoeus'

require_relative 'lib/github_payload'
require_relative 'lib/git_repository'
require_relative 'lib/jenkins'

include GitHubPayload
include GitRepository
include JenkinsSupport

post '/payload/?' do
  return 403 unless valid_signature?
  handler = request.env.fetch('HTTP_X_GITHUB_EVENT', 'default').to_sym
  method(handler).call(JSON.parse request_body) if methods.include? handler
  204  # Acknowledge valid request (with or without handler), return no content.
end

get '/changes/?:head?/?:base?/?' do
  head = params.fetch 'head', repository.head.target.oid
  return 404 unless repository.exists? head

  base = params.fetch 'base', repository.lookup(head).parents.first.oid
  return 404 unless repository.exists? base

  JSON.dump changed_components(head, base)
end

get '/head/?' do
  JSON.dump repository.head.target.oid
end

def pull_request(payload)
  return 204 unless %w(opened synchronize).include? payload['action']
  head = payload['pull_request']['head']['sha']
  base = payload['pull_request']['base']['sha']
  jobs = Typhoeus::Hydra.new
  changed_components(head, base).each do |component|
    jobs.queue jenkins_job(component)
  end
  jobs.run
end
