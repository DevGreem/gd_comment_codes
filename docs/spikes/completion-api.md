# Spike de viabilidad: inyectar sugerencias en el autocompletado del editor de Godot

Fecha: 2026-11-11 (segunda versión, reordenada tras la revisión). Godot 4.7.
Fuentes usadas: referencia de clases de Godot 4.7 (`CodeEdit`, `ScriptEditor`, `EditorInterface`),
headers del motor (`scene/gui/code_edit.h`, `core/object/editor_language.h`,
`editor/script/script_editor_plugin.h`), issues/propuestas de godotengine y el addon
`Godot-Code-Completions` (https://github.com/brohd11/Godot-Code-Completions).

Las citas de la referencia están transcritas de la documentación leída, no verificadas ejecutándolas:
el check 0 existe precisamente para eso. Nada de este documento está *testeado* todavía.

## Qué decide este spike

Dos resultados pueden cambiar el concepto de raíz:

* **check 1**: si las opciones que añade un addon **se suman** a las del motor o las **sustituyen**.
* **check 11**: si el generador puede ejecutarse sin un nodo vivo en la escena.

Todo lo demás ajusta el diseño, no la existencia del producto. El **check 0** va primero porque
confirma los nombres de API que el resto de la lista y el brief citan: si un nombre es distinto, las
líneas que lo usan quedan sin sentido.

## Preparación del repo (obligatoria antes de medir)

El estado actual invalida cualquier medición. Verificado en el repo:

0. **El trabajo sin commitear ya está resuelto** (commit `0dd3df0`). Estaban borrados en el árbol de
   trabajo, pero versionados en HEAD, los dos prototipos del plugin (`editor/gdcc_highlighter.gd`, un
   `SyntaxHighlighter` que envuelve al del editor y colorea `#:`; `export/debug_remover.gd`, un
   `EditorExportPlugin` que eliminaba las líneas `#: debug_only` y la sentencia de debajo) y el addon
   vendorizado `addons/godot_super-wakatime/`. El autor los hizo para probar y pidió commitear su
   eliminación, así que **no se recuperan**: son la decisión D18 del brief y no condicionan el diseño. Dos
   cosas de su contenido sí valen como evidencia *repo-verified* y quitan trabajo al spike: que
   `ScriptEditor.editor_script_changed`, `get_current_editor()`, `get_base_editor()` y la propiedad
   `code.syntax_highlighter` funcionan en 4.7 (los usaba ese código), y que un resaltador propio puede
   encadenarse al nativo guardando el anterior y fusionando su diccionario.
1. Hay **dos** addons de seguimiento de tiempo implicados. `project.godot:24` (editado en el commit
   `0dd3df0`) habilita `res://.godot/scenetime/plugin.cfg`: la ruta vive en la caché del editor, así que un
   clon limpio arranca con un error de plugin faltante; el addon se engancha a `text_changed` del mismo
   `CodeEdit` que vamos a medir, recorre el texto completo por pulsación, sube el contenido de los
   scripts a un servidor y reescribe `editor_plugins/enabled` al desinstalarse. En HEAD, además, está
   versionado `addons/godot_super-wakatime/` (18728 bytes en `godot_super-wakatime.gd`), que la misma
   línea deshabilitó al reemplazarlo. **Acción:** dejar `editor_plugins/enabled` vacío salvo el plugin
   bajo prueba, y decidir si `godot_super-wakatime` se conserva en el repo o se elimina en un commit.
2. `addons/gd_comment_codes` **no está habilitado**. **Acción:** añadir
   `res://addons/gd_comment_codes/plugin.cfg` a `editor_plugins/enabled` (o abrir el proyecto y
   activarlo desde Ajustes del editor → Complementos).
3. `plugin.cfg` tiene `description=""`. **Acción:** rellenarla; también sirve para anotar la versión
   mínima soportada, que el formato de `plugin.cfg` no permite declarar.
4. `export_presets.cfg` pertenece a otro proyecto: exporta a
   `../../../projects/trash/builds/index.html` con `export_filter="all_resources"` y
   `variant/extensions_support=true` en un proyecto de GDScript puro. **Acción:** borrarlo o reescribirlo,
   y prever la exclusión del plugin en exportaciones.
5. `project.godot:28` pide `3d/physics_engine="Jolt Physics"` sin `.gdextension` en el repo.
   **Acción:** quitar la línea o añadir la extensión; si no, Godot avisa en cada arranque.
6. No hay ni un `.tscn` ni scripts de ejemplo, y `.gitignore:18` ignora `**/test/*` (por eso el
   `test/` que existió nunca se pudo commitear). **Acción:** crear los fixtures abajo y ponerlos en
   `example/` y `tests/`, no en `test/`.

## Fixtures a crear

Rutas relativas al repo. Los mismos ficheros sirven después como demo de aceptación.

| Ruta | Contenido |
| :--- | :--- |
| `example/padre.gd` | `@tool`; `@export var animation_player: AnimationPlayer`; `#: nombre<enum(self._get_animations())>` sobre `ejecutar_animacion(nombre: String)`; `_get_animations()` con guarda `null` |
| `example/hijo.gd` | `extends "res://example/padre.gd"`, sin redefinir nada |
| `example/jugador.gd` | `@tool`; `@export var perro: Node` apuntando a un nodo con `padre.gd`; una función que llama `perro.ejecutar_animacion(` y `ejecutar_animacion(` |
| `example/escena.tscn` | raíz con `jugador.gd`, un `Node` con `padre.gd` (named `Perro`) con su `AnimationPlayer` hijo y animaciones `idle`, `saltar`, y un `Node` con `hijo.gd` (named `Canido`) |
| `example/subescena.tscn` | escena instanciada dentro de `escena.tscn`, con un nodo que usa `padre.gd` |
| `example/embebida.tscn` | escena con un nodo cuyo script está **embebido** en el propio `.tscn` (hay que escribir el fichero a mano) |
| `example/singleton.gd` | script para usar como autoload, con un método `@tool` que devuelve una lista |
| `tests/spike_probe.gd` | arnés headless para los checks 0, 6, 9, 12, 13, 14 |

Cambios en `project.godot`: añadir `[autoload]` con `Singleton="*res://example/singleton.gd"` para el
check 5, y `run/main_scene="res://example/escena.tscn"`.

Los fixtures ya cubren el caso de dos nodos corriendo el mismo script (`Perro` y `Canido` en
`escena.tscn`), que es el que mide el check 16; si el orden del árbol no da un resultado estable, la
tabla de formas de llamada del brief necesita una fila nueva y el selector vuelve a estar dentro.
Estos mismos ficheros son luego la demo de aceptación del paso 6 del brief, así que van a `example/`
versionados, no a la carpeta de pruebas.

Rama y artefactos: trabajar en `spike/completion-api`, con todo el código de prueba en
`tests/spike_probe.gd` y en `addons/gd_comment_codes/spike_probe.gd`, marcados como desechables. Al
terminar, o se promueven a la arquitectura o se borran; no dejar que el diseño herede un fichero por
accidente.

Resultados: `docs/spikes/completion-api-results.md`, una línea por check con veredicto, API exacta
usada y versión en la que apareció. Un check sin línea de resultado cuenta como no hecho.

## Checks

| # | Check | GUI/headless | Criterio binario | Si falla |
| :--- | :--- | :--- | :--- | :--- |
| 0 | Volcar la superficie real | headless | ver detalle abajo | no seguir: todo lo demás cita nombres sin confirmar |
| 1 | Sumar opciones sin borrar las del motor | GUI | tras el callback, ¿`get_code_completion_options()` contenía las nativas? ¿aparecen ambas listas? | el concepto pasa a popup propio o a resaltado |
| 2 | Que las opciones sobrevivan a la siguiente pulsación | GUI | escribir un carácter dentro del argumento: ¿sigue la entrada del addon? | disparo solo por tecla del motor |
| 3 | Abrir el popup desde el plugin | GUI | `update_code_completion_options(true)` ¿abre? ¿y con `(`/`,` en `code_completion_prefixes`? | `Ctrl+Space` manual |
| 4 | Leer el texto sin guardar | GUI | ¿`CodeEdit.text` del editor activo vs `Script.source_code` vs disco | anotar que solo funciona con el script abierto |
| 5 | Autoload disponible en el editor | GUI | desde un `@tool`, acceder al singleton y llamar un método | quitar autoloads y el caso `Resource` del diseño |
| 6 | Detección de `@tool` | headless | ¿existe getter, o hay que buscar el texto `@tool` en el buffer? | el aviso D6 se hace heurístico y se declara |
| 7 | Encontrar el nodo de contexto | GUI | recorrer `get_edited_scene_root()` buscando el nodo con el script editado; ¿y en subescenas? | el selector del menú Script pasa de opcional a obligatorio |
| 8 | Receptores por ruta de nodo | GUI | `$Gato.` y `get_node("Gato")` ¿resuelven? ¿con `is_in_string`/`is_in_comment` fiables? | fuera de v1 |
| 9 | Herencia | headless | `hijo.new().has_method("_get_animations")` == `true` y `call()` funciona | reconsiderar D4 |
| 10 | Identidad de script | GUI | comparar `node.get_script()` con `get_current_script()` en: externo, embebido, heredado, subescena; y tras guardar (recompilación) | el selector no puede persistir por referencia |
| 11 | Ejecutar sin nodo vivo | GUI | con el mismo generador: nodo real vs `node.duplicate()` vs `script.new()`; qué devuelve cada uno y cuánto tarda | se confirma que `@tool` + escena abierta son obligatorios |
| 12 | Lista de métodos del script | headless | `get_script_method_list()` sobre la cadena de `GDScript` ¿incluye solo métodos declarados? ¿`has_method("free")` es `true`? | la allowlist no se puede construir y hay que inventar otra |
| 13 | Partir una cadena vacía | headless | `"".split(",")` ¿0 o 1 elementos? Con `Array`/`PackedStringArray` ¿qué cuenta como vacío? | contrato de retorno sin cerrar |
| 14 | Coste por llamada | GUI | `Time.get_ticks_usec()` alrededor de `call()` en el nodo real; recorrido completo del árbol | revisar el disparo por eventos |
| 15 | Coexistencia con otro addon de completado | GUI | instalar `Godot-Code-Completions`, activar ambos: ¿quién gana? | un solo dueño del hook, con detección y aviso |
| 16 | Varios nodos con el mismo script | GUI | con dos nodos corriendo `padre.gd`, ¿el orden del árbol da un resultado estable y cuál se muestra como receptor? | `ambiguous_context` necesita UI, y el selector vuelve a ser obligatorio |

## Check 0 en detalle

Es una sonda de `ClassDB` bajo el binario 4.7 del propio equipo
(`.godot/editor/project_metadata.cfg:7` registra la ruta del ejecutable), sin abrir la GUI. Resuelve de
golpe las citas dudosas del documento: qué método lleva la nota *"This list will replace all current
candidates"*, si existe `clear_code_completion_options`, qué claves devuelve realmente
`get_code_completion_options` (se citaron `kind`/`display_text`/`insert_text`/`font_color`/`icon`/`default_value`
mientras la firma usa `type`/`value`/`location`), el orden exacto de parámetros de
`add_code_completion_option`, el valor por defecto real de `code_completion_enabled`, y si
`ScriptEditor` expone `get_unsaved_files` o `get_unsaved_scripts`.

```gdscript
# tests/spike_probe.gd
extends SceneTree

func _initialize() -> void:
	for cls in ["CodeEdit", "TextEdit", "ScriptEditor", "EditorInterface", "GDScript", "Script"]:
		print("== ", cls)
		for m in ClassDB.class_get_method_list(cls, true):
			print("\t", m["name"])
		for p in ClassDB.class_get_property_list(cls, true):
			print("\t@ ", p["name"], " default=", p.get("default_value"))
	var edit := CodeEdit.new()
	print("code_completion_enabled default: ", edit.code_completion_enabled)
	print("has is_in_string: ", edit.has_method("is_in_string"))
	print("has clear_code_completion_options: ", edit.has_method("clear_code_completion_options"))
	print("empty split size: ", "".split(",").size())
	print("PSC join: ", ",".join(PackedStringArray(["a", "b"])))
	print("GDScript source_code: ", GDScript.new().has_method("reload"), " ", "source_code" in GDScript.new())
	quit()
```

Complemento del check 0, en el editor (esta es la prueba del **check 1**): imprimir
`get_code_completion_options()` **antes** de añadir
nada dentro del callback de completado, con el caret detrás de una coma en una llamada a un método
propio. Ese es el dato que decide el check 1 y, con él, la forma del producto.

## Dónde aterriza cada resultado

Cada fila nombra la sección de `concepts_brief.md` que hay que reescribir con el veredicto, o el número
de decisión/pregunta si el brief lo resuelve ahí.

| Check | A terra en |
| :--- | :--- |
| 0 | *The mechanism* (nombres reales de API) y *Grammar* (claves reales del diccionario de opciones) |
| 1 | *The mechanism* punto 1, D11, y el motivo `hook_busy` en *Diagnostics* |
| 2, 3 | *The mechanism* puntos 1-2 y D12 |
| 4 | *Resolving values away from the keystroke path* (de dónde se lee el texto) |
| 5 | *Deferred* (autoloads y el caso `Resource`) |
| 6 | D6 y el motivo `not_tool` |
| 7, 9, 16 | tabla de formas de llamada en *Which object answers…*, D16 y Q4 |
| 8 | *Deferred* (rutas de nodo) y la fila `node_path_unsupported` |
| 10 | *Resolving values away from the keystroke path* (claves de la tabla) |
| 11 | Q3 (nodo vivo / copia / instancia) |
| 12, 13 | *Calling the developer's code inside the editor* (allowlist) y *Grammar* (contrato de retorno) |
| 14 | *Cost* (Q6) |
| 15 | Q5 y el motivo `hook_busy` |

## Referencias

* `CodeEdit` — https://docs.godotengine.org/en/4.7/classes/class_codeedit.html
* `ScriptEditor` — https://docs.godotengine.org/en/stable/classes/class_scripteditor.html
* `scene/gui/code_edit.h` — https://github.com/godotengine/godot/blob/master/scene/gui/code_edit.h
* `core/object/editor_language.h` (declara la API de edición *"unstable and work-in-progress"*) —
  https://github.com/godotengine/godot/blob/master/core/object/editor_language.h
* Propuesta de rediseño del API de completado (explica por qué hay señal y método virtual que no
  conviven) — https://github.com/godotengine/godot-proposals/issues/10550
* Lectura de opciones nativas desde un plugin (`request_code_completion` →
  `get_code_completion_options` → `cancel_code_completion`) —
  https://github.com/godotengine/godot-proposals/issues/6839
* Migración de funciones del editor fuera de `ScriptLanguage` —
  https://github.com/godotengine/godot-proposals/issues/14566
* Patrón de disparo sin `Ctrl+Space` con `text_changed` —
  https://forum.godotengine.org/t/code-complete-in-code-edit-node/86695
* Addon de completado existente, extensión por subclase de `EditorCodeCompletion` —
  https://github.com/brohd11/Godot-Code-Completions
