open Core
open Async
open Python_lib
open Python_lib.Let_syntax

let _scheduler_thread = ref None

let caml_start_scheduler () =
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
      Stdio.printf "start every %s\n%!" (Py.Type.get fn |> Py.Type.name);
      ignore (Py.Object.call_function_obj_args fn [||] : pyobject);
      Clock_ns.every (Time_ns.Span.of_string span) (fun () ->
        Stdio.printf "here\n%!";
        ignore (Py.Callable.to_function fn [||] : pyobject))]
    ~docstring:"Executes a python closure regularly."
