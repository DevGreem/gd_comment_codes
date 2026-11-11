# GDCommentCodes: comment-driven value suggestions in the Godot script editor

* **Author:** DevGreem
* **Date:** 2026-11-11
* **Status:** brainstorming brief, pre-design. `concept.md` keeps the first-round wording;
  `docs/spikes/completion-api.md` keeps the engine-API research and the test plan.
* **Evidence labels used below.** *documented* = stated in the Godot 4.7 class reference or engine
  source; *inferred* = read from a header, forum thread or proposal, not confirmed; *tested* = run in
  Godot; *repo-verified* = read out of the files in this repository. No behaviour of the engine is
  *tested* in this document yet — that is what the spike changes. Repository facts are *repo-verified*.

## Overview

A plugin for the Godot editor (4.7, GDScript only) that reads specially formatted comments in your
scripts and turns them into value suggestions in the script editor's completion list.

The comment form is `#: <parameter-name><instruction>` on the line above a function. Throughout this
document that line is called a **hint comment**, to keep it apart from GDScript's own `@` annotations
such as `@tool` and `@export`. The one instruction in this version, `enum`, gives a `String` parameter
a set of acceptable values. When you write the argument for that parameter, the editor offers those
values next to its own entries.

Two sources for the set:

* written in the comment: `#: nombre<enum("idle,saltar")>` — nothing runs;
* produced by a member of the class: `#: nombre<enum(self._get_animations())>` — the plugin calls that
  member on the object receiving the call and turns what it returns into suggestions.

**The problem this targets.** A `String` parameter whose valid values exist only at runtime (the names
of an `AnimationPlayer`'s animations, the keys of a data file, the names of a scene's nodes) gets no
completion entries from Godot 4.7: both of the engine's fixed-set features, `enum` and `@export_enum`,
need the set at compile time or in the Inspector. This plugin's target is that one gap — values known
only once the scene is loaded, offered where the developer types them.

### The reference example

Used throughout this document. Two scripts, one scene.

```gdscript
# example/padre.gd
@tool

@export var animation_player: AnimationPlayer = null

#: nombre<enum(self._get_animations())>
func ejecutar_animacion(nombre: String) -> void:
	pass

func _get_animations() -> String:
	if animation_player == null:
		return ""
	return ",".join(animation_player.get_animation_list())
```

```gdscript
# example/jugador.gd
@export var perro: Node      # points at a node running padre.gd

func atacar() -> void:
	self.perro.ejecutar_animacion("salto")   # suggestions appear here
	perro.ejecutar_animacion("salto")        # no suggestions: see the call table
```

The second line is not a mistake: this plugin deliberately refuses receivers it cannot resolve from
text, and `perro.ejecutar_animacion(` is one of them. GDScript allows both forms; the plugin does not.
That is a restriction with a cost, written down rather than hidden: the developer has to type `self.`
for suggestions to appear, and the plugin has to say so in the message it prints when they don't.

### Terms

* **hint comment** — a `#:` line above a function declaration.
* **instruction** — the named part inside `< >`, for example `enum(...)`.
* **generator** — the member a dynamic instruction names, called to produce values.
* **receiver** — the object the hinted function is called on. Inside GDScript that object is what the
  function's own `self` means.
* **context node** — the node in the open scene running the script currently open in the script
  editor. `self.` paths written in the code are evaluated starting from this node.
* **allowlist** — the methods declared by the receiver's own script and its base scripts. The only
  methods the plugin may call.
* **suggestion** — one completion entry shown in `CodeEdit`.
* **reason code** — the name of the reason a suggestion set is empty, from the table under
  *Diagnostics*.

## Analysis

### Which object answers, and how a call finds its hint comment

Two separate jobs, and they need to stay separate in the implementation:

**1. Matching a call to a hint comment.** The plugin works from the receiver, not from a project-wide
list of hint comments. It takes the function name at the caret, the argument index the caret is in, and
the resolved receiver object; it then reads the script attached to that receiver (from the editor buffer
if it is open, otherwise from disk) and looks for a function of that name carrying a hint comment for
that parameter. No index of the whole project is needed, because the receiver tells the plugin exactly
which script to read. If the receiver's script chain does not declare that function, there is nothing to
match and the reason is `no_matching_hint`.

