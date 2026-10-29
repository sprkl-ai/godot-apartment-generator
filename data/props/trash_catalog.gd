class_name TrashCatalog
extends Resource

@export var props: Array[TrashDef] = []

func by_asset(asset: String) -> TrashDef:
	for def: TrashDef in props:
		if def != null and def.asset == asset:
			return def
	return null

func at(index: int) -> TrashDef:
	if props.is_empty():
		return null
	return props[posmod(index, props.size())]
