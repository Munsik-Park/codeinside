// docs/plan.md 단계 4: Serena와 Joern이 갈린 close 호출 지점에서 Joern이 호출을 어디로 이었는지 본다.
open("full.bin")
val sites = List(
  ("infrastructure/turn_host/unattended_session.py", 71),
  ("surfaces/cli/ask/service.py", 389),
  ("surfaces/interactive_shell/runtime/session_shutdown.py", 43),
  ("surfaces/interactive_shell/runtime/session_shutdown.py", 72),
  ("gateway/core/prompt_intake/worker.py", 225),
  ("infrastructure/skills_registry/client.py", 126)
)
for ((f, l) <- sites) {
  cpg.call.nameExact("close").where(_.file.nameExact(f)).filter(_.lineNumber.contains(l)).l.foreach { c =>
    println(s"SITE $f:$l\tmethodFullName=${c.methodFullName}\tcallee=${c.callee.fullName.l.sorted.mkString(",")}")
  }
}
println("CLOSE_CALLS_TOTAL " + cpg.call.nameExact("close").size)
println("CLOSE_CALLS_LINKED_TO_SessionManager " + cpg.method.fullNameExact("core/agent_harness/session/lifecycle.py:<module>.SessionManager.close").callIn.size)
