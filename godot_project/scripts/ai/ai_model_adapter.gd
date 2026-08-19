extends RefCounted
class_name AiModelAdapter

## AiModelAdapter：模型适配器抽象层（不绑定当前训练产物格式）。
##
## 设计目的（对应计划 external-adapter）：
## - 让不同模型实现同一套“观察 -> 决策/动作提交”接口。
## - 让 MCP / 外部策略在 protocol 层只依赖 observation/action/result，
##   不关心底层用 ranking、ONNX、还是其它方法做决策。
##
## 当前仓尚未真正接入 ONNX 推理，所以本文件提供“接口骨架 + 类型注释”。
## 后续接入时，只需要新增一个 adapter（例如 OnnxCpuAdapter），
## 实现本接口并在 seat controller / MCP runtime 中替换 adapter 实例即可。


func controller_type() -> String:
	## 对应 `AI_MCP_PROTOCOL.md` 的 controller 字段：
	## - "human" / "onnx" / "llm" / "legacy_ai"
	return "legacy_ai"


func is_ready() -> bool:
	return false


func model_bundle_hash() -> String:
	## 模型包哈希摘要，用于开局握手三次核对。
	return ""


## titan_pick（TITAN head）
## 输入：obs_titan_pick: number[21]
## 输出：{titan_index:int, accepted:bool}
func infer_titan_pick(_obs_titan_pick: Array) -> Dictionary:
	return {"accepted": false, "reason_key": "not_implemented"}


## ops（Ops head）
## 输入：obs_ops: number[64]，以及本席位 match_global embedding（由 match_global head 得到）
## 输出：{dispatch: Dictionary, accepted:bool}
func infer_ops(_obs_ops: Array, _obs_match_global: Array) -> Dictionary:
	return {"accepted": false, "reason_key": "not_implemented"}


## shop（Shop head）
## 输入：obs_shop: number[256]
## 输出：{shop_action: Dictionary, accepted:bool}
func infer_shop(_obs_shop: Array) -> Dictionary:
	return {"accepted": false, "reason_key": "not_implemented"}


## fit（Fit head）
## 输入：obs_fit: number[80]，宿主会对候选功能桶进行展开
## 输出：{fit_choice: Dictionary, accepted:bool}
func infer_fit(_obs_fit: Array) -> Dictionary:
	return {"accepted": false, "reason_key": "not_implemented"}


## place（Place head）
## 输入：obs_place: number[132]（逐场上格/逐场上子件）
## 输出：{place_choice: Dictionary, accepted:bool}
func infer_place(_obs_place: Array) -> Dictionary:
	return {"accepted": false, "reason_key": "not_implemented"}

