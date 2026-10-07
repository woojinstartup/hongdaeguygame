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
		{"line": "Hello~ where are you from? ...Are you open mindeu?", "options": [
			["witty", "My mind is open. This conversation is closed."],
			["risky", "Open mindeu...? What do you mean?"],
			["evasive", "Sorry, I'm looking for Exit 9. Bye!"]]},
		{"line": "Excuse me~ do you libe alone?", "options": [
			["witty", "No. I live with my 6 brothers. They're all boxers."],
			["risky", "Why do you ask...?"],
			["evasive", "Hold on, my mom is calling. Hi mom!"]]},
		{"line": "Wow, you look like Taylor Swift. Really. I am serious.", "options": [
			["witty", "Then you know I'll write a song about this. A bad one."],
			["risky", "Wait, really? Taylor Swift?"],
			["evasive", "Oh look, Taylor Swift is behind you!"]]},
		{"line": "Don't you want Korean guy? Korean guy is very romantic.", "options": [
			["witty", "I want Korean BBQ. Not Korean guy."],
			["risky", "Romantic how...?"],
			["evasive", "Ne, ne, kamsahamnida~ okay bye!"]]},
	],
	"dasher": [
		{"line": "Hey hey hey! Insta ID? Give me your Insta!", "options": [
			["witty", "It's @not_interested. Private account."],
			["risky", "Uh... why do you need it?"],
			["evasive", "My phone is dead. Forever."]]},
		{"line": "Kakao-talk? You have Kakao? I add you. Quickly quickly!", "options": [
			["witty", "I only use carrier pigeon. Sorry."],
			["risky", "Okay... what's your ID?"],
			["evasive", "Sure! It's 010-0000-0000. Call me never."]]},
	],
	"photo": [
		{"line": "You are so beautiful. I am photographer. Picture-eu? Just one.", "options": [
			["witty", "Sure. Here's a picture of me saying no."],
			["risky", "Is this for a portfolio...?"],
			["evasive", "No photos, I'm in witness protection."]]},
		{"line": "Your style is very unique. Model? You want to be model?", "options": [
			["witty", "I model one thing: walking away."],
			["risky", "Model for what agency?"],
			["evasive", "Let me take YOUR picture first. Say cheese!"]]},
	],
	"trio": [
		{"line": "Hi~ where are you from? We are three. You are one. Drink together?", "options": [
			["witty", "Great math. Here's more: zero chance."],
			["risky", "Just one drink...?"],
			["evasive", "Wait, is that BTS busking over there?!"]]},
		{"line": "Your dance moves so cool! Club together? We know VIP!", "options": [
			["witty", "I wasn't dancing. I was escaping."],
			["risky", "VIP? Which club?"],
			["evasive", "Oh, my friend is waving at me. Gotta go!"]]},
	],
	"boss": [
		{"line": "I am Hongdae Guy King. Tell me honestly... are you OPEN MINDEU?", "options": [
			["witty", "My mind is open. My schedule is closed."],
			["risky", "King of what, exactly?"],
			["evasive", "Hey, a free hotteok! Catch!"]]},
	],
}
const FOLLOW_UPS := {
	"default": [
		{"line": "Ah~ you know... open mindeu. Korean culture experience?", "options": [
			["witty", "I already experienced it. It's you. Bye."],
			["risky", "What kind of culture?"],
			["evasive", "Sorry, I have a tteokbokki appointment."]]},
		{"line": "I have a cat. Very cute cat. You want to see my cat?", "options": [
			["witty", "Send your cat my regards. From very far away."],
			["risky", "...What's the cat's name?"],
			["evasive", "Shh, I love this song. Very loud. Can't hear you."]]},
		{"line": "Ramyeon meokgo gallae? ...It means, ramen at my house. Only ramen.", "options": [
			["witty", "I know what it means. The answer is also 'no'."],
			["risky", "Only ramen? Promise?"],
			["evasive", "My taxi is here! Annyeong!"]]},
		{"line": "So... you libe alone? Hotel? Airbnb? Which one?", "options": [
			["witty", "I live with Interpol. They're watching right now."],
			["risky", "Airbnb... why?"],
			["evasive", "I need to buy banana milk. Alone."]]},
	],
	"boss": [
		{"line": "Every foreigner say yes to the King. Club? VIP table? Open mindeu?", "options": [
			["witty", "Your VIP table is a table for one."],
			["risky", "VIP? What's included?"],
			["evasive", "TAXI! TAXI! Sorry, can't hear you, TAXI!"]]},
		{"line": "I have newest iPhone. Three camera. And I libe alone. Perfect, yes?", "options": [
			["witty", "Use all three cameras to film me leaving."],
			["risky", "Okay, that IS a nice phone..."],
			["evasive", "Is that your manager calling you? Bye!"]]},
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
