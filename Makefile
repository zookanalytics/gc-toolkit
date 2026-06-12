# Convenience targets for gc-toolkit pack maintenance.
#
# All targets are thin wrappers over shell scripts in scripts/. The pack
# itself ships as a Gas City pack and is not built; this Makefile exists
# for operator-driven maintenance commands.

.PHONY: help refresh-skills validate-skills

help:
	@printf 'Available targets:\n'
	@printf '  refresh-skills            Refresh every vendored skill in skills.lock.toml.\n'
	@printf '  refresh-skills SKILL=NAME Refresh just the named manifest entry.\n'
	@printf '  validate-skills           Validate skills.lock.toml against the on-disk tree.\n'

# SKILL is optional; when set, only that entry is refreshed.
SKILL ?=

refresh-skills:
ifeq ($(strip $(SKILL)),)
	./tools/refresh-skills.sh
else
	./tools/refresh-skills.sh --skill=$(SKILL)
endif

validate-skills:
	./tools/validate-skills.sh
