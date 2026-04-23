#!/bin/bash
# 运行所有 headless 场景测试（包装层）
# 唯一权威入口：test_runner.tscn + scene_registry.json
# 用法：bash tests/run_scenarios.sh [--path PROJECT_PATH]

GODOT=${GODOT:-godot}
PROJECT_PATH="$(cd "$(dirname "$0")/.." && pwd)"

echo ""
echo "════════════════════════════════════════"
echo "  HEADLESS REGRESSION"
echo "  Entry: tests/test_runner.tscn"
echo "  Source: tests/scene_registry.json"
echo "════════════════════════════════════════"
echo ""

$GODOT --headless --path "$PROJECT_PATH" --scene res://tests/test_runner.tscn
exit $?
