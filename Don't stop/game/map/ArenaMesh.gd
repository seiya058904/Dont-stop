extends RefCounted
## Flatten the static arena's ordered, coloured primitives into one canvas mesh.
## Geometry stays in world units: no render texture, resolution cap or lighting bypass.
## Only presentation uses this builder; navigation and collision still own their rectangles.
var vertices := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()

func finish() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _polygon(points: PackedVector2Array, ink: Color, triangles: PackedInt32Array) -> void:
	var base := vertices.size()
	for point in points:
		vertices.append(Vector3(point.x,point.y,0))
		colors.append(ink)
	for index in triangles: indices.append(base+index)

func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ink: Color) -> void:
	_polygon(PackedVector2Array([a,b,c,d]),ink,PackedInt32Array([0,1,2,0,2,3]))

func draw_colored_polygon(points: PackedVector2Array, ink: Color) -> void:
	_polygon(points,ink,Geometry2D.triangulate_polygon(points))

func draw_rect(rect: Rect2, ink: Color, filled := true, width := -1.0) -> void:
	var a := rect.position
	var b := Vector2(rect.end.x,rect.position.y)
	var c := rect.end
	var d := Vector2(rect.position.x,rect.end.y)
	if filled:
		_quad(a,b,c,d,ink)
	else:
		draw_polyline(PackedVector2Array([a,b,c,d,a]),ink,width)

func draw_line(a: Vector2, b: Vector2, ink: Color, width := -1.0, antialiased := false) -> void:
	draw_polyline(PackedVector2Array([a,b]),ink,width,antialiased)

func draw_polyline(points: PackedVector2Array, ink: Color, width := -1.0, antialiased := false) -> void:
	if points.size() < 2: return
	var closed := points[0].is_equal_approx(points[-1])
	var count := points.size()-1 if closed else points.size()
	var offsets := PackedVector2Array()
	for i in count:
		var before := points[(i-1+count)%count] if closed or i>0 else points[i]
		var after := points[(i+1)%count] if closed or i<count-1 else points[i]
		var incoming := (points[i]-before).normalized()
		var outgoing := (after-points[i]).normalized()
		if incoming == Vector2.ZERO: incoming = outgoing
		if outgoing == Vector2.ZERO: outgoing = incoming
		var normal := Vector2(-outgoing.y,outgoing.x)
		var miter := Vector2(-incoming.y,incoming.x)+normal
		miter = miter.normalized()
		var denominator := miter.dot(normal)
		offsets.append(miter/maxf(0.25,denominator))
	var half := (width if width > 0.0 else 1.0)*0.5
	for i in (count if closed else count-1):
		var j := (i+1)%count
		var left_a := points[i]+offsets[i]*half
		var left_b := points[j]+offsets[j]*half
		var right_b := points[j]-offsets[j]*half
		var right_a := points[i]-offsets[i]*half
		_quad(left_a,left_b,right_b,right_a,ink)
		if antialiased:
			_fringe(left_a,left_b,points[j]+offsets[j]*(half+0.35),points[i]+offsets[i]*(half+0.35),ink)
			_fringe(right_b,right_a,points[i]-offsets[i]*(half+0.35),points[j]-offsets[j]*(half+0.35),ink)

func _fringe(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ink: Color) -> void:
	_quad(a,b,c,d,ink)
	colors[colors.size()-1] = Color(ink,0)
	colors[colors.size()-2] = Color(ink,0)

func draw_arc(center: Vector2, radius: float, start: float, end: float, count: int, ink: Color, width := -1.0, antialiased := false) -> void:
	var points := PackedVector2Array()
	for i in count:
		points.append(center+Vector2.RIGHT.rotated(lerpf(start,end,float(i)/(count-1)))*radius)
	draw_polyline(points,ink,width,antialiased)

func draw_circle(center: Vector2, radius: float, ink: Color, filled := true, width := -1.0, antialiased := false) -> void:
	var count := clampi(ceili(radius*3),16,128)
	if not filled:
		draw_arc(center,radius,0,TAU,count+1,ink,width,antialiased)
		return
	var points := PackedVector2Array([center])
	var triangles := PackedInt32Array()
	for i in count: points.append(center+Vector2.RIGHT.rotated(i*TAU/count)*radius)
	for i in count: triangles.append_array(PackedInt32Array([0,i+1,(i+1)%count+1]))
	_polygon(points,ink,triangles)
