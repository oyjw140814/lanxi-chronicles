extends SceneTree
## Original deterministic assets. Run again after changing the factory or batching code.
const Factory = preload("res://scripts/asset_factory.gd")
func _initialize() -> void:
	var factory := Factory.new()
	factory.batcher.use_catalog = false
	for kind in ["worker","guard","ranger","lancer","rider","breaker","heart","house","barracks","tower"]:
		for team in range(2):
			var art: Node3D = factory.make(kind,team)
			art.free()
	var catalog := {}
	for key in factory.batcher.cache:
		var paths: Array[String] = []
		for lod in range(2):
			var file := "res://assets/art/"+str(key).replace("/","_")+"_lod%d.res" % lod
			var err := ResourceSaver.save(factory.batcher.cache[key][lod],file,ResourceSaver.FLAG_COMPRESS)
			if err != OK:
				push_error("Asset save failed: "+file)
				quit(1)
				return
			paths.append(file)
		catalog[key] = paths
	var output := FileAccess.open("res://assets/art/mesh_catalog.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(catalog,"\t"))
	print("BAKED_ART pivots=",catalog.size()," LOD_assets=",catalog.size()*2)
	quit()