**2. Resolving the receiver.** The receiver comes from text the plugin can read. It never asks the
language what a variable's type is, because that resolver is not an addon API (the engine's own
`core/object/editor_language.h` states *"This class is unstable and work-in-progress"*).

`self` in a hint comment means the receiver, matching what `self` means inside the body of a function in
GDScript. The generator is therefore called on the receiver instance, and looked up in that instance's
class chain — which is why a child class does not have to redeclare a generator inherited from its
parent. An earlier rule in this brief said the generator should be looked up in the class of the code
where the call is written; that rule is gone because it makes the reference example answer nothing —
`jugador.gd` does not inherit from `padre.gd`, so the generator would never be found.

The call table is the normative statement of what happens. Each row names the script open in the editor,
because the context node depends on it.

| Script open in the editor | Call typed | Receiver resolved to | Suggestions |
| :--- | :--- | :--- | :--- |
| `padre.gd` | `ejecutar_animacion(` | the node in the scene running `padre.gd` | yes |
| `padre.gd` | `self.ejecutar_animacion(` | same | yes |
| `jugador.gd` | `self.perro.ejecutar_animacion(` | `context_node.get("perro")` | yes |
| `jugador.gd` | `ejecutar_animacion(` | the node running `jugador.gd`; its chain does not declare `ejecutar_animacion` | no — `no_matching_hint` |
| `jugador.gd` | `perro.ejecutar_animacion(` | nothing: a bare identifier could be a member, a local or a parameter | no — `receiver_unresolved` |
| `jugador.gd` | `$Gato.ejecutar_animacion(`, `get_node("Gato").ejecutar_animacion(` | not attempted in this version | no — `node_path_unsupported` |
| any of the above | receiver resolves to `null` | — | no — `receiver_null` |
| any of the above | the receiver's script chain does not declare the generator | — | no — `no_matching_hint` |

Two consequences worth stating out loud:

* A hint comment only helps when the **receiver** runs a script whose class chain has both the function
  and the generator. Calls on another node work (`self.perro.`); calls from a script that neither
  declares the function nor receives it do not.
* Several nodes in the scene can run the same script. For `ejecutar_animacion(` with no receiver, the
  plugin uses the first match in scene-tree order and prints which node it used; the hint comment line
  in the popup names the receiver's node path, so the developer can see whose values they are looking
  at. A manual override (the Script-menu selector the author described) stays deferred: it is only
  needed if the automatic choice turns out to be wrong in practice, and whether a node can even be
  added to that menu is unverified — the only precedent in this project's own history uses
  `EditorPlugin.add_tool_submenu_item`, which lands in *Project → Tools*.

### The mechanism, and what is still unverified

`CodeEdit` in the 4.7 class reference exposes `add_code_completion_option(type, display_text,
insert_text, text_color, icon, value, location)`, `update_code_completion_options(force)` (documented to
try to pop up the list when `force` is true), `get_code_completion_options`, `cancel_code_completion`,
the `code_completion_requested` signal and the `code_completion_prefixes` property. The script editor's
widget is reachable with `EditorInterface.get_script_editor().get_current_editor().get_base_editor()`.
Four of these names are already *repo-verified*: the committed prototype in this repo called
`ScriptEditor.editor_script_changed`, `get_current_editor()`, `get_base_editor()` and read
`code.syntax_highlighter`, so they exist in 4.7 and were exercised here. The rest — the completion
methods and their note about replacing candidates — still need confirming against the running build
(spike check 0). What is not documented is how they behave together:

1. **Accumulation versus replacement.** The reference carries a note to the effect that the submitted
   list replaces the current candidates. Either `add_code_completion_option` accumulates within one
   completion cycle and that note belongs to `update_code_completion_options`, or each `add_...` call
   clears the list on its own. The second reading makes "show next to the engine's entries" impossible
   without rebuilding them. Spike check 1 is the question that can end the project.
