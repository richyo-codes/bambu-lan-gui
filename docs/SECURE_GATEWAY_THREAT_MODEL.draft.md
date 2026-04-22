# Secure Gateway Threat Model

## Purpose

This document outlines a draft threat model and architecture concept for a local security gateway that sits between BoomPrint clients and a Bambu printer running in Developer Mode.

The goal is twofold:

1. Improve practical local security for users who want LAN-first workflows.
2. Provide a proof of concept showing that strong local-only security is technically achievable without requiring vendor cloud mediation such as Bambu Connect.

This is intended to be constructive, technical, and implementation-oriented.

## Problem Statement

Bambu Developer Mode exposes useful LAN functionality, but it also weakens the default security posture compared to a locked-down consumer mode. In practice:

- the printer may expose services that are reachable from the LAN
- access secrets may need to be copied to multiple user devices
- camera and control traffic can be consumed directly by clients
- there is no vendor-provided local policy layer for authentication, authorization, auditing, or access scoping

Today, users are often forced into one of two unsatisfying options:

- depend on vendor cloud workflows
- or accept weaker direct-LAN security in Developer Mode

The gateway concept is a proof of concept for a better third option:

- strong local-only access
- secrets contained on a dedicated gateway
- policy enforcement between users and printer
- no requirement for vendor cloud

## Core Idea

Introduce a dedicated local gateway that becomes the only trusted path between user devices and the printer.

Instead of every client device connecting directly to the printer, the architecture becomes:

- clients authenticate to gateway
- gateway authenticates to printer
- gateway stores printer secrets
- gateway exposes only approved, audited, policy-controlled access

This restores a missing trust boundary that Developer Mode otherwise removes.

## High-Level Goals

- keep printer credentials off end-user devices
- reduce direct exposure of printer services on the LAN
- make camera, telemetry, and control flows auditable
- enforce least privilege locally
- support local-first operation without vendor cloud dependency
- demonstrate a viable security architecture that a vendor could support officially

## Non-Goals

This gateway is not intended to:

- guarantee perfect security while Developer Mode is enabled
- defend against malicious printer firmware
- protect against a fully compromised gateway host
- replace network segmentation best practices
- serve as a transparent layer-2 network bridge in the first implementation

The gateway reduces risk; it does not eliminate it.

## Assets To Protect

- printer LAN access code
- printer IP and service discovery details
- RTSP/RTSPS camera URLs and credentials
- print submission capability
- control command capability
- printer telemetry and operational context
- local user trust and authorization boundaries

## Threat Actors

- other devices on the same LAN
- guests or partially trusted users on the local network
- malware running on a user workstation or phone
- a compromised or misconfigured client app instance
- accidental operator mistakes
- future firmware changes that weaken or alter LAN behavior

## Threats

### Credential Leakage

Without a gateway, printer access details may be copied to multiple phones, desktops, laptops, or scripts. A compromised client can expose:

- printer LAN access code
- camera credentials
- internal printer IP and service endpoints

### Unauthorized Viewing

If camera URLs or credentials leak, users on the LAN may be able to watch printer streams without explicit approval.

### Unauthorized Control

Direct access to MQTT or FTP/FTPS can enable:

- pause
- stop
- print submission
- job manipulation
- light or other control actions

### Broad Lateral Exposure

If the printer is directly reachable from the user LAN, every device on that network becomes part of the printer’s effective attack surface.

### Unsafe Command Usage

Some commands may be valid but operationally risky. Without policy or role boundaries, all clients can potentially do too much.

### Vendor Security Gaps In Local Mode

Developer Mode may expose useful capability without supplying:

- local auth tokens
- scoped permissions
- audit logs
- client pairing
- local access control lists

This gateway is intended to demonstrate that these controls are feasible locally.

## Security Principles

- local-first by default
- least privilege
- deny by default for dangerous operations
- keep secrets only on the gateway
- explicit trust boundaries
- auditability for control actions
- avoid raw transparent exposure of printer services

## Trust Boundaries

### Clients

Client devices should trust the gateway, not the printer directly.

They should not require:

- printer access code
- raw RTSP credentials
- direct knowledge of internal printer endpoints

### Gateway

The gateway is the local security controller. It is responsible for:

- storing printer secrets
- authenticating clients
- authorizing actions
- auditing events
- mediating printer protocol traffic

### Printer

The printer remains a downstream protected asset. It should ideally be reachable only by the gateway.

## Embedded Appliance Concept

The most compelling long-term deployment is a low-power dedicated edge device that becomes the only path to the printer.

### Desired Topology

- printer-facing network:
  - isolated connection between printer and gateway
  - ideally Wi-Fi Direct, private AP, or isolated subnet
- user-facing network:
  - normal LAN or Wi-Fi for phones, desktops, and tablets
- printer reachable only through gateway

This is stronger than a simple app-layer proxy running on a normal workstation because it also restores network isolation.

