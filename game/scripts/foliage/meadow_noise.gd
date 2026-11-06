class_name MeadowNoise
extends RefCounted
## The meadow's noise (shaders/foliage/meadow.gdshaderinc), baked once into one tiling texture rather than
## hashed on every grass vertex: four seamless fbm noises, one per channel, which the shader reads at the scale
## each layer wants (r: the soft patches, g: the fine speckle, b: the cool patches, a: the sun spots). Its mips
## blur away what a pixel cannot show, so the far lawn never shimmers. Set as the global fol_noise_tex.

const SIZE := 256

static var _tex: ImageTexture

static func texture() -> ImageTexture:
	if _tex: return _tex
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var chans: Array[Image] = []
	for i in 4:
		var n := FastNoiseLite.new()
		n.seed = 4127 + i * 977
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.frequency = 4.0 / SIZE        # four features across a tile
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		chans.append(n.get_seamless_image(SIZE, SIZE, false, false, 0.1, true))
	for y in SIZE:
		for x in SIZE:
			img.set_pixel(x, y, Color(chans[0].get_pixel(x, y).r, chans[1].get_pixel(x, y).r, chans[2].get_pixel(x, y).r, chans[3].get_pixel(x, y).r))
	img.generate_mipmaps()
	_tex = ImageTexture.create_from_image(img)
	return _tex