2. **Survival across keystrokes.** The GDScript editor refills the list as you type. Whether entries an
   addon added survive the next refill is unknown: spike check 2.
3. **Ownership of the hook.** Only one addon can own completion on a given `CodeEdit`: the reference
   states `code_completion_requested` is not emitted when `_request_code_completion()` is overridden,
   and overriding requires a subclass of a widget the editor itself creates, so an addon cannot install
   one (*inferred*). Any other completion addon in the user's project competes for the same slot. The
   plugin must detect that another owner exists, say so, and stand down rather than disable someone
   else; spike check 15 measures the collision.
4. **Reading text the developer has not saved.** The names for this (`ScriptEditor.get_unsaved_files()`,
   `Script.source_code`) are *inferred* and must be read from the class list: spike checks 0 and 4.
5. **Whether project autoloads exist at edit time.** *Inferred*: the engine may build them only when the
   game runs. If they do not exist in the editor, the autoload context and the `Resource` case with it
   leave the design: spike check 5.

### Calling the developer's code inside the editor

The plugin calls a function written by the user, in the editor's process, on the editor's main thread.
Four properties of that environment shape the design, and none of them is optional:

* **No exceptions.** GDScript has no `try`. An error inside a generator aborts the call chain and prints
  from the engine; the plugin can only check things before calling.
* **No timeout, no interruption.** A generator with an infinite loop, or an `await` that never resumes,
  freezes the editor with unsaved work, and nothing can cancel it. This document states that accepted
  limit instead of promising the plugin will never break the editor.
* **`await` breaks the contract even when it resumes**, because calling a coroutine returns no value to
  display. Generators must take zero arguments and be synchronous, and the plugin must check that
  before calling rather than assume it.
* **The receiver is a live node.** Calling methods on it can change properties, add or free children,
  create undo entries and mark the scene as modified.

**The allowlist is the security control, and `has_method()` is not it.** `has_method()` belongs to
`Object` and reports true for the engine's own methods, so a hint comment naming `free`, `queue_free`,
`set_script` or `remove_child` would pass a "member exists" check and damage the user's scene while they
type. Before calling, the member name must appear in the **allowlist** as defined in Terms: the methods
declared by the receiver's own script and its base scripts. Engine methods are refused by name. The same
rule applies to each segment of a member path. Whether the engine exposes that list
(`GDScript.get_script_method_list()` walking `Script.get_base_script()`) is spike check 12.

**Wrong-source execution.** `#:` is also a documentation-comment prefix in other ecosystems' tools. A
comment copied from a tutorial, or shipped inside a downloaded addon, could be read as an instruction and
get its `self.<member>` called while the developer types. Controls: parse hint comments only in scripts
outside `addons/**` unless the project opts in, never call a member that fails the allowlist, ignore
unknown instruction names, and require recorded consent the first time a project's dynamic hint comment
would run code.

**Failure isolation.** A generator that fails is marked and not retried for that receiver until the hint
comment, the scene or the explicit refresh changes. Its message is reported once per annotation, not once
per keystroke.

**Not decided: what object to run on.** Live node, a `duplicate()` of it, or a throwaway instance of its
script. A copy or a throwaway instance removes the mutation risk entirely and, for self-contained
generators, removes the need for an open scene; both lose the references a generator reads from the rest
of the scene, which is exactly what the reference example uses. Spike checks 11 and 14 measure it. D6
below states what is settled (the generator runs on the receiver) and leaves the nature of that object
open as Q4.

### Resolving values away from the keystroke path

Values are resolved when something changes — the hint comment is edited, the script is saved, the scene
changes, the developer runs the refresh command — and stored in a table. The keystroke path only reads
that table and submits entries. The table is part of the design, not an optimisation: without it the
plugin would call the user's function on every character typed. An earlier line in this brief said
"caching until a latency measurement justifies it"; that was wrong, and the corrected rule is D9.

Table entries are keyed by hint comment, receiver instance id and a hash of the hint comment line. A
stored instance id must be revalidated with `is_instance_valid()` before use, because a node deleted in
the scene leaves a dead id behind; entries are dropped when the scene closes. Which exact text is hashed
is an open detail (Q1).

