using Base.Collections

type EventID
  time :: Float64
  priority :: Bool
  id :: Uint16
end

type Event
  callbacks :: Set
  ev_id :: EventID
  value
  function Event()
    ev = new()
    ev.callbacks = Set{Function}()
    return ev
  end
end

typealias Timeout Event

type Process
  name :: ASCIIString
  task :: Task
  target :: Event
  ev :: Event
  execute :: Function
  function Process(name::ASCIIString, task::Task)
    proc = new()
    proc.name = name
    proc.task = task
    proc.ev = Event()
    return proc
  end
end

type Environment
  now :: Float64
  heap :: PriorityQueue
  eid :: Uint16
  active_proc :: Process
  function Environment(initial_time::Float64=0.0)
    env = new()
    env.now = initial_time
    # Problem with PriorityQueue in julia v0.4
    # env.heap = PriorityQueue{Event, EventID}()
    env.heap = PriorityQueue()
    env.eid = 0
    return env
  end
end

type EmptySchedule <: Exception end

function Timeout(env::Environment, delay::Float64)
  ev = Event()
  schedule(env, ev, delay, "timeout")
  return ev
end

function Process(env::Environment, name::ASCIIString, func::Function, args...)
  proc = Process(name, Task(()->func(env, args...)))
  proc.execute = (env, ev)->execute(env, ev, proc)
  ev = Event()
  push!(ev.callbacks, proc.execute)
  schedule(env, ev, "execute")
  proc.target = ev
  return proc
end

function show(io::IO, ev::Event)
  print(io, "Event $(ev.ev_id.id)")
end

function show(io::IO, proc::Process)
  print(io, "Process $(proc.name)")
end

function now(env::Environment)
  return env.now
end

function add(ev::Event, callback::Function)
  push!(ev.callbacks, callback)
end

function value(ev::Event)
  return ev.value
end

function active_process(env::Environment)
  return env.active_proc
end

function isless(a::EventID, b::EventID)
	return (a.time < b.time) || (a.time == b.time && a.priority > b.priority) || (a.time == b.time && a.priority == b.priority && a.id < b.id)
end

function triggered(ev::Event)
  return isdefined(ev, :value)
end

function schedule(env::Environment, ev::Event, priority::Bool, delay::Float64, value=nothing)
  env.eid += 1
  ev.ev_id = EventID(env.now + delay, priority, env.eid)
  env.heap[ev] = ev.ev_id
  ev.value = value
  return ev
end

function schedule(env::Environment, ev::Event, priority::Bool, value=nothing)
  schedule(env, ev, priority, 0.0, value)
end

function schedule(env::Environment, ev::Event, delay::Float64, value=nothing)
  schedule(env, ev, false, delay, value)
end

function schedule(env::Environment, ev::Event, value=nothing)
  schedule(env, ev, false, 0.0, value)
end

function succeed(env::Environment, ev::Event, value=nothing)
  schedule(env, ev, value)
end

function fail(env::Environment, ev::Event, exc::Exception)
  schedule(env, ev, exc)
end

function run(env::Environment)
  ev = Event()
  run(env, ev)
end

function run(env::Environment, at::Float64)
  ev = Event()
  schedule(env, ev, at)
  run(env, ev)
end

function run(env::Environment, until::Event)
  push!(until.callbacks, stop_simulate)
  try
    while true
      step(env)
    end
  catch exc
    if !isa(exc, EmptySchedule)
      rethrow(exc)
    end
  end
end

function step(env::Environment)
  if isempty(env.heap)
    throw(EmptySchedule())
  end
  ev = dequeue!(env.heap)
  env.now = ev.ev_id.time
  while !isempty(ev.callbacks)
    callback = pop!(ev.callbacks)
    callback(env, ev)
  end
end

function stop_simulate(env::Environment, ev::Event)
  throw(EmptySchedule())
end

function execute(env::Environment, ev::Event, proc::Process)
  env.active_proc = proc
  value = consume(proc.task, ev.value)
  if istaskdone(proc.task)
    schedule(env, proc.ev, value)
  end
end

function yield(env::Environment, ev::Event)
  env.active_proc.target = ev
  push!(ev.callbacks, env.active_proc.execute)
  value = produce(ev)
  if isa(value, Exception)
    throw(value)
  end
  return value
end

function yield(env::Environment, proc::Process)
  return yield(env, proc.ev)
end

function interrupt(env::Environment, proc::Process)
  if !istaskdone(proc.task)
    ev = Event()
    push!(ev.callbacks, proc.execute)
    schedule(env, ev, true, InterruptException())
    delete!(proc.target.callbacks, proc.execute)
  end
end
