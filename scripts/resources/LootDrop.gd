class_name LootDrop
extends Resource
## One entry in a monster's loot table.

@export var item_id: String = ""
@export var quantity: int = 1
@export var min_quantity: int = 0       ## if >0, roll range [min_quantity, quantity]
@export var chance: float = 1.0         ## 0..1  (1.0 = always)
@export var is_currency: bool = false   ## GP / Slayer Coins instead of an item
@export var currency_id: String = ""    ## "gp" | "slayer_coins" | "abyssal_coins"
