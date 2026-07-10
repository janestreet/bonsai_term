open! Core
open Async

(** [Bonsai_term] is a library that lets you build OCaml TUIs (terminal UIs) using Bonsai.
    This is kind of like [bonsai_web], but for terminals.

    To learn how to use this library, you can read this MLI and/or look at some examples
    under [lib/bonsai_term_examples].

    To learn how to use bonsai, you can read our docs at `lib/bonsai/docs`, do the bonsai
    teach in. *)

include module type of Geom

(** [View.t] and [Attr.t] are ~analogous to [bonsai_web]'s [Node.t] and [Attr.t].

    You can use these to construct the "view" of your TUI. *)

module View = View
module Attr = Attr

(** When your users type a key, click, scroll, ... [bonsai_term] will give you an
    [Event.t].

    You can "react" to events by implementing a "handler" function of type
    [Event.t -> unit Effect.t]. *)
module Event = Event

(** [View.With_handler.t] is a helper type alias that contains your "view" and a
    "handler".

    {[
      type View.With_handler.t = view:View.t * handler:(Event.t -> unit Effect.t)
    ]}

    {v
      - A [bonsai_web]  "app" is a function of type [local Bonsai.graph -> Vdom.Node.t Bonsai.t].
      - A [bonsai_term] "app" is a function of type [dimensions:Dimensions.t Bonsai.t -> local Bonsai.graph -> View.With_handler.t Bonsai.t].
    v}

    In [bonsai_web], the browser is responsible for feeding the right mouse/keyboard/...
    events to the "focused" element and calls the right "on_click"/"on_change"/...
    listener.

    In [bonsai_term], you, the app author are responsible for implementing the global
    "handler" function. Sadly, there isn't a "focused" textbox/"tab focus cycling" in
    [bonsai_term]. You, the app author are responsible for keeping track of "focus". *)

(** [Effect.t] is kind of like [bonsai_web]'s [Effect.t], with some terminal specific
    effects. *)
module Effect = Effect

module Mouse_reporting : sig
  (** Controls how much terminal mouse reporting is enabled. *)
  type t =
    | All_mouse_events
    (** Report ordinary mouse events and hover/motion events with no button pressed. *)
    | All_mouse_events_except_hover
    (** Report ordinary mouse events, but do not report hover/motion events with no button
        pressed. *)
    | No_mouse_events
    (** Disable terminal mouse reporting, allowing terminal-native mouse selection. *)
  [@@deriving sexp_of, equal]

  (** Dynamically control terminal mouse reporting.

      [All_mouse_events] enables ordinary mouse events and hover/motion events with no
      button pressed. [All_mouse_events_except_hover] enables ordinary mouse events but
      disables hover events. [No_mouse_events] disables terminal mouse reporting, which is
      important for allowing terminal-native text selection. *)
  val set_mouse_reporting : local_ Bonsai.graph -> (t -> unit Effect.t) Bonsai.t
end

(** [start] is will run your app. The [unit Deferred.t] is determined when the user hits
    [Ctrl-C]. If you would like an exit that is different from [Ctrl+C], please refer to
    [start_with_exit]

    [~target_frames_per_second] is the "framerate" that bonsai_term should attempt to
    follow. Defaults to 60, which makes each frame wait attempt to wait for ~16ms. If a
    frame took (> 0ms , but less than 16ms to render), it will wait for
    [ 16ms - time_taken ]. If a frame took [ >= 16ms ] to render, bonsai_term won't wait
    for the next frame.

    [~dispose] arranges for automatic {{!release} cleanup} of the terminal before the
    process terminates. The downside is that a reference to this terminal is retained
    until the program exits. Defaults to [false].

    [~nosig] additionally turns off signal delivery and flow control ({e isig} and
    {e ixon}) on input. Inhibits automatic handling of {e CTRL-\{C,Z,\,S,Q\}}. Defaults to
    [true].

    [~mouse] controls terminal mouse reporting. Defaults to
    [Mouse_reporting.All_mouse_events_except_hover]. Use
    [Mouse_reporting.All_mouse_events] to also receive hover/motion events, and
    [Mouse_reporting.No_mouse_events] to disable terminal mouse reporting so
    terminal-native text selection works normally.

    [~bpaste] activates bracketed paste reporting. Defaults to [true].

    [~time_source] is which async time source to use for time-keeping. Defaults to
    [wall_clock] though you can pass a custom time source for controlling time in tests.

    [~reader] and [~writer] by default default to the stdin reader and the stdout writer
    respectively. Bonsai_term will receive and parse input events from [reader] and write
    output events to [writer]. Use this if you would like to "redirect" the input/output
    that bonsai term uses.

    [for_mocking] allows you to "mock" the terminal environment of [bonsai_term]. Please
    refer to [Notty_async.For_mocking.t] for the specifics of what can be mocked. *)
val start
  :  ?dispose:bool
  -> ?nosig:bool
  -> ?mouse:Mouse_reporting.t
  -> ?bpaste:bool
  -> ?reader:Reader.t
  -> ?writer:Writer.t
  -> ?time_source:Async.Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> ?for_mocking:Notty_async.For_mocking.t
  -> (dimensions:Dimensions.t Bonsai.t
      -> local_ Bonsai.graph
      -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t)
  -> unit Async.Deferred.Or_error.t

