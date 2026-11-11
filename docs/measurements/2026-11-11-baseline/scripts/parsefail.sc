// docs/plan.md 단계 3: 파싱에 실패한 파일이 그래프에 어떻게 남는지 확인한다.
open("full.bin")
val failed = List(
  "core/agent_harness/turns/turn_snapshot.py", "core/domain/memory/recall.py",
  "core/messages/runtime_message_types.py", "core/tool_framework/utils/tool_availability.py",
  "infrastructure/analytics/provider.py", "infrastructure/analytics/usage_context.py",
  "integrations/_relational.py", "surfaces/interactive_shell/session/connection_checks.py",
  "tools/interactive_shell/shell/output_capture.py")
failed.foreach { f =>
  val ms = cpg.method.filename(f).isExternal(false).name.l
  println(s"RESULT $f file_nodes=${cpg.file.nameExact(f).size} methods=${ms.size}")
}
