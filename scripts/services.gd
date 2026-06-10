class_name GameServices
extends RefCounted

## Typed reference bundle, built once by Game.gd and handed to each system.
##
## This replaces the old pattern of passing the whole `game` node around and
## reaching through it (`game.modifiers`, `game.rail_network`, ...). Systems
## receive this object and use only the fields they need; units and components
## get individual fields injected instead (see Board.register_unit).

var grid: Node2D
var board: Node2D                     # Board: units/cities/trains + spawning
var turn: Node                        # TurnManager: day counter + pipeline
var control: ControlMap               # line of control / territory paint
var input: Node2D                     # InputController (for UI-triggered modes)
var modifiers: ModifierManager
var weather: WeatherManager
var terrain: TerrainManager
var rail_network: RailNetwork
var fow: FOWManager
var card_manager: CardManager
var enemy_ai: EnemyAI
var ui: UIManager
