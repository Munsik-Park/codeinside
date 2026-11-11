def t[A](label: String)(f: => A): A = {
  val s = System.nanoTime(); val r = f
  println(f"TIME $label%s ${(System.nanoTime() - s) / 1e6}%.1f ms"); r
}
t("importCpg") { importCpg("/var/lib/joern/cpg/full.bin") }
println("OVERLAYS " + cpg.metaData.overlays.l)
println("FILES " + cpg.file.size + " METHODS " + cpg.method.size + " CALLS " + cpg.call.size)
println("TOP_CALLED")
cpg.method.isExternal(false).filterNot(_.name.startsWith("<")).map(m => (m.fullName, m.callIn.size)).l.sortBy(-_._2).take(15).foreach(println)
