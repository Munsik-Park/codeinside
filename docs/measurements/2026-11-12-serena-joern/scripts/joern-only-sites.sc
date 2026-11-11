// docs/plan.md 단계 4: SessionManager.close에 이어진 호출 지점 전부의 methodFullName과 후보 수를 본다.
open("full.bin")
cpg.method.fullNameExact("core/agent_harness/session/lifecycle.py:<module>.SessionManager.close").callIn
  .map(c => (c.method.filename, c.lineNumber.getOrElse(-1), c.methodFullName, c.callee.size))
  .l.sortBy(x => (x._1, x._2))
  .foreach { case (f, l, mfn, n) => println(s"SITE $f:$l\tmethodFullName=$mfn\tcallees=$n") }
