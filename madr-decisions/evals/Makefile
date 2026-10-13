# Eval suite for the record-decision supersede flow.
# Run from the repository root as `make -C evals <target>`.
#
#   make -C evals            what each target does and what it costs
#   make -C evals eval       the full suite, 8 cases x 2 arms x 3 runs
#   make -C evals fast       the four cheap, high-signal cases
#   make -C evals pilot      one run per case, for checking a grader change
#   make -C evals case CASE=04-rewrite-demanded
#
# JUDGE must stay at a sonnet-tier model or larger: the default judge is haiku and these rubrics
# turn on distinctions it misses. It must also never be the model the agent runs on, or it grades
# its own output.

JUDGE ?= sonnet
EXTRA ?=
RUN   := ./run.sh --judge-model $(JUDGE) $(EXTRA)

FAST_CASES := 0[4678]-*

.DEFAULT_GOAL := help

## help: list the targets, with what one pass costs
help:
	@echo "madr-decisions eval suite"
	@echo
	@echo "  make -C evals eval          full suite, runs: 3                  ~\$$17"
	@echo "  make -C evals fast          cases 04, 06, 07, 08 only            ~\$$6"
	@echo "  make -C evals pilot         every case, one run each             ~\$$6"
	@echo "  make -C evals case CASE=…   one case, one run                    ~\$$1"
	@echo "  make -C evals report        open the newest HTML report"
	@echo "  make -C evals clean         delete local results"
	@echo
	@echo "  The headline number is the Delta column: with-plugin minus without-plugin."
	@echo "  A score on its own says nothing — the question is whether the plugin changes anything."
	@echo
	@echo "  Reports stay local (--no-publish is built in). Open one with: make -C evals report"
	@echo
	@echo "  Variables:  JUDGE=$(JUDGE)   EXTRA=\"$(EXTRA)\""

## eval: the full suite at the runs each case declares (3)
eval:
	$(RUN)

## fast: the four cheapest cases, which also carry the strongest signal
fast:
	$(RUN) --case '$(FAST_CASES)'

## pilot: one run per case — for checking a grader change, not for a verdict
pilot:
	$(RUN) --runs 1

## case: a single case, one run. CASE=01-code-task-touches-adr
case:
	@test -n "$(CASE)" || { echo "set CASE=<dir name>, e.g. make -C evals case CASE=04-rewrite-demanded"; exit 1; }
	$(RUN) --runs 1 --case '$(CASE)'

## report: open the most recent HTML report
report:
	@r=$$(ls -dt results/*/report.html 2>/dev/null | head -1); \
	test -n "$$r" || { echo "no report yet — run make -C evals eval"; exit 1; }; \
	echo "$$r"; open "$$r"

## clean: remove local results
clean:
	rm -rf results

.PHONY: help eval fast pilot case report clean
