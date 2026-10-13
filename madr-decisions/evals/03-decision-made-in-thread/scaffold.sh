#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs/adr
cat > docs/adr/0007-rest-over-grpc.md <<'ADR'
---
status: "accepted"
date: 2024-11-18
decision-makers: Ana Mirek
consulted:
informed:
---

# REST over gRPC for service-to-service calls

## Context and Problem Statement

Services were calling each other over a mix of REST and an early gRPC experiment. Two transports
meant two sets of client code, two retry stories and two ways to be wrong about timeouts.

## Decision Drivers

* every engineer on the team could already read and debug an HTTP call
* no measured latency problem existed at the time

## Considered Options

* REST over HTTP/1.1 for all internal traffic
* gRPC for all internal traffic

## Decision Outcome

Chosen option: "REST over HTTP/1.1 for all internal traffic", because the team could debug it with
tools it already had and nothing in production was waiting on transport latency. Internal traffic
goes over REST and the gRPC experiment is retired.

### Consequences

* Good, because one transport, one client story, one retry policy
* Bad, because a latency-sensitive path later has no faster option inside this decision
ADR
