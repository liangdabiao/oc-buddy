extends Node

# Async client for the Xiaomi MiMo open platform (api.xiaomimimo.com/v1).
# LLM + ASR + TTS all use POST /v1/chat/completions with a `model` switch.
# Signals deliver results; HTTPRequest keeps the UI thread responsive.

signal chat_done(text)
signal asr_done(text)
signal tts_done(stream)
signal request_error(message)

const BASE_HOST := "https://api.xiaomimimo.com"
const MODEL_CHAT := "mimo-v2.6-flash"
const MODEL_ASR := "mimo-v2.5-asr"
const MODEL_TTS := "mimo-v2.5-tts"

var api_key: String = ""
var voice: String = "Chloe"
var busy := false
var pending_done := ""

var mode := "godot"                    # "godot" (HTTPRequest) | "curl" (subprocess)
var shell: Node = null
var _http: HTTPRequest
var _resp_path := "/tmp/kid_mimo_resp.json"
var _body_path := "/tmp/kid_mimo_body.json"
var _poll_timer: Timer = null


func _ready() -> void:
	if File.new().file_exists("/usr/bin/curl"):
		mode = "curl"                 # ArkOS/R36S: FRT lacks TLS, use curl subprocess
		shell = load("res://scripts/ShellProc.gd").new()
		shell.name = "Shell"
		add_child(shell)
		shell.connect("done", self, "_on_shell_done")
		_poll_timer = Timer.new()
		_poll_timer.wait_time = 0.25
		_poll_timer.connect("timeout", self, "_poll_shell")
		add_child(_poll_timer)
	else:
		_http = HTTPRequest.new()
		_http = HTTPRequest.new()
		_http.timeout = 60
		_http.use_threads = true
		_http.connect("request_completed", self, "_on_response")
		add_child(_http)


func _request(body: Dictionary, on_done: String) -> bool:
	if busy:
		return false
	busy = true
	pending_done = on_done
	if mode == "curl":
		var bf := File.new()
		bf.open(_body_path, File.WRITE)
		bf.store_string(JSON.print(body))
		bf.close()
		var args := PoolStringArray([
			"curl", "-s", "-m", "90", "-X", "POST", BASE_HOST + "/v1/chat/completions",
			"-H", "api-key: " + api_key,
			"-H", "Content-Type: application/json",
			"-d", "@" + _body_path,
			"-o", _resp_path,
		])
		return shell.run(args, 90)
	else:
		var headers := PoolStringArray([
			"api-key: %s" % api_key,
			"Content-Type: application/json",
		])
		var err := _http.request(BASE_HOST + "/v1/chat/completions", headers, false,
			HTTPClient.METHOD_POST, JSON.print(body))
		if err != OK:
			busy = false
			emit_signal("request_error", "HTTP request failed (%d)" % err)
			return false
		return true


func _poll_shell() -> void:
	if not busy:
		_poll_timer.stop()
		return
	if shell.poll_done():
		shell.collect()
		_poll_timer.stop()
		busy = false
		var f := File.new()
		if f.open(_resp_path, File.READ) != OK:
			emit_signal("request_error", "curl produced no response")
			return
		var text := f.get_as_text()
		f.close()
		_handle_response_text(text, pending_done)


func _on_response(_result: int, code: int, _headers: Array, body: PoolByteArray) -> void:
	busy = false
	_handle_response_text(body.get_string_from_utf8(), pending_done)


func _handle_response_text(text: String, on_done: String) -> void:
	var parsed = JSON.parse(text).result
	if parsed == null or not parsed is Dictionary:
		emit_signal("request_error", "bad response")
		return
	if parsed.has("error"):
		var e: Dictionary = parsed["error"]
		var msg := "%s (%s)" % [String(e.get("message", "unknown")), String(e.get("code", ""))]
		if String(e.get("code", "")) == "402":
			msg = "MiMo 账户余额不足，请充值后重试"
		emit_signal("request_error", msg)
		return
	var choices = parsed.get("choices", [])
	if choices.empty():
		emit_signal("request_error", "empty choices")
		return
	var msg: Dictionary = choices[0].get("message", {})

	match on_done:
		"chat":
			emit_signal("chat_done", String(msg.get("content", "")).strip_edges())
		"asr":
			var content = msg.get("content", "")
			var rtext := ""
			if content is String:
				rtext = content
			else:
				for part in content:
					rtext += String(part.get("text", ""))
			emit_signal("asr_done", rtext.strip_edges())
		"tts":
			var audio: Dictionary = msg.get("audio", {})
			var data := String(audio.get("data", ""))
			if data == "":
				emit_signal("request_error", "no audio in TTS response")
				return
			var stream := AudioStreamMP3.new()
			stream.data = Marshalls.base64_to_raw(data)
			emit_signal("tts_done", stream)


# ------------------------------------------------------------------ API ---

func chat(messages: Array, max_tokens: int = 200) -> bool:
	return _request({
		"model": MODEL_CHAT,
		"messages": messages,
		"stream": false,
		"thinking": {"enabled": false},
		"max_completion_tokens": max_tokens,
	}, "chat")


func asr(wav_path: String, language: String = "en") -> bool:
	var wav := File.new()
	if wav.open(wav_path, File.READ) != OK:
		emit_signal("request_error", "cannot open recording")
		return false
	var bytes := wav.get_buffer(wav.get_len())
	wav.close()
	return _request({
		"model": MODEL_ASR,
		"messages": [{"role": "user", "content": [
			{"type": "input_audio", "input_audio": {"data": "data:audio/wav;base64," + Marshalls.raw_to_base64(bytes)}},
		]}],
		"extra_body": {"asr_options": {"language": language}},
	}, "asr")


func tts(text: String, style_hint: String = "") -> bool:
	# sentence goes in the ASSISTANT role; style hints in the USER role
	var messages := []
	if style_hint != "":
		messages.append({"role": "user", "content": style_hint})
	messages.append({"role": "assistant", "content": text})
	return _request({
		"model": MODEL_TTS,
		"messages": messages,
		"audio": {"format": "mp3", "voice": voice},
	}, "tts")
