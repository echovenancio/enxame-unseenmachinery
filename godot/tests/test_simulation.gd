extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
var failures = 0

func check(condition: bool, message: String) -> void:
 if not condition:
  failures += 1
  printerr("FAIL: "+message)

func _init() -> void:
 run.call_deferred()

func run() -> void:
 var base = {"ants":1200,"humans":3,"species":0,"size":8.0,"seed":1977,"duration":240.0,"scenario":2,"behaviour":2}
 var a = Simulation.new()
 var b = Simulation.new()
 a.configure(base); b.configure(base)
 for tick in range(900):
  a.tick(); b.tick()
  check(a.conserved_population()==1200,"Population conserved at tick %d"%tick)
  check(a.alive==b.alive and a.contacts==b.contacts and a.exposures==b.exposures,"Deterministic seeded tick %d"%tick)
  for h in a.humans:
   check(is_finite(h.pos.x) and is_finite(h.pos.y),"Finite human position")
   check(a._inside(h.pos),"Human inside octagon")
  if failures:break
 print("CASE individual: ",a.summary())
 for w in a.weight: check(w<=1,"Individual agents remain individual after brushing")
 var big = Simulation.new()
 var conf = base.duplicate()
 conf.ants = 1000000; conf.humans = 4; conf.duration = 300.0
 big.configure(conf)
 check(big.agent_count<=Simulation.MAX_AGENTS,"Agent budget")
 var begin = Time.get_ticks_usec()
 for tick in range(200):
  big.tick()
  check(big.conserved_population()==1000000,"Cohort population conserved")
  check(big.alive>=0 and big.crushed>=0,"Nonnegative counts")
 var elapsed_us = Time.get_ticks_usec()-begin
 print("BENCHMARK million ants 4 humans: ",elapsed_us/200.0/1000.0," ms/tick, ",big.summary())
 conf.ants = 10000000
 big.configure(conf)
 check(big.population==10000000,"Ten million population accepted")
 check(big.agent_count==Simulation.MAX_AGENTS,"Ten million bounded agent budget")
 begin = Time.get_ticks_usec()
 for tick in range(250):
  big.tick()
  check(big.conserved_population()==10000000,"Ten million population conserved at tick %d"%tick)
  check(big.alive+big.crushed+big.escaped==10000000,"Ten million summary conservation")
 print("BENCHMARK ten million ants: ",(Time.get_ticks_usec()-begin)/250000.0," ms/tick, ",big.summary())
 check(not big._inside(Vector2(big.radius*0.8,big.radius*0.8)),"Regular octagon corner boundary")
 conf.ants = 10000001; big.configure(conf)
 check(big.population==Simulation.MAX_POPULATION,"Population upper bound")
 var escape = Simulation.new()
 conf.ants = 400; conf.humans = 1; conf.escape = true; conf.size = 4.0; conf.behaviour = 3; conf.scenario = 1; conf.duration = 300.0
 escape.configure(conf)
 for tick in range(1200):escape.tick()
 check(escape.escaped>0,"Boundary escape enabled")
 check(escape.conserved_population()==400,"Escaped population conserved")
 print("CASE boundary: ",escape.summary())
 var cold = Simulation.new(); var warm = Simulation.new()
 conf.temperature = 0.0; cold.configure(conf)
 conf.temperature = 28.0; warm.configure(conf)
 check(cold.activity<warm.activity,"Cold lowers ant activity")
 for species in range(Simulation.PROFILES.size()):
  conf.species = species; conf.ants = 300; conf.humans = 2; conf.escape = false; conf.behaviour = 2
  var s = Simulation.new();s.configure(conf)
  for tick in range(300):s.tick()
  check(s.conserved_population()==300,"Species population conservation")
  print("CASE species ",species,": ",s.summary())
 var empty = Simulation.new()
 empty.configure({"ants":0,"humans":0})
 check(empty.finished and empty.conserved_population()==0,"Empty arena terminates")
 empty.configure({"ants":50,"humans":0})
 check(empty.finished and empty.alive==50,"No humans terminates")
 empty.configure({"ants":0,"humans":1})
 check(empty.finished,"No ants terminates")
 var bounded = Simulation.new()
 bounded.configure({"ants":40,"humans":1,"duration":1.0})
 for tick in range(20):bounded.tick()
 check(bounded.finished and bounded.elapsed<=1.1,"Time limit terminates")
 print("TEST_RESULT failures=",failures)
 quit(1 if failures else 0)
