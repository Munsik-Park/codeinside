// docs/plan.md 단계 3: 프런트엔드가 만든 그래프를 importCpg로 올리는 시간 (default overlay 적용 포함)
def t[A](label: String)(f: => A): A = {
  val s = System.nanoTime(); val r = f
  println(f"TIME $label%s ${(System.nanoTime() - s) / 1e6}%.1f ms"); r
}
if (workspace.project("full.bin").isDefined) delete("full.bin")
t("importCpg") { importCpg("/var/lib/joern/cpg/full.bin") }
println("OVERLAYS " + cpg.metaData.overlays.l)
println("FILES " + cpg.file.size + " METHODS " + cpg.method.size + " CALLS " + cpg.call.size)
