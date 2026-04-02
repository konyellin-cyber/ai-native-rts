extends Node

## InputServer — TCP 连接管理（精简层）
## 职责：监听 TCP 端口，接受连接，把原始字节转发给 CommandRouter，把响应写回客户端。
## 命令解析 / 路由 / 输入注入 / UI 查询全部委托给 CommandRouter。
## 为什么这样拆：TCP 生命周期与业务逻辑解耦后，可单独替换传输层（如改用 WebSocket）。

var _server: TCPServer
var _connection: StreamPeerTCP
var _port: int = 5555
var _enabled: bool = false
var _router: RefCounted  ## CommandRouter


func setup(config: Dictionary = {}, sel_mgr: Node = null) -> void:
	_port = config.get("port", 5555)
	_enabled = config.get("enabled", true)
	if not _enabled:
		return
	var RouterScript = load("res://tools/ai-renderer/command_router.gd")
	_router = RouterScript.new()
	_router.setup(sel_mgr)
	_server = TCPServer.new()
	var err = _server.listen(_port, "127.0.0.1")
	if err == OK:
		print("[INPUT_SERVER] Listening on 127.0.0.1:%d" % _port)
	else:
		push_error("[INPUT_SERVER] Failed to listen on port %d: error %d" % [_port, err])
		_enabled = false


func _process(_delta: float) -> void:
	if not _enabled:
		return
	if _server and _server.is_connection_available():
		_connection = _server.take_connection()
	if _connection and _connection.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		if _connection.get_available_bytes() > 0:
			var raw = _connection.get_utf8_string(_connection.get_available_bytes())
			var response = _router.handle(raw.strip_edges())
			_connection.put_data((response + "\n").to_utf8_buffer())
			_connection.disconnect_from_host()
			_connection = null