### Appliance Modes

#### Mode 1: Application-Layer Gateway Only

- gateway and printer both live on normal LAN
- clients talk to gateway API instead of printer directly
- easiest proof of concept

#### Mode 2: Preferred Access Path

- gateway stores all secrets
- clients only use gateway
- printer may still technically be reachable directly, but the intended path is the gateway

#### Mode 3: Isolated Printer Network

- gateway has one printer-facing interface and one user-facing interface
- printer lives on isolated Wi-Fi, AP, VLAN, or dedicated subnet
- user LAN cannot reach printer directly

#### Mode 4: Full Single-Path Security Appliance

- gateway is the only practical network path to the printer
- all camera, telemetry, and control access is mediated
- clients cannot directly reach printer services

This is the strongest version of the concept.

## Why This Matters

This project is not intended to replace vendor security engineering. It is intended to demonstrate that:

- local auth can be layered cleanly
- scoped access can be local
- audit logs can be local
- secret isolation can be local
- safer LAN-only workflows are feasible without mandatory vendor cloud dependency

That proof of concept can help create constructive public pressure for better vendor LAN support.

Users should not have to choose between:

- vendor cloud lock-in
- or weaker local security in Developer Mode

A local security gateway demonstrates that there is another viable path.

## Proposed Gateway Responsibilities

- store printer access secrets securely
- authenticate local clients
- issue local tokens or paired device credentials
- proxy or relay selected MQTT, FTP/FTPS, and stream operations
- sanitize protocol quirks and firmware differences
- enforce policy and command restrictions
- log actions and operator attribution
- optionally broker camera access instead of exposing raw stream credentials

## Media Path Options

### Option 1: Direct Camera, Proxied Control

- gateway proxies control traffic only
- clients still use direct RTSP/RTSPS

Pros:
- simplest
- lowest bandwidth and CPU cost

Cons:
- camera credentials may still leak to clients
- weaker isolation story

### Option 2: Auth-Brokered Stream Access

- gateway exposes controlled stream access
- gateway may mint temporary access URLs or broker access decisions

Pros:
- stronger secret isolation
- better balance of complexity and security

Cons:
- more implementation work

### Option 3: Full Stream Relay

- gateway fully relays video traffic

Pros:
- strongest control and visibility

Cons:
- highest bandwidth and CPU cost
- likely too heavy for first proof of concept

Preferred direction:

- start with Option 1 or Option 2
- avoid full video relay for the first implementation

## Why An Application-Layer Gateway First

The first implementation should avoid transparent bridging and focus on an application-layer security gateway.

Reasons:

- easier to audit
- easier to reason about policy
- less risk of accidental exposure
- easier to log and attribute commands
- better proof of a deliberate security model

A transparent bridge may be a future deployment option, but it is not the best first step.

## Technology Direction

### Dart

Dart remains valuable for:

- client apps
- reusable protocol models
- protocol/client reference logic
- package extraction for reusable printer access semantics

### Go

Go is likely the better fit for the gateway service because it is better suited for:

- long-running daemons
- embedded deployment
- low-power Linux edge devices
- container and systemd service operation
- networking-heavy services

The likely long-term shape is:

- Dart package for protocol/client logic
- Go gateway for service and appliance deployment
- shared contract between Flutter app and gateway

## Phased Roadmap

### Phase 1: Local Application-Layer Gateway

- single printer
- single gateway instance
- app authenticates to gateway
- gateway authenticates to printer
- no full network isolation yet

### Phase 2: Secret Containment and Policy

- gateway stores printer credentials only on the gateway
- add local pairing and token auth
- introduce policy checks and audit logs

### Phase 3: Embedded Appliance Mode

- run on low-power hardware
- printer moved to isolated Wi-Fi, private AP, or dedicated subnet
- gateway becomes preferred path for all access

### Phase 4: Full Single-Path Architecture

- printer reachable only through gateway
- mediated camera access
- mediated telemetry and control
- multi-client and multi-role local access

## Open Questions

- how practical is Wi-Fi Direct or AP+uplink on target hardware and Linux drivers
- whether RTSP brokering can avoid a full relay in a clean way
- what minimum role model is useful for early versions
- what parts of current Dart connectivity code can become the reference protocol layer
- whether the gateway should expose a local REST API, local WebSocket API, or both

## Immediate Next Steps

- continue extracting the pure protocol/client layer from the Flutter app
- document a gateway-facing API contract
- centralize printer command and ACK parsing
- identify which capabilities are safe for first-wave mediation
- sketch a minimal Go gateway prototype architecture

## Draft Position Statement

BoomPrint Gateway is intended as a constructive proof of concept showing that secure local-first access to Developer Mode printers is feasible without mandatory cloud mediation. It aims to reduce practical risk for users today while also demonstrating architectural patterns that vendors could adopt to improve official LAN connectivity and local security support.
