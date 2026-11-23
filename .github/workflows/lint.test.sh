#!/usr/bin/env bash
# lint.test.sh — guards lint.yml, the lint check on GitHub: the events that run
# it, the one job and its id, the draft gate that is the job's whole if:, the
# concurrency group the job holds, the platforms it lints for, and the version
# of golangci-lint it runs, which only .golangci-lint-version names.
#
# A draft pull request must not run the lint, and a push to main, a manual
# dispatch and the marking of a draft as ready must. Main's ruleset names a
# required check by its job's id, and a name: or a matrix on the job renames
# it, so the job is `lint` and sets neither. The city's merge counts no skipped
# result, so the draft gate is the job's whole if:: a condition of its own that
# skipped the job at a ready head would hold that pull request's merge. The job
# holds a concurrency group named for the workflow, the job and the ref, that
# cancels the run in progress, and the workflow holds none, for the reasons
# tests.test.sh gives for tests.yml.
#
# The job lints every package twice, for the reason lint.yml's header gives:
# for Linux, the platform of the ubuntu-latest runner, in a step whose env
# names no GOOS, and for macOS on arm64 in a step whose env names both. A GOOS
# set for the whole job or workflow would leave no run for the runner's
# platform.
#
# tools/lint.sh and this job lint with the same release because each reads it
# from .golangci-lint-version, so each golangci-lint the job builds reads the
# file, and the job names no release of its own, nor a query such as latest.
#
# Hermetic: reads lint.yml with Psych, the YAML parser Ruby ships, as
# action-pins.test.sh reads every workflow. Needs ruby.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF="$HERE/lint.yml"

[ -f "$WF" ] || { echo "lint.test.sh: cannot find lint.yml at $WF" >&2; exit 2; }
ruby -e 'require "psych"' 2>/dev/null \
    || { echo "lint.test.sh: needs ruby with Psych, its YAML parser, to read lint.yml" >&2; exit 2; }

# The check exits 0 when lint.yml holds every rule, 1 naming each rule it
# breaks, and 2 when it cannot read the file. Psych reads the bare key on as
# true, as YAML 1.1 does, so the events are under either key.
ruby - "$WF" <<'RUBY'
require 'psych'

failures = []
fail_with = ->(msg) { failures << msg }
begin
  doc = Psych.safe_load(File.read(ARGV[0]), aliases: false)
  raise 'its top level is not a mapping' unless doc.is_a?(Hash)
rescue StandardError, Psych::Exception => e
  warn "lint.test.sh: cannot read lint.yml: #{e.message}"
  exit 2
end

events = doc[true] || doc['on'] || {}
types = Array(events.dig('pull_request', 'types'))
%w[opened synchronize reopened ready_for_review].each do |t|
  fail_with.("pull_request types must include '#{t}'") unless types.include?(t)
end
fail_with.("pull_request must run for main") unless Array(events.dig('pull_request', 'branches')) == ['main']
fail_with.("a push to main must run the lint") unless Array(events.dig('push', 'branches')) == ['main']
fail_with.("a manual dispatch must run the lint") unless events.key?('workflow_dispatch')

fail_with.("the workflow must hold no concurrency group, each job holds its own") if doc.key?('concurrency')

jobs = doc['jobs'] || {}
fail_with.("lint.yml must have one job, lint, and has #{jobs.keys.inspect}") unless jobs.keys == ['lint']
job = jobs['lint'] || {}
%w[name strategy].each do |k|
  fail_with.("job lint must not set #{k}:, which renames the check main's ruleset requires") if job.key?(k)
end
gate = "github.event_name != 'pull_request' || github.event.pull_request.draft == false"
fail_with.("job lint's whole if: must be the draft gate, #{gate}, and is #{job['if'].inspect}") unless job['if'] == gate
group = '${{ github.workflow }}-lint-${{ github.ref }}'
conc = job['concurrency'].is_a?(Hash) ? job['concurrency'] : {}
fail_with.("job lint's concurrency group must be #{group}") unless conc['group'] == group
fail_with.("job lint's concurrency must cancel the run in progress") unless conc['cancel-in-progress'] == true

steps = Array(job['steps']).select { |s| s.is_a?(Hash) }
runs = steps.map { |s| s['run'].to_s }
pinned = runs.select { |r| r.include?('golangci-lint@$(cat .golangci-lint-version)') }
fail_with.("job lint must run golangci-lint at the release .golangci-lint-version names") if pinned.empty?
named = runs.join("\n").scan(/golangci-lint@(?!\$\(cat \.golangci-lint-version\))([^\s"']*)/).flatten
fail_with.("job lint names a release of its own, #{named.join(', ')}; it reads .golangci-lint-version") unless named.empty?

fail_with.("job lint must run on ubuntu-latest, the platform its run with no GOOS lints for, and runs on #{job['runs-on'].inspect}") unless job['runs-on'] == 'ubuntu-latest'
{ 'the workflow' => doc, 'job lint' => job }.each do |what, holder|
  env = holder['env'].is_a?(Hash) ? holder['env'] : {}
  fail_with.("#{what} must not set GOOS in its env, which every step would lint for") if env.key?('GOOS')
end
lints = steps.select { |s| s['run'].to_s.include?('golangci-lint') && s['run'].to_s.match?(%r{(^|\s)run\s+\./\.\.\.(\s|$)}) }
env_of = ->(s) { s['env'].is_a?(Hash) ? s['env'] : {} }
fail_with.("job lint must lint every package for Linux, in a step whose env names no GOOS") unless lints.any? { |s| !env_of.(s).key?('GOOS') }
fail_with.("job lint must lint every package for macOS on arm64, in a step whose env sets GOOS darwin and GOARCH arm64") unless lints.any? { |s| env_of.(s)['GOOS'] == 'darwin' && env_of.(s)['GOARCH'] == 'arm64' }

failures.each { |f| warn "lint.test.sh: FAIL — #{f}" }
exit 1 unless failures.empty?
puts 'lint.test.sh: OK'
RUBY