A consequence the developer will notice: a hint comment written seconds ago has no values until the next
resolution event. The plugin resolves the script being edited on a short debounce so the wait is not
"save first", and reports `stale` rather than silence.

### Grammar not yet written

Hint comments live inside other people's source files, so changing the format later is a breaking change
nobody can detect. This needs EBNF and a version before implementation. All items are blocking for the
design document and are collected as Q1:

* separator and spacing in `#: nombre<enum(...)>`, and whether the parameter name must match a real
  parameter of the function;
* a value containing a comma inside the literal list — either an escape rule or a stated "not supported";
* whether member paths of more than one segment are allowed (`self.gato._get_animations()`), and how
  each segment is validated;
* whether nested calls with arguments are allowed inside `enum(...)` — the zero-argument rule is settled
  in D8, so this is only about the grammar that expresses it;
* adjacency: what may sit between the `#:` line and the `func` line, and whether several parameters of
  one function can be hinted;
* the instruction name. `enum` collides with the `enum` keyword and with `@export_enum`, both of which
  already mean "fixed set of values" to a Godot developer. Examples here use `enum` while Q2 decides;
* return contract: `null` means no suggestions (D7). The literal example returns `""`, and whether that
  becomes one empty suggestion or none depends on how an empty string splits (*inferred*, spike check
  13). Accepting `Array` and `PackedStringArray` alongside `String` would remove the `",".join(...)` the
  reference example has to write today;
* whether suggestions are inserted with surrounding quotes, and which completion kind and `location`
  value an addon entry should use so the engine's filtering behaves;
* line endings: `.gitattributes` normalises to LF on commit, but an editor buffer on Windows can hold
  CRLF, and the parser reads the buffer.

### Diagnostics: when there are no suggestions, say why

Twelve causes can produce the same visible symptom: an empty list. Each gets a name, a place the
developer will actually look, and a recovery action.

Two channels, because a reason at the caret is useless in an Output panel nobody is reading:

* **in place:** the popup's own header line shows the receiver's node path when suggestions exist, and
  shows `gdcc: <reason code> <plain words>` where the plugin has something to say about the call under
  the caret. The plugin does not insert a non-selectable row into the candidate list, because the engine
  filters that list on the typed prefix and an explanatory row could be filtered away.
* **in the Output panel:** one tagged line per event, format
  `gdcc [<code>] <script>:<line> <param> receiver=<NodePath> engine=<version> <message>`, deduplicated
  per hint comment until something changes.

| reason code | cause | in-place message | recovery |
| :--- | :--- | :--- | :--- |
| `parse_error` | the line does not match the grammar | hint comment not understood | fix the line; the message quotes the offending part |
| `unknown_instruction` | instruction name not registered | unknown instruction | never executed; check the spelling |
| `not_tool` | dynamic hint comment in a script without `@tool` | script needs `@tool` | add `@tool`; the engine's own `missing_tool` warning applies too |
| `no_context_node` | the edited script runs on no node of the open scene | no node to run on | open the scene, or use the literal form |
| `ambiguous_context` | several nodes run the edited script | shows the first match used | the deferred selector |
| `receiver_unresolved` | receiver is a bare identifier or an expression | no suggestions; the message names the fix: write `self.perro.…` | rewrite the call with `self.` |
| `node_path_unsupported` | receiver is `$Path` or `get_node("Path")` | not handled in this version | use `self.<member>` |
| `receiver_null` | a path segment resolved to `null` | names the segment | assign the export |
| `no_matching_hint` | the receiver's class chain has no hint comment for that function and parameter | nothing hinted here | write the hint comment on the receiver's class |
| `member_not_allowed` | named member is not in the allowlist | refused, error severity | point the hint comment at a declared generator |
| `not_synchronous` | the generator awaits | refused before calling | make the generator synchronous |
| `call_failed` | the generator raised | reported once | fix the generator, then refresh |
| `wrong_return_type` | returned value is neither a string nor an array | reported once | fix the return type |
| `empty_result` | the generator returned nothing | silent | — |
| `suppressed` | repeated failures marked this hint comment | shown on refresh | refresh |
| `stale` | values not yet resolved for this change | shown until resolution | refresh, or wait for the debounce |
| `hook_busy` | another addon already owns completion | plugin stands down | disable one of the two |

