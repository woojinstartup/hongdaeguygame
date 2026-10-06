class_name HEDialogue
extends RefCounted
## Dialogue battle: the Hongdae guy delivers a pickup line, the player picks a reply.
## witty -> win the round; risky -> he follows up (fail after the last round);
## evasive -> chance to slip away, otherwise he follows up. Timeout = fail.

const MAX_ROUNDS := 3
const ROUND_TIME := 7.0
const EVASIVE_CHANCE := 0.55
const BOSS_EVASIVE_CHANCE := 0.35

const OPENERS := {
	"basic": [
		{"line": "Are you open-minded?", "options": [
			["witty", "No. I'm closed. Like a store at 3 AM."],
			["risky", "What do you mean by that?"],
			["evasive", "*Pretend to read the subway map*"]]},
		{"line": "Do you live alone?", "options": [
			["witty", "I live with four bodyguards and a goose."],
			["risky", "Why do you ask?"],
			["evasive", "*Fake a phone call in Finnish*"]]},
		{"line": "You are so beautiful. Coffee?", "options": [
			["witty", "I only drink coffee with people who don't ask that."],
			["risky", "Maybe... where?"],
			["evasive", "*Point behind him and walk away*"]]},
		{"line": "Where are you from? I love foreigner.", "options": [
			["witty", "From the 'Not Interested' region."],
			["risky", "Canada. Why?"],
			["evasive", "*Nod politely and speed-walk*"]]},
	],
	"dasher": [
		{"line": "What's your Instagram?", "options": [
			["witty", "@not_today_hongdae. It's private. Forever."],
			["risky", "Why do you want it?"],
			["evasive", "*Show phone: 0% battery*"]]},
		{"line": "Can I get your KakaoTalk?", "options": [
			["witty", "Sorry, I only talk via carrier pigeon."],
			["risky", "I don't really use Kakao..."],
			["evasive", "*Type random numbers and walk off*"]]},
	],
	"photo": [
		{"line": "Let me take your photo! Very pretty!", "options": [
			["witty", "Sure. Here's a photo of me leaving."],
			["risky", "Uh... okay, just one?"],
			["evasive", "*Cover face with tourist map*"]]},
		{"line": "You look like a model. Instagram model?", "options": [
			["witty", "Yes. I model 'walking away'."],
			["risky", "Haha, really? You think so?"],
			["evasive", "*Blind him with the flash*"]]},
	],
	"trio": [
		{"line": "Hey! My friends want to say hi!", "options": [
			["witty", "Tell your friends I said bye."],
			["risky", "Hi... all of you?"],
			["evasive", "*Duck into the crowd*"]]},
		{"line": "We are three. You are one. Drink together?", "options": [
			["witty", "Great math. Here's more: zero chance."],
			["risky", "Just one drink...?"],
			["evasive", "*Pretend your friend is waving*"]]},
	],
	"boss": [
		{"line": "I am the Hongdae Guy King. Are you... OPEN-MINDED?", "options": [
			["witty", "My mind is open. My schedule is closed."],
			["risky", "King of what, exactly?"],
			["evasive", "*Throw a hotteok and run*"]]},
	],
}

const FOLLOW_UPS := {
	"default": [
		{"line": "Ah, you know... open mind-eu. Korean culture experience?", "options": [
			["witty", "I already experienced it. It's you. Bye."],
			["risky", "What kind of culture?"],
			["evasive", "*Get very interested in a tteokbokki stall*"]]},
		{"line": "My apartment has a very nice view. Netflix?", "options": [
			["witty", "My hotel has a nicer view: you, leaving."],
			["risky", "What would we watch?"],
			["evasive", "*Join the nearest busking crowd*"]]},
		{"line": "Just 5 minutes! I teach you Korean!", "options": [
			["witty", "I know one word already: 'Annyeong'. Bye."],
			["risky", "Five minutes... teach me what?"],
			["evasive", "*Sprint toward a taxi*"]]},
	],
	"boss": [
		{"line": "Every foreigner says yes to the King. Club? VIP table?", "options": [
			["witty", "Your VIP table is a table for one."],
			["risky", "VIP? What's included?"],
			["evasive", "*Call a taxi very loudly*"]]},
		{"line": "I have the newest iPhone. Three cameras. For you.", "options": [
			["witty", "Use all three to film me leaving."],
			["risky", "Okay, that IS a nice phone..."],
			["evasive", "*Hide behind a street food cart*"]]},
	],
}

var kind := "basic"
var round_index := 1
var wins := 0
var wins_needed := 1
var current: Dictionary = {}
var options: Array = []
var time_left := ROUND_TIME
var finished := false
var outcome := ""
var _rng := RandomNumberGenerator.new()

func start(enemy_kind: String, seed_value: int = -1) -> void:
	kind = enemy_kind if OPENERS.has(enemy_kind) else "basic"
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	round_index = 1
	wins = 0
	wins_needed = 2 if kind == "boss" else 1
	finished = false
	outcome = ""
	_load_line(OPENERS[kind])

func _load_line(pool: Array) -> void:
	current = pool[_rng.randi_range(0, pool.size() - 1)]
	options = []
	for option: Array in current["options"]:
		options.append({"kind": option[0], "text": option[1]})
	# Shuffle so the witty answer is not always first.
	for i: int in range(options.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = options[i]
		options[i] = options[j]
		options[j] = tmp
	time_left = ROUND_TIME

func line() -> String:
	return str(current.get("line", ""))

func tick(delta: float) -> Dictionary:
	if finished:
		return {}
	time_left -= delta
	if time_left <= 0.0:
		return _finish("fail", "Too slow! He keeps talking... and talking.")
	return {}

## roll: optional deterministic 0..1 value for evasive checks (tests).
func choose(index: int, roll: float = -1.0) -> Dictionary:
	if finished or index < 0 or index >= options.size():
		return {}
	var picked: Dictionary = options[index]
	match str(picked["kind"]):
		"witty":
			wins += 1
			if wins >= wins_needed:
				return _finish("escape", "Burn! He is speechless. You walk away.")
			return _next_round("He staggers... but the King keeps going!")
		"evasive":
			var chance := BOSS_EVASIVE_CHANCE if kind == "boss" else EVASIVE_CHANCE
			var value := roll if roll >= 0.0 else _rng.randf()
			if value < chance:
				return _finish("escape", "Smooth. You slipped away.")
			return _next_round("He follows you. Persistent...")
		_:
			return _next_round("Big mistake. Now he thinks you're interested.")

func _next_round(message: String) -> Dictionary:
	if round_index >= MAX_ROUNDS:
		return _finish("fail", "He won't stop. You lose your cool (and a life).")
	round_index += 1
	_load_line(FOLLOW_UPS["boss" if kind == "boss" else "default"])
	return {"result": "continue", "message": message}

func _finish(result: String, message: String) -> Dictionary:
	finished = true
	outcome = result
	return {"result": result, "message": message}

func index_of_kind(option_kind: String) -> int:
	for i: int in options.size():
		if options[i]["kind"] == option_kind:
			return i
	return -1
