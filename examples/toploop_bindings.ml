(* This module provides bindings to the ocaml toplevel.
   This allows one to run ocaml blocks from python and exchange values between the
   ocaml and python runtimes.

   The toplevel module returns [Obj.t] object so we rely heavily on [Obj.repr]
   to get some typed values out of it. This should be type-safe as we also
   ask the toplevel loop to check the types.
*)
module F = Format
open Base
open Python_lib
open Python_lib.Let_syntax
module Typerep = Typerep_lib.Std.Typerep

let is_initialized = ref false

let maybe_initialize () =
  if not !is_initialized
  then (
    is_initialized := true;
    Clflags.debug := true;
    Clflags.verbose := false;
    Warnings.parse_options false "-58";
    Location.formatter_for_warnings := F.err_formatter;
    Toploop.set_paths ();
    !Toploop.toplevel_startup_hook ();
    (* required for side-effect initialization in Topdirs *)
    Toploop.initialize_toplevel_env ();
    let lexing = Lexing.from_string "type pyobject;;" in
    let phrases = !Toploop.parse_use_file lexing in
    List.iter phrases ~f:(fun phrase ->
      let ok = Toploop.execute_phrase false F.std_formatter phrase in
      ignore (ok : bool));
    Py_typerep.Named_types.register_exn
      ~name:"pyobject"
      ~ocaml_type:"pyobject"
      ~python_to_ocaml:Fn.id
      ~ocaml_to_python:Fn.id)
;;

let exn_to_string exn ~code =
  let print_loc _ _report ppf (location : Location.t) =
    F.fprintf
      ppf
      "ocaml evaluation error on lines %d:%d to %d:%d\n"
      location.loc_start.pos_lnum
      location.loc_start.pos_cnum
      location.loc_end.pos_lnum
      location.loc_end.pos_cnum
  in
  let default_printer = Location.default_report_printer () in
  let report report_printer report ppf x =
    let location = report.Location.main.loc in
    F.pp_print_newline ppf ();
    let min_line_number = location.loc_start.pos_lnum - 5 in
    let max_line_number = location.loc_end.pos_lnum + 5 in
    String.rstrip code ~drop:(function
      | ' ' | '\r' | '\n' | '\t' -> true
      | _ -> false)
    |> String.split ~on:'\n'
    |> List.filter_mapi ~f:(fun lnum line ->
      let lnum = 1 + lnum in
      if min_line_number <= lnum && lnum <= max_line_number
      then (
        let marker =
          if location.loc_start.pos_lnum <= lnum
          && lnum <= location.loc_end.pos_lnum
          then ">"
          else " "
        in
        Some (Printf.sprintf "%s%3d: %s" marker lnum line))
      else None)
    |> String.concat ~sep:"\n"
    |> F.pp_print_string ppf;
    F.pp_print_newline ppf ();
    default_printer.Location.pp_main_txt report_printer report ppf x
  in
  let buffer = Buffer.create 256 in
  let formatter = F.formatter_of_buffer buffer in
  let report_printer () : Location.report_printer =
    { default_printer with
      Location.pp_main_loc = print_loc
    ; pp_submsg_loc = print_loc
    ; pp_main_txt = report
    }
  in
  Location.report_printer := report_printer;
  Location.report_exception formatter exn;
  Buffer.contents buffer
;;

let toploop_eval str ~verbose =
  try
    maybe_initialize ();
    let lexing = Lexing.from_string str in
    let phrases = !Toploop.parse_use_file lexing in
    List.iter phrases ~f:(fun phrase ->
      let ok = Toploop.execute_phrase verbose F.std_formatter phrase in
      ignore (ok : bool));
    F.pp_print_flush F.std_formatter ()
  with
  | Py.Err _ as err -> raise err
  | exn -> raise (Py.Err (SyntaxError, exn_to_string exn ~code:str))
;;

let toploop_eval_and_get typerep str =
  let eval_value (type a) (typerep : a Typerep.t) =
    toploop_eval
      ~verbose:false
      (Printf.sprintf "let out : %s = (%s);;" (Py_typerep.to_ocaml typerep) str);
    let path, _ = Env.lookup_value (Lident "out") !Toploop.toplevel_env in
    let obj = Toploop.eval_value_path !Toploop.toplevel_env path in
    Py_typerep.ocaml_to_python typerep (Caml.Obj.obj obj)
  in
  let (T typerep) = Py_typerep.parse typerep in
  eval_value typerep
;;

