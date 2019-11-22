open Import
open Base

type t

val create : string -> t
val create_with_eval : name:string -> py_source:string -> t
val set_value : t -> string -> pyobject -> unit

val set_function
  :  t
  -> ?docstring:string
  -> string
  -> (pyobject array -> pyobject)
  -> unit

val set_function_with_keywords
  :  t
  -> ?docstring:string
  -> string
  -> (pyobject array -> (string, pyobject, String.comparator_witness) Map.t -> pyobject)
  -> unit

val set : t -> ?docstring:string -> string -> pyobject Defunc.t -> unit
val set_unit : t -> ?docstring:string -> string -> unit Defunc.t -> unit
val set_no_arg : t -> ?docstring:string -> string -> (unit -> pyobject) -> unit

(* Helper function to get keywords from a python object.
   When no keyword is present, null is used; otherwise a
   python dictionary with string key gets used.
*)

val keywords_of_python
  :  pyobject
  -> (string, pyobject, String.comparator_witness) Map.t Or_error.t

val docstring_with_params : ?docstring:string -> _ Defunc.t -> string
