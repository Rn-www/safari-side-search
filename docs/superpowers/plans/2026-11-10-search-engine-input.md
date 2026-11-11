# Search engine selection and automatic input implementation plan

> Execute natively in this session; a fresh reviewer checks the final change.

**Goal:** Fix actual menu selection/default persistence and accept engine names, domains or search result URLs in the custom editor.

**Architecture:** Keep strict SearchEngine templates and stored engine IDs. Normalize user input through a pure Shared resolver; give menu items explicit target/action routes that receive their own represented IDs. Preserve existing sandbox, native UI and panel-local Esc.

**Tech Stack:** Swift, Foundation, AppKit, existing compiler/build/test scripts.

**Spec:** User request in this chat on 2026-11-10; google.com resolves to https://www.google.com/search?q={query}. Default means the existing sidebar default search engine.

## Constraints

No full-screen Esc, extra helper, new permission, network discovery or third-party package. Visible checks only on the built-in display. Unknown homepages must not invent an unverified search endpoint; accept an actual search URL with an identifiable term parameter or retain input and explain what is missing. Existing custom templates remain valid.

## Review focus

Real menu-item dispatch, not direct control callback; current versus default isolation; reloaded preferences; exact host matching and ambiguous query parameters; edits/deduplication without losing custom IDs or navigation state.

- [x] Check native menu-item dispatch: baseline passed. Reproduce settings auto-hide in actual UI; replace auto-hiding NSPanel with NSWindow and defer menu-triggered sheets.
- [x] Add normalization, optional automatic naming, recognizable URL preview and store-backed save; test aliases, schemes, terms, invalid hosts, encoding and duplicate presets/customs.
- [x] Verify core, engine/settings integration and fresh review; install a signed universal clean build, then sync source ZIP, application ZIP and delivery metadata.

Completed: 196 core checks, settings and engine integration, independent review fixes, signed universal 1.2.1 (10), actual native menu/input/save/restart checks, and test-data cleanup. Current/default restored to Google.
