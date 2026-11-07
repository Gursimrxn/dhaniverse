class_name Screens
## One screen at a time, and while one is up it has the keys and the mouse. The world says what is up (a sheet, the phone, the
## mentor, the board in focus, the pause menu, settings, the title) and when anything is busy (that, or a film): the phone, the
## mentor and the paper ask before opening over it, and the player, the camera and the town's E ask before taking a key.

static var busy := Callable()      # something is up or a film plays: nothing new opens over it
static var up := Callable()        # a screen is up: the town gets no keys and no mouse

static func free_to_open() -> bool:
	return not busy.is_valid() or not busy.call()

static func holding() -> bool:
	return up.is_valid() and up.call()
