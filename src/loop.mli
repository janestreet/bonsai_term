open! Core
open Bonsai
open Async

type common_app_fn :=
  dimensions:Geom.Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

type ('result, 'exit) app_with_exit_fn :=
  exit:('exit -> unit Effect.t)
  -> dimensions:Geom.Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> 'result Bonsai.t

type 'ret common_start_args :=
  ?dispose:bool
  -> ?nosig:bool
  -> ?mouse:Mouse_reporting_config.t
  -> ?bpaste:bool
  -> ?reader:Reader.t
  -> ?writer:Writer.t
  -> ?time_source:Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> ?for_mocking:Notty_async.For_mocking.t
  -> 'ret

val start : (common_app_fn -> unit Deferred.Or_error.t) common_start_args

val start_with_exit
  : ((exit:('exit -> unit Effect.t) -> common_app_fn) -> 'exit Deferred.Or_error.t)
      common_start_args

val start_with_exit_result
  : ((exit:('exit -> unit Effect.t) -> common_app_fn)
     -> ('exit, [ `Incoming_events_pipe_closed ]) Result.t Deferred.Or_error.t)
      common_start_args

val start_with_driver
  : (get_view_and_handler:('result -> View.With_handler.t)
     -> handle_incoming:('result -> 'incoming -> unit Effect.t)
     -> ('result, 'exit) app_with_exit_fn
     -> ('result, 'exit, 'incoming) Driver.t Deferred.Or_error.t)
      common_start_args

module For_testing : sig
  val make_app_exit_on_ctrlc
    :  common_app_fn
    -> (exit:(unit -> unit Effect.t) -> common_app_fn)

  val with_driver
    :  dispose:bool option
    -> nosig:bool option
    -> mouse:Mouse_reporting_config.t option
    -> bpaste:bool option
    -> reader:Reader.t option
    -> writer:Writer.t option
    -> time_source:Time_source.t option
    -> for_mocking:Notty_async.For_mocking.t option
    -> optimize:bool option
    -> target_frames_per_second:float option
    -> get_view_and_handler:('result -> View.With_handler.t)
    -> handle_incoming:('result -> 'incoming -> unit Effect.t)
    -> ('result, 'exit) app_with_exit_fn
    -> (('result, 'exit, 'incoming) Driver.t -> 'a Deferred.Or_error.t)
    -> 'a Deferred.Or_error.t
end

module For_other_bonsais : sig
  module Event_queue = Event_queue

  module Runtime : sig
    module type S = Runtime_intf.S
  end

  (** [start_with_custom_runtime] lets you run a bonsai term app with a "different"
      runtime backend. The "default" bonsai term backed is notty.

      This function is agnostic to the way that rendering is performed so you could render
      into things like an editor buffer or other rendering mechanisms. *)
  val start_with_custom_runtime
    :  runtime_start_params:'runtime_start_params
    -> (module Runtime_intf.S with type Start_params.t = 'runtime_start_params)
    -> ?time_source:Async.Time_source.t
    -> ?optimize:bool
    -> ?target_frames_per_second:float
    -> get_view_and_handler:('result -> View.With_handler.t)
    -> handle_incoming:('result -> 'incoming -> unit Ui_effect.t)
    -> (exit:('exit -> unit Ui_effect.t)
        -> dimensions:Geom.Dimensions.t t
        -> graph @ local
        -> 'result t)
    -> ('result, 'exit, 'incoming) Driver.t Deferred.Or_error.t
end
