# ProtocolsSupplementTests.swift — Refactoring Guide

**Criterion**: S6 (Multiple modules/protocols in single test file)

## Issue
This test file contains conformance tests for three distinct protocols:
- DI-01: `SettingsStoring` (via `SettingsStore`)
- DI-02: `UsageStoring` (via `UsageStore`)
- DI-07: `TokenSyncing` (via `TokenStore`)

Each protocol represents a separate dependency injection concern and should be isolated in its own test class file for clarity and maintainability.

## Recommendation
Split into three files:
1. `SettingsStoringConformanceTests.swift` (lines 22-45)
2. `UsageStoringConformanceTests.swift` (lines 49-79)
3. `TokenSyncingConformanceTests.swift` (lines 83-111)

This improves:
- **Discoverability**: Each protocol's tests are in a dedicated file
- **Independence**: Protocol-specific test utilities (e.g., `makeTempURL`, `makeTempDbPath`) stay local
- **Scalability**: New conformance tests for each protocol can be added without cluttering unrelated tests

## Current State
- SettingsStoringConformanceTests: 24 lines
- UsageStoringConformanceTests: 31 lines
- TokenSyncingConformanceTests: 29 lines
- Helper duplicates: `makeTempURL` and `makeTempDbPath` patterns could be consolidated per-file

## Notes
- Tests use actual implementations, not mocks (protocol conformance by contract)
- No S7 (hand-written mocks) detected
- No S8 (xcodebuild type issues) detected
- Lines < 500 (not M2)