Before every generator call the plugin writes a start record with the hint comment's file and line, the
member and the receiver, and flushes it. If the editor is killed during a hang, the last unpaired record
names the responsible hint comment.

### Cost

No numbers are agreed. What is fixed: no network and no model calls in the completion path, and the
expensive work happens on events rather than per keystroke. What the design document must state with a
value and a unit: resolution latency target for a normal scene, the debounce window, the maximum number
of generators per resolution, the table's size limit, and the effort estimate for the first version. The
only estimate in this brief is one afternoon for the spike (Q5); the cost of
running a generator itself is measured by spike check 14.

### Repository state

Repo-verified. A Godot 4.7 project with an empty `EditorPlugin`
(`addons/gd_comment_codes/gd_comment_codes.gd`, all four hooks `pass`) and a `plugin.cfg` whose
`description` is empty. The plugin is not enabled. What *is* enabled, in the versioned `project.godot`,
is a plugin path inside `.godot/` — a cache directory a fresh clone does not have — and that plugin is a
time-tracking addon that hooks `text_changed` on the same script-editor widget the spike needs to
measure, uploads script text to a server, and rewrites `editor_plugins/enabled` on uninstall. The
project also requests the Jolt physics engine with no `.gdextension` in the repo, and
`export_presets.cfg` belongs to another project (it exports outside the repo and enables GDExtension in
a plain-GDScript project).

**The working tree has uncommitted work that contradicts this brief's history.** `git ls-tree HEAD` shows
that two prototypes were *committed* and are now deleted in the working tree, not lost:
`addons/gd_comment_codes/editor/gdcc_highlighter.gd` (a `SyntaxHighlighter` that wraps the editor's own
highlighter, delegates to it and merges the result, colouring any `#:` occurrence orange) and
`addons/gd_comment_codes/export/debug_remover.gd` (an `EditorExportPlugin`, registered with
`add_export_plugin()`, that removes `#: debug_only` lines and the statement under each one when building).
`addons/godot_super-wakatime/` is also tracked and deleted in the working tree, and `project.godot` was
edited without committing to point at `.godot/scenetime/` and to drop `run/main_scene`. Everything the
plugin file itself used to do — connect `ScriptEditor.editor_script_changed`, resolve
`get_current_editor().get_base_editor() as CodeEdit`, replace `code.syntax_highlighter` — is
*repo-verified* code that ran in this project, which raises the evidence level of several claims in
*The mechanism* above. None of it is to be resurrected: the author dropped it (D18). The test folders named
in the editor cache were never committed and cannot be recovered. `.gitignore` ignores `**/test/*`, which
is why one of them could never have been committed. Still open in the repo, and cleaned before measuring:
the `editor_plugins/enabled` entry pointing inside `.godot/`, the Jolt physics request with no extension in
the repo, and `export_presets.cfg` belonging to another project — the spike's setup section lists the
concrete edits, and fixtures go in `example/` and `tests/`.

### Ideal end state

The hint comment says which values are valid. The plugin answers from the cheapest source available,
resolves on events rather than keystrokes, calls only members the project's own scripts declare, refuses
a receiver it cannot resolve instead of guessing, tells you which node's values you are looking at, and
names its reason whenever the list is empty.

## Goals vs. Non-Goals

**In scope for the first version**, pending the spike:

* read hint comments from the text the developer has open in the editor;
* the `enum` instruction from two sources: a literal list, and a generator on the receiver called
  through the allowlist;
* match a call to a hint comment through the receiver's own script, with no project-wide index;
* show suggestions next to the engine's own entries in the argument position of the hinted parameter,
  triggered by the engine's completion key, and opened automatically at the argument position only if
  spike checks 1 to 3 pass;
* `@tool` required on a script carrying a dynamic hint comment; a script with only literal hint comments
  needs neither `@tool` nor an open scene;
