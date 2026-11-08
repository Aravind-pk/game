class_name Stylize
extends RefCounted
## Anime / cel look for imported models: toon diffuse + toon specular, plus an
## inverted-hull ink outline as a next pass. Materials are converted once and cached.

const OUTLINE_COLOR := Color(0.13, 0.11, 0.11)

static var _cache := {}
static var _outline_mats := {}


static func outline_material(width: float) -> ShaderMaterial:
	var key := snappedf(width, 0.001)
	if _outline_mats.has(key):
		return _outline_mats[key]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;
uniform vec4 color : source_color = vec4(0.09, 0.08, 0.09, 1.0);
uniform float width = 0.03;
void vertex() {
	VERTEX += normalize(NORMAL) * width;
}
void fragment() {
	ALBEDO = color.rgb;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("color", OUTLINE_COLOR)
	_outline_mats[key] = m
	return m


static func toon(src: Material, outline_width: float) -> Material:
	if not (src is StandardMaterial3D):
		return src
	var key := "%d:%.3f" % [src.get_instance_id(), outline_width]
	if _cache.has(key):
		return _cache[key]
	var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = clampf(m.roughness, 0.55, 1.0)
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	var emissive := m.emission_enabled and m.emission.get_luminance() > 0.05
	if outline_width > 0.0 and not emissive:
		m.next_pass = outline_material(outline_width)
	_cache[key] = m
	return m


## Convert every surface under `root`. outline_width is in the model's local units.
static func apply(root: Node, outline_width := 0.03) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src:
				mi.set_surface_override_material(s, toon(src, outline_width))
