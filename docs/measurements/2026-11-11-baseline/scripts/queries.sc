// docs/plan.md 단계 3: 질의 응답 시간. 각 질의를 두 번 돌려 첫 실행과 두 번째 실행을 함께 남긴다.
def t[A](label: String)(f: => A): A = {
  val s = System.nanoTime(); val r = f
  println(f"TIME $label%s ${(System.nanoTime() - s) / 1e6}%.1f ms"); r
}
t("open") { open("full.bin") }
println("OVERLAYS " + cpg.metaData.overlays.l)

val evidence = "core/domain/types/evidence.py:<module>.record_evidence_entry"
val retry    = "core/llm/shared/llm_retry.py:<module>.maybe_raise_credit_exhausted"
val gitFn    = ".github/ci/git_changes.py:<module>.git"

for (i <- 1 to 2) {
  val q1 = t(s"Q1 callers(record_evidence_entry) run$i") { cpg.method.fullNameExact(evidence).callIn.method.fullName.dedup.l }
  println(s"RESULT Q1 ${q1.size}")
  val q2 = t(s"Q2 callees(maybe_raise_credit_exhausted) run$i") { cpg.method.fullNameExact(retry).callOut.name.dedup.l }
  println(s"RESULT Q2 ${q2.size}")
  val q3 = t(s"Q3 callers-depth2(record_evidence_entry) run$i") { cpg.method.fullNameExact(evidence).callIn.method.callIn.method.fullName.dedup.l }
  println(s"RESULT Q3 ${q3.size}")
  val q4 = t(s"Q4 flow git.param->check_output.arg run$i") {
    def source = cpg.method.fullNameExact(gitFn).parameter
    def sink = cpg.call.methodFullNameExact("subprocess.py:<module>.check_output").argument
    sink.reachableByFlows(source).l
  }
  println(s"RESULT Q4 ${q4.size}")
  val q5 = t(s"Q5 flow callers.param->record_evidence_entry.arg run$i") {
    def source = cpg.method.fullNameExact(evidence).callIn.method.parameter
    def sink = cpg.method.fullNameExact(evidence).callIn.argument
    sink.reachableByFlows(source).l
  }
  println(s"RESULT Q5 ${q5.size}")
}
