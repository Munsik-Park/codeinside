// docs/plan.md 단계 4: Q1과 흔한 이름 메서드의 호출자를 Joern으로 뽑아 Serena와 비교한다.
// 3단계 queries.sc의 Q1과 같은 식(callIn.method)을 쓰고, 비교용으로 호출 지점 줄 번호도 남긴다.
def t[A](label: String)(f: => A): A = {
  val s = System.nanoTime(); val r = f
  println(f"TIME $label%s ${(System.nanoTime() - s) / 1e6}%.1f ms"); r
}
open("full.bin")
val targets = List(
  "Q1" -> "core/domain/types/evidence.py:<module>.record_evidence_entry",
  "C1" -> "core/agent_harness/session/lifecycle.py:<module>.SessionManager.close"
)
for ((q, fn) <- targets) {
  val callers = t(s"$q callers") { cpg.method.fullNameExact(fn).callIn.method.fullName.dedup.l }
  println(s"RESULT $q ${callers.size}")
  callers.sorted.foreach(c => println(s"CALLER $q\t$c"))
  cpg.method.fullNameExact(fn).callIn
    .map(c => (c.method.fullName, c.method.filename, c.lineNumber.getOrElse(-1), c.code.linesIterator.nextOption.getOrElse("")))
    .l.sortBy(x => (x._2, x._3))
    .foreach { case (m, f, l, code) => println(s"CALLSITE $q\t$f\t$l\t$m\t$code") }
}