* the reason codes above, reported in place and in the Output panel in the stated format;
* hint comments parsed only outside `addons/**` unless the project opts in, consent recorded before the
  first dynamic execution, both stored in Project Settings under a `gd_comment_codes/` namespace so they
  travel with the project; a refresh command reachable from *Project → Tools*;
* a value table filled by events, never by keystrokes;
* an example scene and example scripts committed, and parsing plus resolution callable without an editor
  window.

**Deferred, each with its re-entry condition:**

* structural providers that read the scene without executing project code: when a case appears that the
  literal form cannot express and the developer would otherwise have to write a `@tool` generator for;
* the `#: valor<int,String>` form, reclassified as editor error reporting on argument types: when it has
  its own design, its own integration point and its own instruction name;
* node-path receivers (`$Gato.`, `get_node("Gato")`): when the argument-position parser exists anyway,
  which is the condition that makes them affordable;
* receivers that are local variables or general expressions: only if a design for type resolution
  without the engine's resolver is written;
* autoloads and resource-reachable context: only if spike check 5 shows the engine provides them at edit
  time;
* the Script-menu context selector: only if automatic discovery of the context node proves wrong in
  practice, and only if a place in that menu can be added at all;
* a project-wide status dock: it needs the project-wide index ruled out above, so it returns with it;
* caching results between sessions.

**Out of scope:** network access and model calls in the completion path, external editors, syntax
highlighting of `#:` as a feature, C# scripts, and the `#: debug_only` export-stripping behaviour of the
dropped prototype (D18) — that instruction goes with it, and hint comments are not removed from exported
builds in this version.

## Alternatives Weighed

* **Interpret the comment without executing anything** for dynamic values. Rejected by the author: static
  analysis gives the type of the values but not the values. It does not apply to the reference example,
  where reading the `AnimationPlayer` in the open scene answers the same list without running project
  code; that is the deferred structural provider above.
* **Built-in providers written by the plugin.** Rejected by the author for the first version: every engine
  type supported this way is a surface to keep aligned with Godot. The resolver design keeps room for
  them.
* **The plugin adds `@tool` or simulates it.** Rejected by the author: the developer marks the script.
* **Ask which node is the context, or follow the node clicked** versus **discover the node running the
  edited script.** The author described a Script-menu selector with a reset rule; automatic discovery
  covers the same node with no new UI, so the selector is deferred and the choice is open as Q4, settled
  by spike check 7.
* **Type-restriction hints as suggestions.** Rejected by the author with a correction: the form was meant
  for error reporting, so it is a different feature, deferred.
* **Registry of instruction modules from the start** versus **direct dispatch until a second instruction
  exists.** The author's first-round decision was the registry. This brief proposes keeping the parser
  and the resolver in separate files with one resolver signature and building no registry mechanism yet,
  because one instruction does not need a plugin system. The author accepted this in place of the
  first-round registry decision, recorded as D17.
* **`@export_enum` on an exported variable.** The engine already gives a dropdown of values in the
  Inspector, with no code running and no plugin; it covers values a node owns, not a parameter of a
  function called elsewhere.
* **A GDScript `enum` plus a typed parameter** (`enum State { IDLE, SALTAR }` with
  `func ejecutar_animacion(nombre: State)`). Typed, no plugin, no editor execution; the values must be
  known at compile time, which is the case this plugin is not about.
* **GDScript's own annotation syntax (`@`) instead of a hint comment.** Read by the parser and the editor
  and by any future tooling, and it cannot collide with another ecosystem's doc-comment convention. The
  comment is cheaper to prototype and is what the author wants; the wrong-source risk above is the price.
* **`EditorSyntaxHighlighter` for underlaid hints instead of completion entries.** No popup to share and
  no completion hook to win. Two facts from the recovered prototype (`git show
  HEAD:addons/gd_comment_codes/editor/gdcc_highlighter.gd`) correct what this brief said earlier: the
  wrapper **keeps** GDScript's own highlighting by calling the previous highlighter and merging its
  dictionary, so this route adds rather than replaces; and it already worked, colouring `#:` in this
  project. The author deleted it as an experiment, so the correction stands and the code does not. Against
  it: a
  colour on a comment does not tell you the valid values for the argument you are writing, so it is a
  companion to the suggestions, not the feature.
