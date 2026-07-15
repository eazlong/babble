# Godot Client

This context defines the domain language used by the Godot client for scene-driven learning flows and dialogue playback.

## Language

**Dialogue Flow**:
A continuous linear dialogue segment with no special animation, input wait, reward grant, or scene transition inside it. A scene controller may play multiple dialogue flows and coordinate non-dialogue actions between them.
_Avoid_: Complete scene flow, step, animation block

**Dialogue Flow Config**:
A JSON file that defines one or more dialogue flows by `flow_id`, speaker, localized lines, and parameter placeholders. Dialogue flow configs live separately from scene configs because dialogue content changes independently from scene metadata and resource loading.
_Avoid_: Scene config, script constants, hard-coded dialogue table

**Scene Dialogue Flow File**:
A dialogue flow config scoped to one scene and containing all dialogue flows for that scene. Each flow still has a globally unique `flow_id` so the loader can index flows across files.
_Avoid_: One file per line, one file per dialogue flow

**Dialogue Flow Loader**:
A pure data component that loads, validates, queries, localizes, and parameterizes dialogue flows. It does not play UI, synthesize speech, wait for audio, or advance scene state.
_Avoid_: Dialogue player, scene controller, TTS handler

**Local Dialogue Flow Loader**:
A dialogue flow loader instantiated by a scene controller instead of registered as an autoload singleton. The local loader avoids new global state while dialogue flow loading remains a pure data concern.
_Avoid_: Dialogue flow singleton, global dialogue registry

**Named Placeholder**:
A `{name}` token inside localized dialogue text that is replaced by a runtime value before playback. Named placeholders are preferred over positional `%s` formatting because localized languages may need different word order or repeated values.
_Avoid_: Positional placeholder, `%s`

**Dialogue Language Fallback**:
The runtime rule used when a dialogue line does not contain the requested language: requested language first, then `en`, then any available language with a warning. Fallback happens when localized lines are requested, not when JSON files are loaded.
_Avoid_: Load-time translation, silent empty text

**Dialogue Flow Load Error**:
A recoverable problem in a dialogue flow config that should be reported during loading or lookup without crashing the scene. Invalid files fail as files, invalid flows or lines are skipped, duplicate `flow_id` values are rejected, and missing runtime placeholders remain visible with a warning.
_Avoid_: Silent correction, scene crash