let rec of_type_expr : Types.type_expr -> Type.t =
  fun type_expr ->
  match type_expr.desc with
  | Tconstr (path, [], _) -> Atom (Path.last path)
  | Tconstr (path, [ td ], _) -> Apply (of_type_expr td, Path.last path)
  | Tconstr (path, _, _) ->
    raise
      (Py.Err
         ( SyntaxError
         , Printf.sprintf "unsupported type %s with multiple parameters" (Path.last path)
         ))
  | Tarrow ((Nolabel | Labelled _), td1, td2, _c) ->
    Arrow (of_type_expr td1, of_type_expr td2)
  | Tarrow (Optional _, _td1, _td2, _c) ->
    raise (Py.Err (SyntaxError, "optional arguments are not supported"))
  | Ttuple [ td1; td2 ] -> Tuple2 (of_type_expr td1, of_type_expr td2)
  | Ttuple [ td1; td2; td3 ] ->
    Tuple3 (of_type_expr td1, of_type_expr td2, of_type_expr td3)
  | Ttuple [ td1; td2; td3; td4 ] ->
    Tuple4 (of_type_expr td1, of_type_expr td2, of_type_expr td3, of_type_expr td4)
  | Ttuple [ td1; td2; td3; td4; td5 ] ->
    Tuple5
      ( of_type_expr td1
      , of_type_expr td2
      , of_type_expr td3
      , of_type_expr td4
      , of_type_expr td5 )
  | Ttuple _ ->
    raise (Py.Err (SyntaxError, Printf.sprintf "tuple with more than 5 arguments"))
  | Tvar _ -> Atom "pyobject"
  | Tlink td -> of_type_expr td
  | Tsubst td -> of_type_expr td
  | Tnil -> raise (Py.Err (SyntaxError, "unsupported type Tnil"))
  | Tvariant _ -> raise (Py.Err (SyntaxError, "unsupported type Tvariant"))
  | Tunivar _ -> raise (Py.Err (SyntaxError, "unsupported type Tunivar"))
  | Tpoly (_, _) -> raise (Py.Err (SyntaxError, "unsupported type Tpoly"))
  | Tpackage (_, _, _) -> raise (Py.Err (SyntaxError, "unsupported type Tpackage"))
  | Tobject (_, _) -> raise (Py.Err (SyntaxError, "unsupported type Tobject"))
  | Tfield (_, _, _, _) -> raise (Py.Err (SyntaxError, "unsupported type Tfield"))
;;

let toploop_eval_and_get_no_type str =
  toploop_eval ~verbose:false (Printf.sprintf "let out = (%s);;" str);
  let path, value_description = Env.lookup_value (Lident "out") !Toploop.toplevel_env in
  let obj = Toploop.eval_value_path !Toploop.toplevel_env path in
  let (T typerep) = of_type_expr value_description.val_type |> Py_typerep.of_type in
  Py_typerep.ocaml_to_python typerep (Caml.Obj.obj obj)
;;

let register_module ~module_name =
  let modl = Py_module.create module_name in
  Py_module.set_unit
    modl
    "eval"
    [%map_open
      let str = positional "str" string ~docstring:"ocaml code to run"
      and verbose = keyword "verbose" bool ~default:false ~docstring:"verbose" in
      toploop_eval str ~verbose]
    ~docstring:
      {|
    Evaluates an ocaml expression.

    This takes a argument a string containing some ocaml code. This string is parsed,
    typechecked and evaluated in a toplevel.
    The global variable scope is shared between multiple calls to this function.
      |};
  Py_module.set_function
    modl
    "get"
    (function
      | [| str |] -> Py.String.to_string str |> toploop_eval_and_get_no_type
      | [| typerep; str |] ->
        toploop_eval_and_get (Py.String.to_string typerep) (Py.String.to_string str)
      | _ -> raise (Py.Err (SyntaxError, "expected one or two arguments")))
    ~docstring:
      {|
    Evaluates an ocaml expression and returns the result as a python object.

    This takes one or two arguments. When two arguments are given, the first
    one is a type representation of the object to be transfered from ocaml to
    python. The second one is a string containing some ocaml code. This string
    is parsed, typechecked (its type has to match the type argument) and
    evaluated in a toplevel in the same way it is when running eval.

    Supported types can involve bool, int, string, float, list, option,
    only a single arrow is allowed in which case a function is returned.
    Examples of types would be:
        - int
        - unit -> string
        - (string * int option) list -> string * string

    Returns:
        A python object which type depends on the type argumnent.
    |};
  Py_module.set_unit
    modl
    "add_topdir"
    [%map_open
      let dir = positional "dir" string ~docstring:"directory to add" in
      if !is_initialized then failwith "can only add directories before initialization.";
      Topdirs.dir_directory dir]
    ~docstring:
      {|
    Adds a new top-level directory in the cmi search path.

    This can only be executed before the first call to eval or dir. Otherwise an exception
    is raised.
    |};
  Py_module.set_unit
    modl
    "add_named_type"
    [%map_open
      let name = positional "name" string ~docstring:"type name"
      and ocaml_type = positional "ocaml_type" string ~docstring:"ocaml type" in
      Py_typerep.register_named_type ~name ~ocaml_type]
    ~docstring:
      {|
    Registers an ocaml type so that it can be transfered to python in a caspule.
    |}
;;
