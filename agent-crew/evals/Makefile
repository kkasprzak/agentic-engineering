# Eval suite for how a coordinator takes a "deliver" request.
# Run from the repository root as `make -C agent-crew/evals <target>`.
#
#   make -C agent-crew/evals            what each target does
#   make -C agent-crew/evals eval       the full suite, 4 cases x 2 arms x 3 runs
#   make -C agent-crew/evals pilot      one run per case, for checking a grader change
#   make -C agent-crew/evals case CASE=01-deliver-item
#
# JUDGE must never be the model the agent runs on, or it grades its own output.

JUDGE ?= sonnet
EXTRA ?=
RUN   := ./run.sh --judge-model $(JUDGE) $(EXTRA)

.DEFAULT_GOAL := help

## help: list the targets
help:
	@echo "agent-crew eval suite"
	@echo
	@echo "  make -C agent-crew/evals eval          full suite, runs: 3"
	@echo "  make -C agent-crew/evals pilot         every case, one run each"
	@echo "  make -C agent-crew/evals case CASE=…   one case, one run"
	@echo "  make -C agent-crew/evals report        open the newest HTML report"
	@echo "  make -C agent-crew/evals clean         delete local results"
	@echo
	@echo "  The headline number is the Delta column: with-plugin minus without-plugin."
	@echo "  Reports stay local (--no-publish is built in)."
	@echo
	@echo "  Variables:  JUDGE=$(JUDGE)   EXTRA=\"$(EXTRA)\""

## eval: the full suite at the runs each case declares (3)
eval:
	$(RUN)

## pilot: one run per case — for checking a grader change, not for a verdict
pilot:
	$(RUN) --runs 1

## case: a single case, one run. CASE=01-deliver-item
case:
	@test -n "$(CASE)" || { echo "set CASE=<dir name>, e.g. make -C agent-crew/evals case CASE=01-deliver-item"; exit 1; }
	$(RUN) --runs 1 --case '$(CASE)'

## report: open the most recent HTML report
report:
	@r=$$(ls -dt results/*/report.html 2>/dev/null | head -1); \
	test -n "$$r" || { echo "no report yet — run make -C agent-crew/evals eval"; exit 1; }; \
	echo "$$r"; open "$$r"

## clean: remove local results
clean:
	rm -rf results

.PHONY: help eval pilot case report clean
