// docs/plan.md 단계 4: 흔한 이름 후보마다 정의별 호출 지점 수(callIn)와 호출하는 함수 수(callIn.method)를 본다.
open("full.bin")
for (n <- List("_get_client", "record", "close", "resolve", "rotate")) {
  val defs = cpg.method.isExternal(false).nameExact(n).l
  println(s"NAME $n defs=${defs.size} callsites_by_name=${cpg.call.nameExact(n).size}")
  defs.sortBy(_.fullName).foreach { m =>
    println(s"  DEF ${m.fullName}\tcallIn=${m.callIn.size}\tcallers=${m.callIn.method.fullName.dedup.size}")
  }
}
