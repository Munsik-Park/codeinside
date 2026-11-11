// docs/plan.md 단계 3: 파일 하나를 바꾼 뒤 다시 만든 그래프에 변경이 반영됐는지 확인한다.
def t[A](label: String)(f: => A): A = {
  val s = System.nanoTime(); val r = f
  println(f"TIME $label%s ${(System.nanoTime() - s) / 1e6}%.1f ms"); r
}
if (workspace.project("mod.bin").isDefined) delete("mod.bin")
t("importCpg mod") { importCpg("/var/lib/joern/cpg/mod.bin") }
println("RESULT probe_fn " + cpg.method.name("codeinside_incremental_probe").fullName.l)
println("RESULT probe_callers " + cpg.method.name("record_evidence_entry").callIn.method.name.l.count(_ == "codeinside_incremental_probe"))
delete("mod.bin")
