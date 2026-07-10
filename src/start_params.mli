open! Core
open Bonsai
open Async

type ('result, 'exit, 'incoming, 'runtime_start_params) t = private
  { runtime_start_params : 'runtime_start_params
  ; optimize : bool
  ; target_frames_per_second : float
  ; time_source : Time_source.t
  ; get_view_and_handler : 'result -> View.With_handler.t
  ; handle_incoming : 'result -> 'incoming -> unit Effect.t
  ; app :
      exit:('exit -> unit Effect.t)
      -> dimensions:Geom.Dimensions.t Bonsai.t
      -> local_ Bonsai.graph
      -> 'result Bonsai.t
  }

val create_exn
  :  runtime_start_params:'runtime_start_params
  -> time_source:Time_source.t option
  -> optimize:bool option
  -> target_frames_per_second:float option
  -> get_view_and_handler:('result -> View.With_handler.t)
  -> handle_incoming:('result -> 'incoming -> unit Effect.t)
  -> app:
       (exit:('exit -> unit Effect.t)
        -> dimensions:Geom.Dimensions.t Bonsai.t
        -> local_ Bonsai.graph
        -> 'result Bonsai.t)
  -> ('result, 'exit, 'incoming, 'runtime_start_params) t