* **Stripping hint comments at export, with a `#: debug_only` instruction.** Found in the committed
  prototype the first review round had called lost: an `EditorExportPlugin`, registered with
  `add_export_plugin()`, deleting `#: debug_only` lines and the statement below each one. It was a second
  instruction, and a differently shaped one (above a statement, naming no parameter, producing no values),
  so it would have moved D3, the grammar and the registry question. Rejected by the author, whose
  experiment it was, and out of scope (D18).
* **A plugin-owned popup anchored at the caret.** The fallback if the completion hook turns out not to
  allow additive entries. No API for caret pixel position is named in this brief, so it is not costed.
* **Building on `Godot-Code-Completions`** (https://github.com/brohd11/Godot-Code-Completions), which
  hooks script-editor completion from GDScript, offers values at an argument position, lists enum members
  for typed arguments and resolves receivers by instantiating scripts; extended by subclassing
  `EditorCodeCompletion`, configured under `EditorSettings -> plugin/code_completion/`. It is the
  strongest evidence that this project is buildable and the strongest argument against writing the
  plumbing twice. Against it: its extension point may not allow values produced by executing project
  code, it competes for the same single completion hook, it brings its own version churn and settings
  namespace, and `plugin.cfg` cannot declare a dependency. Spike check 15 and staging step 3 answer it.
  Open as Q6.
* **An external language-server extension (VS Code).** Excluded from scope by the author.

## Key Decisions & Staging for Next Steps

### Decisions

* **D1.** Integrated Godot script editor only. Godot 4.7. External editors out of scope.
* **D2.** `#:` marks a hint comment; any other comment is an ordinary comment.
* **D3.** A hint comment names a parameter of the function below it and carries one instruction.
* **D4.** `self` in a hint comment is the **receiver** of the call, matching GDScript's own meaning, and
  the generator is looked up in the receiver's class chain.
* **D5.** Receivers are resolved only from readable text, per the call table. A bare identifier or any
  other expression is refused with `receiver_unresolved`, and the message states the fix. This keeps type
  inference out of the design.
* **D6.** The generator runs on the receiver resolved as in D5. Whether that object is the live node, a
  copy or a throwaway instance is open (Q3). A script with only literal hint comments needs neither
  `@tool` nor an open scene; a script with a dynamic hint comment must be `@tool`, and the plugin reports
  otherwise.
* **D7.** The developer guards the generator's own missing references. A `null` return means no
  suggestions.
* **D8.** Before a generator is called, its name must appear in the allowlist (methods declared by the
  receiver's script and its base scripts); engine methods are refused. Generators take zero arguments and
  must be synchronous.
* **D9.** Values come from a table resolved on events. The keystroke path reads the table and submits
  entries; it never calls a generator.
* **D10.** Repeated failures for one hint comment are suppressed until something changes; messages do not
  repeat per keystroke.
* **D11.** The goal is suggestions next to the engine's own entries rather than replacing them. The
  documented note that submitted options replace the current candidates makes this an open risk decided by
  spike check 1, not settled behaviour.
* **D12.** Automatic opening at the argument position is attempted, with the engine's completion key as
  the fallback. The argument-position parser is needed either way, because the plugin has to know which
  parameter the caret is in.
* **D13.** Hint comments are parsed only outside `addons/**` unless the project opts in; consent for
  dynamic execution is recorded in Project Settings under `gd_comment_codes/`.
* **D14.** `#: valor<int,String>` is editor error reporting, not suggestions, and is deferred.
* **D15.** No network access and no model calls in the completion path.
* **D16.** Matching a call to a hint comment goes through the receiver's own script; no project-wide
  index. Provisional: it follows from D5 and D9 and needs confirming against spike check 7.
* **D17.** One instruction means no registry mechanism: `parse_hint_comment()` and `resolve_values()`
  live in separate files, the resolver carries one signature (instruction name, argument, receiver and
  call context in; values or a reason out), and dispatch is a direct match on the instruction name. A
  second real instruction adds the registry by extracting those two files, with no change to the hint
  comment format. This replaces the first-round decision to ship a registry, on the author's request.
  The second instruction found in the project's history (`#: debug_only`) does not change that: it was an
  experiment and is out of scope (D18).

* **D18.** The two prototypes in the first commits (`gdcc_highlighter.gd`, `debug_remover.gd`) and the
  vendored `addons/godot_super-wakatime/` addon are dropped on the author's decision, with the deletion
  committed as `0dd3df0`. Nothing from them is designed around, and `#: debug_only` is not an instruction of
  this plugin. Two findings stay as evidence: the wrapper pattern for `syntax_highlighter` (keep the previous
  highlighter, merge its dictionary) and the four `ScriptEditor`/`CodeEdit` names that code already exercised
  on 4.7.

### Open questions for the design document

* **Q1.** The grammar list in *Grammar not yet written*, every item, including which text is hashed for
  the table key.
* **Q2.** The instruction name (`enum` versus `values`/`options`) and the format version rule.
* **Q3.** Whether generators run on the live receiver, a copy, or a throwaway instance.
* **Q4.** Whether the context node is discovered automatically, chosen through a selector, or both.
* **Q5.** Whether to build on `Godot-Code-Completions`.
* **Q6.** Cost numbers and the effort estimate, and where each setting lives — Project Settings as
  proposed in D13 versus per-user EditorSettings, with the consequences for version control and rollback.

### Staging

1. Clean the repo so the spike measures something real, following the setup list in
   `docs/spikes/completion-api.md`: the prototype and addon deletions are already committed (D18), so what is
   left is removing the `.godot/` entry from `editor_plugins/enabled`, enabling the plugin under test,
   dropping or rewriting `export_presets.cfg`, dropping the Jolt physics line, and committing the fixtures
   under `example/` and `tests/`.
2. Run the spike, starting with check 0 (dump the real `ClassDB` surface, which also settles the method
   names this brief cites from documentation) and then check 1, the accumulation question. Write one line
   per check to `docs/spikes/completion-api-results.md` with the verdict and the API actually used.
3. Install and run `Godot-Code-Completions` in 4.7 (check 15). If its extension point can carry values
   produced by executing project code, the first version is a parser plus a resolver and no editor
   integration. Record the answer either way; it settles Q5.
4. Write the grammar in EBNF with the return contract and the format version, and close Q1 and Q2 in the
   same pass.
5. Fix the receiver forms for the first version, including whether node paths are accepted (Q1, Q4).
6. Write the acceptance test as reproducible steps on the reference example, one expected outcome per row
   of the call table, plus a counter inside the generator that proves no call happens while typing.
7. Run the design document (`egm-draft`, the EGM stage that turns this brief into a formal design doc)
   once steps 2, 3, 4 and 5 are settled.

## Changelog

* Round 1 (seven review passes) produced the API questions, the execution-risk list, the call-site
  problem and the missing alternatives. Most were answered in conversation with the author.
* Round 2 (eight review passes) found that the brief had become a log of layered revisions carrying six
  internal contradictions, that the "look up the generator in the call-site class" rule broke the
  reference example, that `has_method()` is not a safety control, that the acceptance test asked for the
  case a scope limit excluded, and that several cited API names were unverified. This version is the
  rewrite that followed: one owner per fact (the call table and the reason-code table are normative,
  decisions reference them), evidence labels on every claim, review narration moved out of the normative
  text, and the spike renumbered to match.
* A verification pass after that rewrite caught a factual error inherited from round 1: the "deleted
  prototypes with no surviving source" were committed and recoverable from git. Reading them corrected two
  claims (a highlighter wrapper preserves GDScript's own highlighting rather than replacing it; four editor
  API names were already exercised in 4.7) and surfaced a second instruction, `#: debug_only`. The author
  confirmed the work was experimentation and asked for the deletions to be committed, which produced D18 and
  commit `0dd3df0`.
