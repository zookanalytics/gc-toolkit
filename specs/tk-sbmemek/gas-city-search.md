---
name: Gas City search for the demo toolchain's Vercel-key report
description: The search the arch check asks for before check-demo-toolchain reports VERCEL_AUTOMATION_BYPASS_SECRET. What Gas City, the packs it bundles and publishes, and bd ship for finding a key that the secrets file holds and sessions lack, read at named upstream commits, and why the pack reports the key from its own doctor check. Read it when checking whether the pack still needs that report, or whether Gas City now reports such a key itself.
---

# Gas City search for the demo toolchain's Vercel-key report

`doctor/check-demo-toolchain` reports whether `VERCEL_AUTOMATION_BYPASS_SECRET`
reaches the session it runs in, and warns when `${GC_HOME}/secrets.env` holds
the key and the session does not. The arch check asks what Gas City already
ships for that ([review-arch.md](../../docs/review-arch.md#the-checks), check
1). Gas City carries a key from the secrets file only through its gates, and it
drops any other key without saying so. No check in `gc doctor`, in the packs
Gas City bundles or in the packs it publishes reports that drop. So the pack
reports the key itself, from the doctor check it already has. A pack doctor
check is how Gas City lets a pack add a readiness check of its own.

## The surface and the need

`check-demo-toolchain` is a pack doctor check. It already reported Node,
ffmpeg, `OPENAI_API_KEY` and `gh`, and this change has it report the Vercel key
in three states:

- In the session, the key is named on the OK line.
- In the secrets file but not the session, the key is a warning. The warning
  names the `GC_SUPERVISOR_ENV` opt-in when the session's own list does not
  name the key, and a fresh `gc supervisor install` when it does.
- Set nowhere, the key is a note and not an item.

The change adds no check, no command and no pack noun. Its other files are the
check's test, the demo-capture skill and the docs that describe the check, none
of which is operational surface
([review-arch.md](../../docs/review-arch.md#when-the-lens-applies)).

The need is a diagnosis. A person who adds the key to the secrets file learns
from `gc doctor` whether sessions receive it and, when they do not, what would
carry it there. The key is Vercel's Protection Bypass for Automation key, which
lets automation past a deployment's Vercel sign-in. The report says where the
key is and nothing about what a capture does with it.

## Where the search looked

Each was read on 2026-10-26:

- Gas City at main `f78779e41522`, the commit the arch review read: its
  documentation, the checks `gc doctor` registers, the packs it bundles, and
  its source. The source was searched case-insensitively for `secrets.env`,
  `GC_SUPERVISOR_ENV` and Vercel, and each hit outside the tests was read, as
  was every environment read in a file that builds a doctor check result and
  every read of a variable named as a key, token, secret or password.
- Every pack Gas City publishes, at `dac12a4a802c`. Each pack's doctor checks
  were read, each pack was searched case-insensitively for `secrets.env`,
  `GC_SUPERVISOR_ENV`, `supervisor install`, `workspace.env`, `passthrough` and
  Vercel, and each hit was read. Gas City bundles `gastown` and `gascity` from
  the packs at `66c672b5ed00`, where their doctor checks are the same and none
  of these terms matches.
- bd at `002e33aee117`, searched case-insensitively for `secrets.env`,
  `GC_SUPERVISOR_ENV` and Vercel. Nothing matched.

Each passage cited below from Gas City's documentation was also found on the
live site at docs.gascity.com.

## What Gas City ships

**The secrets file reaches the supervisor only through a gate.** The
[Troubleshooting](https://docs.gascity.com/getting-started/troubleshooting#provider-credentials-dropped-when-the-supervisor-starts)
page's section "Provider Credentials Dropped When the Supervisor Starts" says
that each time `gc` writes the supervisor's service file, it merges
`${GC_HOME}/secrets.env` into the supervisor's environment. It merges only the
keys already eligible: provider credentials, a short built-in list, and keys
opted in through `GC_SUPERVISOR_ENV`, and "any other key in the file is
ignored". In the `gc` command's source, `buildSupervisorServiceData` takes the
service env from `supervisorServiceExtraEnv`. That function skips a file entry
unless `shouldPersistSupervisorEnv` admits it, through the
`supervisorServiceEnvKeys` allowlist or a provider credential, or the opt-in
list names it. A provider credential is a key that package `processenv`'s
`IsProviderCredentialEnv` accepts: a key that starts with one of the
`providerCredentialEnvPrefixes`, such as `OPENAI_`, or one of the exact names
in `providerCredentialEnvKeys`, such as `AWS_ACCESS_KEY_ID`.
`supervisorSecretsEnvFileEntries` reports an unreadable file and each malformed
line on stderr. Nothing reports a key the gate skips.
`VERCEL_AUTOMATION_BYPASS_SECRET` is not a provider credential and is not on the
allowlist, and nothing in Gas City names Vercel.

**A session receives such a key through the same list, or through an `env`
table in the city's config.** The same page's section
["A Custom Environment Variable Doesn't Reach Agent Sessions"](https://docs.gascity.com/getting-started/troubleshooting#a-custom-environment-variable-doesn%E2%80%99t-reach-agent-sessions)
says that `passthroughEnv` forwards a variable into a session only when it is
`GC_`-prefixed, in a small fixed provider, locale and XDG set, or named in
`GC_SUPERVISOR_ENV`. "Everything else is dropped silently, by design." The
page's fix names the variable in that list, with the list naming itself so
that it survives a restart, then runs `gc supervisor install` and restarts the
supervisor. Sessions already running keep their old environment. In the
source, the fixed set is package `processenv`'s
`ProviderProcessPassthroughEnv`, which also forwards provider credentials. The
page also offers `[workspace.env]` in `city.toml`, one of the `env` tables a
session's environment merges, as are a provider's and an agent's
(`resolveTemplate` in the `gc` command). The `$VAR` form of each expands
against the supervisor's own environment (package `processenv`,
`ExpandSessionEnvValue`), so a key that only the secrets file holds must clear
the install's gate first. The literal form writes the value into the config.
For a key like this one, the opt-in is the one route that carries it from the
secrets file into the supervisor and on into its sessions.

**`gc doctor` reports neither drop.** None of the checks `gc doctor` registers
at `f78779e41522` reads the secrets file or `GC_SUPERVISOR_ENV`. Its checks
read the environment to configure themselves, such as which store, Dolt log or
archive repository a check inspects, and `provider-catalog-local-readiness`
also reads provider keys there, as below. The checks nearest the need cover
other things:

- `pack-credentials` (package `doctor`, `PackCredentialsCheck`) loads the git
  credential rules for remote pack imports and matches them against the city's
  imports.
- `service-secrets-perms` (`ServiceSecretsPermsCheck`) audits the file modes
  under each workspace service's `secrets` directory.
- `supervisor-binary`, `supervisor-unit-ownership` and `supervisor-http-api`
  check the running supervisor's build, its systemd unit and its API.
- `provider-catalog-local-readiness` probes the provider CLIs installed on the
  host, such as whether `claude` reports a first-party sign-in, and warns when
  a ready one is missing from the city's `[providers]`. Its probe (package
  `api`, `ProbeProviders`) reads provider keys from `gc doctor`'s own
  environment: an installed MiMo Code is ready when `XIAOMI_API_KEY` is set or
  its own credential file holds a login, and ZCode needs `ZCODE_API_KEY`. A
  provider without a credential is not ready and goes unreported, so the check
  names no missing key, and it never reads the secrets file.
- `gate-sandbox-reads` (`gateSandboxReadCheck` in the `gc` command) rebuilds
  the environment a convergence gate runs in and checks that a bead read
  succeeds there. It probes a gate's environment, not a session's, and
  reports no key.

Outside `gc doctor`, the
[CLI Reference](https://docs.gascity.com/reference/cli#gc-supervisor-install)
gives `gc supervisor install` one flag, `--force`. `gc supervisor status` says
whether the supervisor runs and what supervises it. `gc config explain` and
`gc config show` print the resolved config, which holds `[workspace.env]` but
not the service env. Gas City reads the secrets file only while it builds the
service file, and no command reports what the file holds or what an install
would carry.

**A pack adds a readiness check through a pack doctor check.** The
[Gas City Pack Specification](https://docs.gascity.com/reference/specs/pack-spec#1-2-11-doctor-directory),
section 1.2.11 "Doctor Directory", defines a pack check as a `doctor/<name>/`
directory whose check script is `run.sh` unless its optional `doctor.toml`
names another. The Troubleshooting
page's section
["Add City-Local Doctor Checks"](https://docs.gascity.com/getting-started/troubleshooting#add-city-local-doctor-checks)
gives the protocol a check script follows: exit 0 for OK, 1 for a warning and 2
or higher for an error, with the first stdout line as the message and the rest
as details.

The packs Gas City bundles
([Builtin Packs](https://docs.gascity.com/reference/system-packs)) check tools
and files. `core`'s `check-binaries` requires `jq` and reports whether `gh` is
present. `bd`'s `check-bd` checks that bd is installed at a supported version.
`dolt`'s `check-dolt` checks Dolt, `flock` and `lsof`. `gastown`'s
`check-scripts` checks that the pack's scripts are executable. The `gascity`
pack has no check.

Of the packs Gas City publishes, `contributing-to-gascity`, `discord`, `github`
and `slack-full` check that tools such as bd, gc, gh, git, jq, openssl and
python are available. `discord` also checks for a legacy pack's state, and
`slack-full` checks its own built binaries, its public ingress and its
environment. `slack-full`'s `env` check is the one that reports keys. The four
keys its Slack adapter requires pass when they are set in the environment or
present in the adapter's own env file under the XDG config directory, and the
check errors otherwise. A key in that file passes on the file alone, because
the adapter's launch script sources the file before it starts the adapter. The
check never reads Gas City's secrets file or `GC_SUPERVISOR_ENV`.

No pack names `secrets.env`, `GC_SUPERVISOR_ENV` or `gc supervisor install`,
and none names Vercel's bypass key. Vercel appears only in skill and prompt
text. `gstack`'s deploy skill detects a Vercel project, reads a preview
deploy's URL from a pull request's checks and waits out an automatic deploy.
The other mentions, in `bmad`, `compound-engineering` and `gstack`'s other
skills, are examples in prose. The `github` pack reads `[workspace.env]` in
`workspace_env_value`, which takes its public URL overrides, and in
`city_workspace_env`, which takes its `GITHUB_INTAKE_` settings, such as the
App identity and its resolver, and passes them into the environment of the
resolver it runs. Each takes a setting from the process environment first and
from `city.toml` second. Neither is a doctor check, and neither reads Gas
City's secrets file.

## What the change does with it

The report composes Gas City's mechanisms. It is an item of
`check-demo-toolchain`, a pack doctor check, so `gc doctor` runs it beside its
own checks under the protocol above. Its fix is the opt-in the Troubleshooting
page documents, with the list naming itself. It adds no check and no pack noun,
so it needs no warrant
([review-arch.md](../../docs/review-arch.md#the-checks), check 2).

Two of Gas City's rules are mirrored in the check, because no `gc` command
answers them for a caller. The file probe looks for an assignment of the key
with a non-empty value, in the forms the Troubleshooting page documents: an
optional `export ` and optional quotes. The opt-in list is split on commas,
semicolons and whitespace, as `supervisorServiceExplicitEnvKeys` splits it.

The capability Gas City lacks is a report of a secrets-file key its gates skip.
Neither `gc supervisor install` nor `gc doctor` gives one. The Troubleshooting
page says the file's other keys are ignored and that a session's other
variables are dropped silently. A report of every skipped key belongs in Gas
City, which owns the gates and reads the file. The pack's check names one key,
as `slack-full`'s `env` check names only its adapter's keys.

This answer changes if Gas City starts reporting a secrets-file key its gates
skip, in `gc doctor` or at `gc supervisor install`. The report's file-only
warning should then defer to Gas City's report. At `f78779e41522` neither
reports one.
