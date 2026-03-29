# Haven Plugin — Hello Service

## What This Project Is

This repository is a **reference Haven plugin**.

It demonstrates the minimal structure and expectations for a service that can be installed, managed, and orchestrated by Haven.

This is **not a production service**.
It is a **template + contract example** for future plugin development.

---

## What Haven Expects From a Plugin

Haven operates on three core abstractions:

Capability → Bundle → RuntimeUnit

This repository provides exactly one of each.

### Capability

User-facing feature.

Example:
- "Hello Service"

This is what users install via Haven.

---

### Bundle

A deployable implementation of a capability.

- Maps a capability → runtime units
- Defines user-configurable settings

In this plugin:
- Single bundle
- Single runtime unit

---

### RuntimeUnit

A single executable process.

- Native binary (this project)
- Started and managed by Haven via launchd
- Must be fully self-contained

---

## Plugin Structure

```text
Specs/
  Capabilities/
  Bundles/
  Runtime/
Service/
  Package.swift
  Sources/HelloService/main.swift
Scripts/ 
