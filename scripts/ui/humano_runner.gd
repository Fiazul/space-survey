class_name HumanoRunner
extends Control
# The dinosaur's arcade screen; all distances are pixels in a 512×288 canvas.

const SCREEN := Vector2(512, 288)
const FLOOR_Y := 222.0
const HUMAN_X := 110.0
const INK := Color("263541")
const PAPER := Color("f1dfb5")
const GRAVITY := 1200.0
const JUMP_SPEED := 440.0

var running := false
var crashed := false
var player_y := 0.0
var vertical_speed := 0.0
var distance := 0.0
var score := 0
var best := 0
var obstacles: Array[Dictionary] = []
var _next_obstacle := 2.0
var _rng := RandomNumberGenerator.new()
var _font: Font = ThemeDB.fallback_font

func _ready() -> void:
	custom_minimum_size = SCREEN
	size = SCREEN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 1077
	reset_run()

func reset_run() -> void:
	running = false
	crashed = false
	player_y = 0.0
	vertical_speed = 0.0
	distance = 0.0
	score = 0
	obstacles.clear()
	_next_obstacle = 2.0
	queue_redraw()

func jump() -> void:
	if crashed: reset_run()
	running = true
	if player_y <= .001:
		vertical_speed = JUMP_SPEED

func human_rect() -> Rect2:
	return Rect2(HUMAN_X - 9.0, FLOOR_Y - 40.0 - player_y, 18.0, 40.0)

func hit_obstacle() -> void:
	crashed = true
	running = false
	best = maxi(best, score)

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	var left := clampf(delta, 0.0, .25)
	while left > .000001 and running:
		var step := minf(left, 1.0/120.0)
		var speed := minf(180.0 + distance*.006, 300.0)
		distance += speed*step
		score = int(distance*.07)
		best = maxi(best, score)
		vertical_speed -= GRAVITY*step
		player_y = maxf(0.0, player_y + vertical_speed*step)
		if player_y == 0.0: vertical_speed = 0.0
		_next_obstacle -= step
		if _next_obstacle <= 0.0:
			obstacles.append({"x":540.0, "width":_rng.randf_range(18.0, 30.0), "height":_rng.randf_range(25.0, 42.0)})
			_next_obstacle = _rng.randf_range(1.45, 2.3)
		for obstacle in obstacles:
			obstacle.x -= speed*step
			var box := Rect2(float(obstacle.x), FLOOR_Y - float(obstacle.height), float(obstacle.width), float(obstacle.height))
			if human_rect().grow(-3.0).intersects(box.grow(-2.0)): hit_obstacle()
		obstacles = obstacles.filter(func(o): return float(o.x) + float(o.width) > -20.0)
		left -= step
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), PAPER)
	draw_string(_font, Vector2(24, 34), "HUMANO", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
	draw_string(_font, Vector2(320, 32), "HI %05d  %05d" % [best, score], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)
	for i in 3:
		var x := fposmod(120.0 + i*188.0 - distance*.16, 580.0) - 35.0
		var y := 70.0 + (i%2)*18.0
		draw_line(Vector2(x,y), Vector2(x+45,y), Color(INK,.25), 2.0)
		draw_line(Vector2(x+8,y-7), Vector2(x+32,y-7), Color(INK,.25), 2.0)
	draw_line(Vector2(0,FLOOR_Y), Vector2(512,FLOOR_Y), INK, 2.0)
	for i in 25:
		var x := fposmod(float(i)*23.0 - distance, 550.0) - 20.0
		draw_line(Vector2(x,FLOOR_Y+8+(i%3)*3), Vector2(x+5,FLOOR_Y+8+(i%3)*3), Color(INK,.45), 1.0)
	for obstacle in obstacles:
		var x: float = obstacle.x
		var height: float = obstacle.height
		var width: float = obstacle.width
		draw_rect(Rect2(x+width*.36, FLOOR_Y-height, width*.28, height), INK)
		draw_rect(Rect2(x, FLOOR_Y-height*.62, width, 6.0), INK)
		draw_rect(Rect2(x, FLOOR_Y-height*.86, 6.0, height*.3), INK)
		draw_rect(Rect2(x+width-6, FLOOR_Y-height*.73, 6.0, height*.2), INK)
	var y := FLOOR_Y - player_y
	var stride := sin(distance*.13)*6.0 if running and player_y == 0.0 else 2.0
	draw_rect(Rect2(HUMAN_X-6,y-43,12,12), INK)
	draw_rect(Rect2(HUMAN_X-5,y-28,10,16), INK)
	draw_line(Vector2(HUMAN_X,y-23), Vector2(HUMAN_X-12,y-15-stride*.5), INK, 5.0)
	draw_line(Vector2(HUMAN_X,y-22), Vector2(HUMAN_X+12,y-17+stride*.5), INK, 5.0)
	draw_line(Vector2(HUMAN_X-2,y-12), Vector2(HUMAN_X-6-stride,y), INK, 5.0)
	draw_line(Vector2(HUMAN_X+2,y-12), Vector2(HUMAN_X+6+stride,y), INK, 5.0)
	draw_rect(Rect2(HUMAN_X+2,y-40,3,3), PAPER)
	if crashed or not running:
		var text := "OOPS. HUMAN DOWN." if crashed else "A SMALL HUMAN. A BIG ADVENTURE."
		draw_rect(Rect2(78,90,356,65), PAPER)
		draw_string(_font, Vector2(0,112), text, HORIZONTAL_ALIGNMENT_CENTER, 512, 17, INK)
		draw_string(_font, Vector2(0,140), "SPACE / CLICK TO " + ("TRY AGAIN" if crashed else "JUMP"), HORIZONTAL_ALIGNMENT_CENTER, 512, 13, INK)
	draw_string(_font, Vector2(24,263), "NO DINOSAURS WERE HARMED IN THIS GAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK,.6))
