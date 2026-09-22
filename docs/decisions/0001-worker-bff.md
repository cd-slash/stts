# ADR 0001: Worker BFF and agent adapter boundary

- Status: Accepted
- Date: 2026-09-22

## Context

STTS needs a voice-first client for Hermes today while remaining capable of supporting other agent stacks. Browser clients must not receive upstream credentials. Speech behavior should be consistent regardless of the selected agent stack, and Hermes should retain its existing session and coordination responsibilities.

## Decision

Use an installable PWA that communicates only with a Cloudflare Worker BFF. The Worker authenticates users, proxies the shared speech service, and translates a narrow normalized application protocol through a Hermes adapter. Chief of Staff is the default coordinator.

Do not connect the browser directly to Hermes. Do not introduce a Durable Object or application database in the first milestone.

## Consequences

### Positive

- Credentials and upstream topology remain server-side.
- UI and future native clients share a stack-neutral contract.
- Additional agent stacks can be introduced as adapters.
- Hermes remains the authority for sessions and agent execution.
- Speech can evolve independently from Hermes.

### Negative

- The Worker must relay long-lived events and maintain protocol translation.
- Adapter compatibility must be tested against Hermes upgrades.
- The application needs explicit recovery semantics across two upstream services.

### Deferred

- Application-owned conversation persistence.
- Multi-device event fan-out.
- Shared/multi-user conversations.
- Native iOS and CarPlay delivery.
