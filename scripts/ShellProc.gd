extends Node

# Generic subprocess runner with a worker thread (OS.execute blocks, so it
# must not run on the main thread). Used for curl (network) and arecord
# (microphone) on ArkOS, where the FRT runtime lacks TLS/mic support.
# PC builds keep Godot-native paths instead.

signal done(exit_code: int, output: String)

var _thread: Thread = null
var _args: PoolStringArray = []
var _output: String = ""
var _code: int = -1


func run(args: PoolStringArray, timeout_sec: int = 90) -> bool:
	if _thread != null and _thread.is_active():
		return false
	_args = args
	_output = ""
	_code = -1
	_thread = Thread.new()
	_thread.start(self, "_worker", timeout_sec)
	return true


func _worker(timeout_sec: int) -> void:
	var argv := _args
	var stdout: Array = []
	_code = OS.execute(argv[0], argv.slice(1, argv.size()), true, stdout, timeout_sec)
	var text := ""
	for line in stdout:
		text += String(line)
	_output = text


func poll_done() -> bool:
	return _thread != null and not _thread.is_active()


func collect() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func output_text() -> String:
	return _output


func exit_code() -> int:
	return _code
