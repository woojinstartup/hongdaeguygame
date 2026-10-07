class_name HEStageData
extends RefCounted
## Four Hongdae stages. Legend: # building, . street, S start, G goal,
## C convenience store (safe zone), B busking crowd (hide), P picnic mat,
## T tree, a AirPods, b "I have a boyfriend" shield, f call a friend, n "No English".
## Enemy routes are tile coordinates; trio members stand on a single post and sweep.

const STAGES := [
	{
		"id": "exit9",
		"name": "Hongik Univ. Station Exit 9",
		"goal_label": "EXIT",
		"theme": "street",
		"hint": "Stay out of the pink vision cones. Hide in the 24/7 store. Reach EXIT.",
		"map": [
			"####################",
			"#S.....#......a....#",
			"#.###.##.####.####.#",
			"#...#......#CC#....#",
			"###.#.####.#.##.##.#",
			"#b..#.#..........#.#",
			"#.###.#.#####.##.#.#",
			"#.....#.....#..#...#",
			"#.#####.###.##.#.#G#",
			"####################",
		],
		"enemies": [
			{"kind": "basic", "route": [Vector2i(7, 5), Vector2i(16, 5)]},
			{"kind": "basic", "route": [Vector2i(18, 1), Vector2i(18, 7)]},
		],
	},
	{
		"id": "walking",
		"name": "Hongdae Walking Street",
		"goal_label": "GO",
		"theme": "street",
		"hint": "Busking crowds hide you, but slow you down. Beware the iPhone dasher.",
		"map": [
			"####################",
			"#S..BB.....#...BB..#",
			"#.####.###.#.#####.#",
			"#.....a..#...#.....#",
			"###.####.#.###.###.#",
			"#...BBB........#CC.#",
			"#.#####.#.####.#.###",
			"#...f.#.#BB...n#...#",
			"#.###...####.#...#G#",
			"####################",
		],
		"enemies": [
			{"kind": "basic", "route": [Vector2i(1, 3), Vector2i(8, 3)]},
			{"kind": "basic", "route": [Vector2i(3, 5), Vector2i(14, 5)]},
			{"kind": "dasher", "route": [Vector2i(9, 7), Vector2i(14, 7)]},
			{"kind": "photo", "route": [Vector2i(12, 1), Vector2i(18, 1)]},
		],
	},
	{
		"id": "park",
		"name": "Yeontral Park",
		"goal_label": "GO",
		"theme": "park",
		"hint": "Picnic mats and trees block your path. The trio sweeps the middle.",
		"map": [
			"####################",
			"#S...T......T...b..#",
			"#.PP.PP.TT.PPP.PPP.#",
			"#.......n..........#",
			"#T.PPP.TT.PPP.TT.T.#",
			"#.......CC.........#",
			"#.PPTP.PP.PTPP.PP.P#",
			"#....f.............#",
			"#.TT.PP.PP.TT.PP.TG#",
			"####################",
		],
		"enemies": [
			{"kind": "trio", "route": [Vector2i(4, 5)], "phase": 0.0},
			{"kind": "trio", "route": [Vector2i(11, 5)], "phase": 2.1},
			{"kind": "trio", "route": [Vector2i(16, 5)], "phase": 4.2},
			{"kind": "dasher", "route": [Vector2i(6, 7), Vector2i(17, 7)]},
			{"kind": "photo", "route": [Vector2i(13, 1), Vector2i(18, 1)]},
			{"kind": "basic", "route": [Vector2i(1, 3), Vector2i(18, 3)]},
		],
	},
	{
		"id": "club",
		"name": "Club Street (Night)",
		"goal_label": "HOTEL",
		"theme": "club",
		"hint": "The Hongdae Guy King fires pickup lines. Dodge the hearts and reach your HOTEL.",
		"map": [
			"####################",
			"#S...#......#....#G#",
			"#.##.#.####.#.##.#.#",
			"#.#a.....#....#....#",
			"#.#.####.#.##.#.##.#",
			"#...#CC#.#.b....#..#",
			"###.#.##.####.#.##.#",
			"#n.......#....#....#",
			"#.####.#.#.##.#.##.#",
			"####################",
		],
		"enemies": [
			{"kind": "boss", "route": [Vector2i(16, 3)]},
			{"kind": "basic", "route": [Vector2i(3, 3), Vector2i(8, 3)]},
			{"kind": "basic", "route": [Vector2i(1, 7), Vector2i(8, 7)]},
			{"kind": "dasher", "route": [Vector2i(6, 1), Vector2i(11, 1)]},
			{"kind": "basic", "route": [Vector2i(15, 7), Vector2i(18, 7)]},
		],
	},
]

static func count() -> int:
	return STAGES.size()

static func get_stage(index: int) -> Dictionary:
	return STAGES[clampi(index, 0, STAGES.size() - 1)]
