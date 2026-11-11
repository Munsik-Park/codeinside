open("full.bin")
val internal = cpg.method.isExternal(false).filterNot(_.name.startsWith("<")).l
val byName = internal.groupBy(_.name).filter(_._2.size == 1).values.map(_.head).toList
println("UNIQUE_TOP_CALLED")
byName.map(m => (m.fullName, m.callIn.size, m.callOut.size)).filter(_._1.startsWith("core/")).sortBy(-_._2).take(10).foreach(println)
println("SUBPROCESS_CALLS")
cpg.call.methodFullName(".*subprocess.*").map(c => (c.methodFullName, c.method.fullName, c.lineNumber.getOrElse(-1))).l.take(15).foreach(println)
