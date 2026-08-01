extends SceneTree

const W := 4096
const H := 2048

func _init() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.0012
	noise.seed = 1337
	var noise2 := FastNoiseLite.new()
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.frequency = 0.004
	noise2.seed = 4242

	for y in H:
		for x in W:
			var u := float(x) / float(W)
			var v := float(y) / float(H)
			var lat := (0.5 - v) * PI
			var lon := u * TAU
			var up: float = sin(lat)
			var sun := 1.0
			var horizon := smoothstep(0.5, 0.55, v)
			var zenith := pow(maxf(up, 0.0), 0.55)

			var base := Color(0.35, 0.6, 0.9).lerp(Color(0.16, 0.32, 0.62), zenith * 0.8)
			base = base.lerp(Color(0.85, 0.88, 0.95), horizon * 0.35)
			base = base.lerp(Color(0.95, 0.78, 0.55), (1.0 - horizon) * 0.15)

			var sun_dir := Vector3(0.6, 0.35, 0.7).normalized()
			var dir := Vector3(cos(lat) * cos(lon), up, cos(lat) * sin(lon))
			var d: float = dir.normalized().dot(sun_dir)
			sun = pow(maxf(d, 0.0), 400.0) * 2.0
			sun += pow(maxf(d, 0.0), 8.0) * 0.6

			var n: float = noise.get_noise_2d(lon * 1.0, lat * 6.0)
			var n2: float = noise2.get_noise_2d(lon * 2.0, lat * 12.0)
			var cloud := clampf((n * 0.6 + n2 * 0.4 + 0.25) * 2.2, 0.0, 1.0)
			cloud *= (1.0 - absf(lat) / 1.2)
			cloud *= 0.9
			base = base.lerp(Color(1, 1, 1), cloud * 0.55)

			var col := base + Color(sun, sun, sun)
			col = col.linear_to_srgb()
			img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))

	img.save_png("res://textures/skybox.png")
	print("SAVED res://textures/skybox.png")
	quit(0)
