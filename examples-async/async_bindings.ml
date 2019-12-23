open Core
open Async
open Python_lib
open Python_lib.Let_syntax

let _scheduler_thread = ref None

let caml_start_scheduler () =
  Clock_ns.every (Time_ns.Span.of_sec 0.4) (fun () ->
    Core.printf "current time: %s\n%!" (Time_ns.now () |> Time_ns.to_string));
  never_returns (Scheduler.go ())

let register_module ~module_name =
  Callback.register "caml_start_scheduler" caml_start_scheduler;
  let modl = Py_module.create module_name in
  Py_module.set_unit
    modl
    "every"
    [%map_open
      let span = positional "span" string ~docstring:"the interval at which to run the function"
      and fn = positional "fn" pyobject ~docstring:"the function to run" in
      Core.printf "start every %s\n%!" (Py.Type.get fn |> Py.Type.name);
      ignore (Py.Object.call_function_obj_args fn [||] : pyobject);
      Clock_ns.every (Time_ns.Span.of_string span) (fun () ->
        Stdio.printf "here %s\n%!" (Time_ns.now () |> Time_ns.to_string));
        (* ignore (Py.Callable.to_function fn [||] : pyobject)) *)
    ]
    ~docstring:"Executes a python closure regularly."
