// docs/plan.md 단계 4: 흔한 이름 비교 대상 고르기.
// 레포 안에 정의가 여럿(서로 다른 클래스)인 메서드 이름을 정의 수, 이름 기준 호출 지점 수와 함께 뽑는다.
open("full.bin")
val internal = cpg.method.isExternal(false).filterNot(_.name.startsWith("<")).l
// 클래스 메서드만: fullName이 "<파일>:<module>.<Class>.<name>" 꼴
val inClass = internal.filter { m => m.fullName.split(":<module>.", 2).lift(1).exists(_.count(_ == '.') == 1) }
val groups = inClass.groupBy(_.name).filter(_._2.map(_.fullName).distinct.size >= 3)
println("CANDIDATES name\tdefs\tcallsites_by_name\tcallIn_first_def")
groups.toList.map { case (n, ms) =>
  (n, ms.map(_.fullName).distinct.size, cpg.call.nameExact(n).size, ms.head.callIn.size)
}.sortBy(x => (-x._2, x._1)).take(60).foreach { case (n, d, c, ci) => println(s"CAND $n\t$d\t$c\t$ci") }
