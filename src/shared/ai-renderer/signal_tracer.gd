extends RefCounted

## SignalTracer — 信号接收追踪器
## 职责：记录信号接收历史，供 SimulatedPlayer 的 wait_signal 机制查询。
## 为什么单独拆出：信号追踪是纯数据结构，与调度逻辑无耦合，单独测试更容易。

var _signal_chain: Array[Dictionary] = []
var signals_received: int = 0  ## 只读，供 get_interaction_summary 汇总


func record(signal_name: String, frame: int, args: Array = []) -> void:
	## 记录一条信号事件。由 SimulatedPlayer.record_signal() 调用。
	_signal_chain.append({
		"frame": frame,
		"signal": signal_name,
		"args": args,
	})
	signals_received += 1


func get_chain() -> Array:
	return _signal_chain.duplicate()
