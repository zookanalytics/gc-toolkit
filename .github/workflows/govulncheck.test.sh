#!/usr/bin/env bash
# govulncheck.test.sh — guards govulncheck.yml, the scan for known
# vulnerabilities on GitHub: the events that run it, the one job and its id,
# the draft gate that is the job's whole if:, the concurrency group the job
# holds, and each part of the scan whose change would leave the check green
# while it scans less than it should.
#
# The events, the job's id, its if: and its concurrency group follow tests.yml's
# jobs, for the reasons tests.test.sh gives. Main's ruleset names a required
# check by its job's id, and a name: or a matrix renames it, so the job is
# `govulncheck` and sets neither.
#
# The scan's parts, for the reasons govulncheck.yml's comments give: the job
# runs on macOS; setup-go takes the Go release from go.mod and names none of its
# own; and govulncheck is installed at a release the workflow names. The scan
# runs over ./... from the repository root, and no flag picks its output, its
# level or its mode. govulncheck exits 3 on a finding only in text output and
# only at the level it scans (TextHandler.Flush in golang.org/x/vuln's
# internal/scan/text.go), so -format or -json would pass whatever it found, and
# -scan module would fail on a vulnerability no release fixes in a module the
# code only requires. Neither the job nor a step
# continues on error, and the scan's line runs nothing after it, so the scan's
# exit is the check's.
#
# Hermetic: reads govulncheck.yml with Psych, the YAML parser Ruby ships, as
# action-pins.test.sh reads every workflow. Needs ruby.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../tools/test-floor.sh" || exit 2
WF="$HERE/govulncheck.yml"

[ -f "$WF" ] || { echo "govulncheck.test.sh: cannot find govulncheck.yml at $WF" >&2; exit 2; }
ruby -e 'require "psych"' 2>/dev/null \
    || { echo "govulncheck.test.sh: needs ruby with Psych, its YAML parser, to read govulncheck.yml" >&2; exit 2; }

# The check exits 0 when govulncheck.yml holds every rule, 1 naming each rule it
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
  warn "govulncheck.test.sh: cannot read govulncheck.yml: #{e.message}"
  exit 2
end
hash = ->(v) { v.is_a?(Hash) ? v : {} }

events = hash.(doc[true] || doc['on'])
types = Array(hash.(events['pull_request'])['types'])
%w[opened synchronize reopened ready_for_review].each do |t|
  fail_with.("pull_request types must include '#{t}'") unless types.include?(t)
end
fail_with.('pull_request must run for main') unless Array(hash.(events['pull_request'])['branches']) == ['main']
fail_with.('a push to main must run the scan') unless Array(hash.(events['push'])['branches']) == ['main']
fail_with.('a manual dispatch must run the scan') unless events.key?('workflow_dispatch')

fail_with.('the workflow must hold no concurrency group, each job holds its own') if doc.key?('concurrency')

jobs = hash.(doc['jobs'])
fail_with.("govulncheck.yml must have one job, govulncheck, and has #{jobs.keys.inspect}") unless jobs.keys == ['govulncheck']
job = hash.(jobs['govulncheck'])
%w[name strategy].each do |k|
  fail_with.("job govulncheck must not set #{k}:, which renames its check") if job.key?(k)
end
gate = "github.event_name != 'pull_request' || github.event.pull_request.draft == false"
fail_with.("job govulncheck's whole if: must be the draft gate, #{gate}, and is #{job['if'].inspect}") unless job['if'] == gate
group = '${{ github.workflow }}-govulncheck-${{ github.ref }}'
conc = hash.(job['concurrency'])
fail_with.("job govulncheck's concurrency group must be #{group}") unless conc['group'] == group
fail_with.("job govulncheck's concurrency must cancel the run in progress") unless conc['cancel-in-progress'] == true

fail_with.("job govulncheck must run on a macOS runner, and runs on #{job['runs-on'].inspect}") \
  unless job['runs-on'].is_a?(String) && job['runs-on'].start_with?('macos-')

steps = Array(job['steps']).select { |s| s.is_a?(Hash) }
fail_with.('job govulncheck must set no continue-on-error') if job.key?('continue-on-error')
steps.each_with_index do |s, i|
  fail_with.("step #{i + 1} of job govulncheck must set no continue-on-error") if s.key?('continue-on-error')
end

setup = steps.select { |s| s['uses'].to_s.start_with?('actions/setup-go@') }
fail_with.("job govulncheck must set up Go once, with actions/setup-go, and does #{setup.size} times") unless setup.size == 1
with = hash.(setup.first && setup.first['with'])
fail_with.('setup-go must take the Go release from go.mod, as go-version-file: go.mod') unless with['go-version-file'] == 'go.mod'
fail_with.("setup-go must name no go-version, which wins over go.mod's") if with.key?('go-version')

env_of = ->(s, name) { hash.(s['env'])[name] || hash.(job['env'])[name] || hash.(doc['env'])[name] }

installs = steps.select { |s| s['run'].to_s.include?('golang.org/x/vuln/cmd/govulncheck@') }
fail_with.('job govulncheck must install govulncheck with go install') if installs.empty?
installs.each do |s|
  s['run'].to_s.scan(%r{golang\.org/x/vuln/cmd/govulncheck@([^\s"']+)}).flatten.each do |ref|
    name = ref[/\A\$\{?(\w+)\}?\z/, 1]
    release = name ? env_of.(s, name).to_s : ref
    fail_with.("govulncheck must be installed at a release such as v1.10.0, and is installed at #{ref} (#{release.inspect})") \
      unless release.match?(/\Av\d+\.\d+\.\d+\z/)
  end
end

# A scan is a line whose command, after any VAR=value words, is the govulncheck
# binary; its arguments are the words after that.
scans = steps.flat_map do |s|
  s['run'].to_s.each_line.map do |line|
    words = line.split
    words.shift while words.first.to_s.match?(/\A\w+=/)
    [s, line.strip, words.drop(1)] if words.first.to_s.delete(%q("')).match?(%r{(\A|/)govulncheck\z})
  end.compact
end
fail_with.('job govulncheck must run the govulncheck binary it installs') if scans.empty?
scans.each do |s, line, args|
  fail_with.("the scan must run over ./..., and its line is: #{line}") unless args.include?('./...')
  picked = args.grep(/\A--?(format|json|scan|mode|C)(=|\z)/).map { |a| a[/\A--?\w+/] }
  fail_with.("the scan must set no #{picked.join(', ')}, and its line is: #{line}") unless picked.empty?
  rest = args.grep(/\A(\|\||&&|;|\||&)\z/)
  fail_with.("the scan's line must run nothing after it, and its line is: #{line}") unless rest.empty?
end

failures.each { |f| warn "govulncheck.test.sh: FAIL — #{f}" }
exit 1 unless failures.empty?
puts 'govulncheck.test.sh: OK'
RUBY