(** [start_with_exit] is like [start] but allows you to customize _when_ to exit and also
    allows you to "return" something upon exiting.

    Unlike [start], this mode will _not_ exit by default when you press [Ctrl+C]. If you
    would like to exit when [Ctrl+C] is pressed you must intentionally schedule [exit] to
    occur when [Ctrl+C] is pressed in your app's handler. *)
val start_with_exit
  :  ?dispose:bool
  -> ?nosig:bool
  -> ?mouse:Mouse_reporting.t
  -> ?bpaste:bool
  -> ?reader:Reader.t
  -> ?writer:Writer.t
  -> ?time_source:Async.Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> ?for_mocking:Notty_async.For_mocking.t
  -> (exit:('exit -> unit Effect.t)
      -> dimensions:Dimensions.t Bonsai.t
      -> local_ Bonsai.graph
      -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t)
  -> 'exit Async.Deferred.Or_error.t

(** [start_with_exit_result] is like [start_with_exit] but instead of returning an
    [Or_error.t] when the incoming events pipe closes, it returns a [Result.t] that
    distinguishes between a normal exit (via [exit]) and the incoming events pipe being
    closed. This is useful when your app needs to know _why_ it stopped running. *)
val start_with_exit_result
  :  ?dispose:bool
  -> ?nosig:bool
  -> ?mouse:Mouse_reporting.t
  -> ?bpaste:bool
  -> ?reader:Reader.t
  -> ?writer:Writer.t
  -> ?time_source:Async.Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> ?for_mocking:Notty_async.For_mocking.t
  -> (exit:('exit -> unit Effect.t)
      -> dimensions:Dimensions.t Bonsai.t
      -> local_ Bonsai.graph
      -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t)
  -> ('exit, [ `Incoming_events_pipe_closed ]) Result.t Async.Deferred.Or_error.t

(** [start_with_driver] starts a Bonsai_term app in the background and gives you access to
    a [Driver.t]. This lets you the caller do things like:

    - Inspect the most recently drawn view with [Driver.prev_view].
    - Inject user-defined ['incoming] events with [Driver.send_incoming_event].

    You can "wait" for the bonsai term app to finish with [Driver.finished]. *)
val start_with_driver
  :  ?dispose:bool
  -> ?nosig:bool
  -> ?mouse:Mouse_reporting.t
  -> ?bpaste:bool
  -> ?reader:Reader.t
  -> ?writer:Writer.t
  -> ?time_source:Async.Time_source.t
  -> ?optimize:bool
  -> ?target_frames_per_second:float
  -> ?for_mocking:Notty_async.For_mocking.t
  -> get_view_and_handler:('result -> View.With_handler.t)
  -> handle_incoming:('result -> 'incoming -> unit Effect.t)
  -> (exit:('exit -> unit Effect.t)
      -> dimensions:Dimensions.t Bonsai.t
      -> local_ Bonsai.graph
      -> 'result Bonsai.t)
  -> ('result, 'exit, 'incoming) Driver.t Async.Deferred.Or_error.t

(** [Position] refers a specific point in the terminal.

    top-left terminal corner is [{ row = 0; column = 0}]

    [row] increases downward and [column] increases to the right. *)
module Position = Position

module Bonsai = Bonsai
module Cursor = Cursor
module Title = Title
module Driver = Driver

(** [stitch] is a tiny utility function that will "tuple up" a view and a handler bonsais
    into a single bonsai node. This is useful if you want to quickly turn some of these
    into a Bonsai.t for use inside of a [match%sub] or other Bonsai functions. *)
val stitch
  :  (view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t)
  -> (view:View.t * handler:(Event.t -> unit Effect.t)) Bonsai.t

(** [unstitch] is the inverse of [stitch]. *)
val unstitch
  :  (view:View.t * handler:(Event.t -> unit Effect.t)) Bonsai.t
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

module Private : sig
  module Driver = Driver
  module Frame_outcome = Frame_outcome

  module For_testing : sig
    type common_app_fn :=
      dimensions:Dimensions.t Bonsai.t
      -> local_ Bonsai.graph
      -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

    val make_app_exit_on_ctrlc
      :  common_app_fn
      -> (exit:(unit -> unit Effect.t) -> common_app_fn)

    val with_driver
      :  dispose:bool option
      -> nosig:bool option
      -> mouse:Mouse_reporting.t option
      -> bpaste:bool option
      -> reader:Reader.t option
      -> writer:Writer.t option
      -> time_source:Time_source.t option
      -> for_mocking:Notty_async.For_mocking.t option
      -> optimize:bool option
      -> target_frames_per_second:float option
      -> get_view_and_handler:('result -> View.With_handler.t)
      -> handle_incoming:('result -> 'incoming -> unit Effect.t)
      -> (exit:('exit -> unit Effect.t)
          -> dimensions:Dimensions.t Bonsai.t
          -> local_ Bonsai.graph
          -> 'result Bonsai.t)
      -> (('result, 'exit, 'incoming) Driver.t -> 'a Deferred.Or_error.t)
      -> 'a Deferred.Or_error.t

    val register_mouse_reporting_for_mock_tests
      :  (Bonsai.graph @ local -> 'a Bonsai.t)
      -> Bonsai.graph @ local
      -> 'a Bonsai.t
  end
end

module Captured_or_ignored = Captured_or_ignored

module Expert : sig
  module Write_to_tty = Write_to_tty
  module For_other_bonsais = Loop.For_other_bonsais
end
