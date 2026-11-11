# Concept: GDCommentCodes — comment-driven editor hints for Godot

Author: DevGreem
Date: 2026-11-11
Status: anchored brainstorming hypothesis, pre-design. Plain GDScript plugin, Godot 4.7,
integrated script editor only.

Superseded: this file records the concept as stated in the first brainstorming round. The current
state, after review and after the API documentation pass, is in `concepts_brief.md` (decisions and
open questions) and `docs/spikes/completion-api.md` (what the engine actually allows). Notable
changes since this file: `@tool` is required only on scripts with a dynamic annotation, `self.` is
required on member accesses, `self` in an annotation is the **receiver** of the call (not the
class where the call is written, which would make the example above produce nothing), the
`#: valor<int,String>` form was reclassified as an error-reporting feature and deferred, calls
through a bare identifier get no suggestions, and the context node is the node running the script
open in the editor rather than a node picked by hand.

Two corrections this file does not yet reflect in its own text, kept here so the gap is explicit:
`ejecutar_animacion("salto")` written in `jugador.gd` is not valid GDScript for a function declared
in `padre.gd`; the call has to name a receiver (`perro.ejecutar_animacion("salto")`). And the
`@tool` marker belongs on the script that carries the dynamic annotation, not on every script
involved.

## What it is

A Godot editor plugin. In GDScript source files, a comment written as `#: <instruction>`
above a function declaration tells the plugin to give the developer suggestions while typing
in that function's parameter list. A comment that does not start with `#:` is an ordinary
comment and the plugin ignores it.

The first instruction set:

1. `#: nombre<enum(self._get_animations())>` — the `String` parameter `nombre` accepts one
   value from a list that a member of the class produces. `self.` is required and means "this
   member belongs to the class of the instance running the call". The plugin calls the member and
   splits what it returns into suggestions.
2. `#: nombre<enum("idle,moverse,saltar")>` — static suggestion set written literally in the
   comment. Nothing is executed.
3. Deferred: `#: valor<int,String>` above `func mi_funcion(valor: Variant)`. It was meant to make
   the editor report an error when a value of another type is passed, not to suggest values, so it
   is a separate feature and not part of the first version.

Example the author wants to work on day one (`@tool` is required, the export is guarded inside the
generator, and the suggestion appears at the call site, not at the declaration):

```gdscript
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

Called from another script in the same scene:

```gdscript
@tool

func atacar() -> void:
	ejecutar_animacion("salto")               # suggestions appear here
	self.comp.animar("corre")                 # and here, self. is required
```

`ejecutar_animacion(` with no receiver at all is not ambiguous: the running instance is the one
whose script is being edited. The `self.` requirement applies to accesses through another member.
Whether node-path receivers (`$Gato.ejecutar_animacion(`) are also accepted is an open grammar
question, recorded in `concepts_brief.md`.

## Decisions already made by the author

* Scope is the integrated Godot script editor. External editors (VS Code, LSP clients) are
  out of scope for now and only a possible future direction.
* Dynamic suggestions need real values, so the plugin executes user code. Static suggestions
  are resolved by reading the comment only.
* Built-in generators (for example "give me the animation names of the AnimationPlayer in
  this scene, without me writing a function") are explicitly out of v1 scope, but the
  instruction system must allow adding them later.
* The instruction names (`enum`, and later others) live in a registry, so adding an
  instruction means writing a module, not editing the parser. v1 ships only `enum` plus the
  type restriction form.
* `self.` is mandatory wherever a class member is meant: in the annotation
  (`enum(self._get_animations())`) and in the code being completed (`self.gato.ejecutar_animacion(`).
  The plugin never infers where a bare identifier comes from, so it needs no type resolver.
* `self` in an annotation binds to the instance running the code at the call site, and the member
  is found by walking the inheritance chain, so a child class does not have to redefine the
  generator.
* The script editor's Script menu carries a node selector, in the style of a SQL editor's
  "execute in the context of X": it lists nodes of the open scene, and if the selected node stops
  running the script currently open in the editor, the selection clears.
* The currently open scene is the one shown in the active scene tree; the 2D or 3D editor mode is
  irrelevant.
* If the script being edited is not attached to any node of the open scene, and no autoload
  provides it, dynamic suggestions are not offered. A `Resource` script counts as available if it
  is referenced by an autoload (possibly through other resources) or if it is used by a node in
  the current scene. (Autoload availability at edit time is pending verification: see
  `docs/spikes/completion-api.md`, check 5.)
* `@tool` is mandatory on annotated scripts. It is the developer's job, not the plugin's: if the
  script is not `@tool`, the plugin warns that its comments will not run and provides no dynamic
  suggestions.
* A generator that returns `null` produces no suggestions. Guarding missing references
  (for example an unassigned `@export`) is the developer's job inside the generator, since GDScript
  has no `try`.
* Other errors are soft: invalid or failed evaluation prints an error to the console and shows no
  suggestions. It must not break the editor or the script.
* Suggestions are added to Godot's normal completion list, they do not replace it. (The documented
  contract of `add_code_completion_option` says the opposite; merging is pending verification: see
  `docs/spikes/completion-api.md`, check 2.)
* The suggestion list opens automatically when the caret reaches the annotated parameter's
  argument position — for `func funcion(a: int, b: String)`, after the user types
  `funcion(10,` — and the typed text filters the list. If the engine does not allow it, automatic
  opening is dropped.
* The type restriction form (`#: valor<int,String>`) is deferred: it was intended as editor error
  reporting on wrong argument types, not as a suggestion source.

## Known gaps left open on purpose

* Exact grammar of `#:` (nesting, escaping commas inside values, one annotation per
  parameter, multiple parameters annotated, whitespace rules).
* How the plugin reads the script's own text (in-memory editor buffer versus saved file) and
  how fresh the annotation data must be while typing.
* Whether the annotated function is only matched by name from inside the project, or also for
  engine classes and scene instantiation.
* Cost model: how often the member function runs while typing, and caching.
* Version support policy (4.7 only, or 4.x line).
* Whether `self.` member lookup allows plain attributes (no call) and what a non-String
  return value means.

## Repository state

`/home/ian/Documents/remote/github/gd_comment_codes` is a Godot 4.7 project. The plugin is a
skeleton: `addons/gd_comment_codes/plugin.cfg` (name "GDCommentCodes", version 0.1) and
`addons/gd_comment_codes/gd_comment_codes.gd`, an `@tool extends EditorPlugin` with empty
`_enable_plugin`, `_disable_plugin`, `_enter_tree`, `_exit_tree`. No other source files.
