import gg
import gx
import os
import rand

struct App {
mut:
	gg            &gg.Context
	touch         TouchInfo
	ui            Ui = Ui{}
	theme         &Theme = themes[0]
	theme_idx     int = 0
	board         Board
	undo          []Board
	atickers      [4][4]int
	state         GameState = .play
	tile_format   TileFormat = .normal
	moves         int
}

struct Pos {
	x int = -1
	y int = -1
}

struct Board {
mut:
	field  [4][4]int
	points int
	shifts int
}

struct TileLine {
	ypos   int
mut:
	field  [5]int
	points int
	shifts int
}

struct TouchInfo {
mut:
	start_pos Pos
}

enum TileFormat {
	normal
	log
	exponent
	shifts
	none_
	end_ // To know when to wrap around
}

enum GameState {
	play
	over
	victory
}

fn (b Board) transpose() Board {
	mut res := b
	for y in 0..4 {
		for x in 0..4 {
			res.field[y][x] = b.field[x][y]
		}
	}
	return res
}

fn (b Board) hmirror() Board {
	mut res := b
	for y in 0..4 {
		for x in 0..4 {
			res.field[y][x] = b.field[y][3 - x]
		}
	}
	return res
}

fn (t TileLine) to_left() TileLine {
	right_border_idx := 5
	mut res := t
	mut zeros := 0
	mut nonzeros := 0
	// gather meta info about the line:
	for x in 0..4 {
		if res.field[x] == 0 {
			zeros++
		} else {
			nonzeros++
		}
	}
	if nonzeros == 0 {
		// when all the tiles are empty, there is nothing left to do
		return res
	}
	if zeros > 0 {
		// we have some 0s, do shifts to compact them:
		mut remaining_zeros := zeros
		for x := 0; x < right_border_idx - 1; x++ {
			for res.field[x] == 0 && remaining_zeros > 0 {
				res.shifts++
				for k := x; k < right_border_idx; k++ {
					res.field[k] = res.field[k + 1]
				}
				remaining_zeros--
			}
		}
	}
	// At this point, the non 0 tiles are all on the left, with no empty spaces
	// between them. we can safely merge them, when they have the same value:
	for x := 0; x < right_border_idx - 1; x++ {
		if res.field[x] == 0 {
			break
		}
		if res.field[x] == res.field[x + 1] {
			for k := x; k < right_border_idx; k++ {
				res.field[k] = res.field[k + 1]
			}
			res.shifts++
			res.field[x]++
			res.points += 1 << res.field[x]
		}
	}
	return res
}

fn (b Board) to_left() Board {
	mut res := b
	for y in 0..4 {
		mut hline := TileLine{y}
		for x in 0..4 {
			hline.field[x] = b.field[y][x]
		}
		reshline := hline.to_left()
		res.shifts += reshline.shifts
		res.points += reshline.points
		for x in 0..4 {
			res.field[y][x] = reshline.field[x]
		}
	}
	return res
}

fn (mut app App) update_tickers() {
	for y in 0..4 {
		for x in 0..4 {
			mut old := app.atickers[y][x]
			if old > 0 {
				old--
				app.atickers[y][x] = old
			}
		}
	}
}

fn (mut app App) new_game() {
	app.board = Board{}
	for y in 0..4 {
		for x in 0..4 {
			app.board.field[y][x] = 0
			app.atickers[y][x] = 0
		}
	}
	app.state = .play
	app.undo = []
	app.moves = 0
	app.new_random_tile()
	app.new_random_tile()
}

fn (mut app App) check_for_victory() {
	for y in 0..4 {
		for x in 0..4 {
			fidx := app.board.field[y][x]
			if fidx == 11 {
				app.victory()
				return
			}
		}
	}
}

fn (mut app App) check_for_game_over() {
	mut zeros := 0
	mut remaining_merges := 0
	for y in 0..4 {
		for x in 0..4 {
			fidx := app.board.field[y][x]
			if fidx == 0 {
				zeros++
				continue
			}
			if (x > 0 && fidx == app.board.field[y][x - 1])
				|| (x < 4 - 1 && fidx == app.board.field[y][x + 1])
				|| (y > 0 && fidx == app.board.field[y - 1][x])
				|| (y < 4 - 1 && fidx == app.board.field[y + 1][x]) {
				remaining_merges++
			}
		}
	}
	if remaining_merges == 0 && zeros == 0 {
		app.game_over()
	}
}

fn (mut app App) new_random_tile() {
	mut etiles := [16]Pos{}
	mut empty_tiles_max := 0
	for y in 0..4 {
		for x in 0..4 {
			fidx := app.board.field[y][x]
			if fidx == 0 {
				etiles[empty_tiles_max] = Pos{x, y}
				app.atickers[y][x] = 0
				empty_tiles_max++
			}
		}
	}
	if empty_tiles_max > 0 {
		new_random_tile_index := rand.intn(empty_tiles_max)
		empty_pos := etiles[new_random_tile_index]
		// 1/8 chance of creating a `4` tile
		rint := rand.intn(8)
		random_value := if rint == 0 { 2 } else { 1 }
		app.board.field[empty_pos.y][empty_pos.x] = random_value
		app.atickers[empty_pos.y][empty_pos.x] = 15
	}
	app.check_for_victory()
	app.check_for_game_over()
}

fn (mut app App) victory() {
	app.state = .victory
}

fn (mut app App) game_over() {
	app.state = .over
}

fn (mut app App) move(d Direction) {
	old := app.board
	new := match d {
		.left  { old.to_left() }
		.right { old.hmirror().to_left().hmirror() }
		.up    { old.transpose().to_left().transpose() }
		.down  { old.transpose().hmirror().to_left().hmirror().transpose() }
	}
	if old.shifts != new.shifts {
		app.moves++
		app.board = new
		app.undo << old
		app.new_random_tile()
	}
}

fn frame(mut app App) {
	app.update_tickers()
	app.gg.begin()
	app.draw()
	app.gg.end()
}

// TODO: Move this somewhere else once Android support is merged
$if android {
	#include <android/log.h>
	#define LOG_TAG "v_logcat_test"
	#define printf(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
	#define fprintf(a, ...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
}

// Utility functions, to avoid importing `math`
[inline]
fn min(a, b int) int {
	if a < b { return a } else { return b }
}

[inline]
fn max(a, b int) int {
	if a > b { return a } else { return b }
}

[inline]
fn abs(a int) int {
	if a < 0 { return -a } else { return a }
}

fn main() {
	mut app := &App{ gg: 0 }
	app.new_game()

	mut font_path := os.resource_abs_path(os.join_path('assets', 'RobotoMono-Regular.ttf'))
	$if android {
		// the `assets/` folder is implied, since we're getting the font straight from the apk
		font_path = 'RobotoMono-Regular.ttf'
	}

	app.gg = gg.new_context({
		bg_color: app.theme.bg_color
		width: default_window_width
		height: default_window_height
		use_ortho: false
		create_window: true
		window_title: 'canvas'
		frame_fn: frame
		event_fn: on_event
		user_data: app
		font_path: font_path
	})
	app.gg.run()
}
