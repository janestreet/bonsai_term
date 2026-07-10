open! Core
open Bonsai
open Async

type ('result, 'exit, 'incoming) t =
  { clock : Bonsai.Time_source.t
  ; target_delay : Time_ns.Span.t
  ; term : 'incoming Term.t
  ; dimensions_manager : 'incoming State_management.For_dimensions.t
  ; exit_manager : 'exit State_management.For_exit.t
  ; driver : 'result Bonsai_driver.t
  ; get_view_and_handler : 'result -> View.With_handler.t
  ; handle_incoming : 'result -> 'incoming -> unit Effect.t
  ; time_source : Async.Time_source.t
  ; mutable prev_view : View.t option
  ; finished : ('exit, [ `Incoming_events_pipe_closed ]) Result.t Ivar.t
  }

let create
  (type runtime_start_params)
  ({ Start_params.runtime_start_params
   ; time_source
   ; optimize
   ; target_frames_per_second
   ; get_view_and_handler
   ; handle_incoming
   ; app
   } :
    ('result, 'exit, 'incoming, runtime_start_params) Start_params.t)
  (module Runtime : Runtime_intf.S with type Start_params.t = runtime_start_params)
  =
  let clock = State_management.For_clock.create time_source
  and target_delay = Time_ns.Span.of_sec (1.0 /. target_frames_per_second) in
  let%bind term = Term.create runtime_start_params (module Runtime) ~time_source () in
  let dimensions_manager = State_management.For_dimensions.create ~term
  and exit_manager = State_management.For_exit.create () in
  let driver =
    (fun (local_ graph) ->
      app
        ~exit:(fun exit -> State_management.For_exit.exit_effect exit_manager exit)
        ~dimensions:(State_management.For_dimensions.value dimensions_manager)
        graph)
    |> Cursor.register term
    |> Title.register term
    |> Mouse_reporting.register term
    |> Write_to_tty.register term
    |> Bonsai_driver.create
         ~optimize
         ~time_source:clock
         ~instrumentation:(Bonsai_driver.Instrumentation.default_for_test_handles ())
  in
  let finished = Ivar.create () in
  let driver =
    { clock
    ; target_delay
    ; term
    ; dimensions_manager
    ; exit_manager
    ; driver
    ; get_view_and_handler
    ; handle_incoming
    ; time_source
    ; prev_view = None
    ; finished
    }
  in
  return driver
;;

let compute_first_frame t =
  Bonsai_driver.flush t.driver;
  Bonsai_driver.trigger_lifecycles t.driver
;;

let handle_root_event
  ~handle_event
  ~handle_incoming_event
  ~dimensions_manager
  ~exit_manager
  (event : 'incoming Event.Root_event.t)
  : 'exit Frame_outcome.t
  =
  let[@inline always] maybe_exit_if_exit_manager_says_so () =
    match State_management.For_exit.exit_status exit_manager with
    | Not_yet_exited -> Frame_outcome.Continue
    | Exited exit -> Exit exit
  in
  match event with
  | Incoming_events_pipe_closed -> Incoming_events_pipe_closed
  | Resize dimensions ->
    State_management.For_dimensions.set dimensions_manager dimensions;
    Continue
  | Incoming_event incoming_event ->
    handle_incoming_event incoming_event;
    maybe_exit_if_exit_manager_says_so ()
  | Event ((Paste _ | Mouse _ | Key_press _) as event) ->
    handle_event event;
    maybe_exit_if_exit_manager_says_so ()
  | Timer -> Continue
;;

let[@inline always] if_frame_has_not_yet_exited exit_manager f =
  match State_management.For_exit.exit_status exit_manager with
  | Exited exit ->
    Deferred.return
      (`Frame_painted (Deferred.return (`Frame_finished (Frame_outcome.Exit exit))))
  | Not_yet_exited -> f ()
;;

let[@inline always] do_effect ~(here : [%call_pos]) effect =
  Effect.Expert.handle effect ~on_exn:(fun exn ->
    let here = Source_code_position.to_string here in
    Exn.reraise exn ("Unhandled exception raised in effect: " ^ here))
;;

let compute_frame
  ({ clock
   ; target_delay
   ; term
   ; dimensions_manager
   ; exit_manager
   ; driver
   ; get_view_and_handler
   ; handle_incoming
   ; time_source
   ; prev_view
   ; finished
   } as t)
  =
  if_frame_has_not_yet_exited exit_manager
  @@ fun () ->
  let frame_start_time = Time_source.now time_source in
  let () = State_management.For_clock.advance_to clock frame_start_time
  and () = State_management.For_dimensions.update dimensions_manager in
  Bonsai_driver.flush driver;
  let #(~view, ~handler, ~handle_incoming_event) =
    let result = Bonsai_driver.result driver in
    let handle_incoming_event incoming_event =
      do_effect (handle_incoming result incoming_event)
    in
    let ~view, ~handler = get_view_and_handler result in
    #(~view, ~handler, ~handle_incoming_event)
  in
  let view_changed =
    match prev_view with
    | None -> true
    | Some prev_view -> not (phys_equal view prev_view)
  in
  let%bind () =
    if view_changed
    then
      if Term.dead term
      then Deferred.return ()
      else (
        let%map () = Term.image term (View.Private.notty_image view) in
        t.prev_view <- Some view)
    else Deferred.return ()
  in
  Bonsai_driver.trigger_lifecycles driver;
  let time_taken = Time_ns.diff (Time_source.now time_source) frame_start_time in
  let delay = Time_ns.Span.(max zero (target_delay - time_taken)) in
  let handle_event event = do_effect (handler event) in
  let shutdown_or_continue =
    let%map events = Term.next_event_or_wait_delay ~delay term in
    Nonempty_list.fold_until
      events
      ~init:()
      ~finish:(fun () -> Continue)
      ~f:(fun () event ->
        match
          handle_root_event
            ~handle_event
            ~handle_incoming_event
            ~dimensions_manager
            ~exit_manager
            event
        with
        | Continue -> Continue ()
        | Incoming_events_pipe_closed -> Stop Frame_outcome.Incoming_events_pipe_closed
        | Exit exit -> Stop (Frame_outcome.Exit exit))
  in
  let frame_finished =
    let%map shutdown_or_continue in
    let () =
      match shutdown_or_continue with
      | Exit exit -> Ivar.fill_if_empty finished (Ok exit)
      | Incoming_events_pipe_closed ->
        Ivar.fill_if_empty finished (Error `Incoming_events_pipe_closed)
      | Continue -> ()
    in
    `Frame_finished shutdown_or_continue
  in
  return (`Frame_painted frame_finished)
;;

let release t = Term.release t.term
let prev_view t = t.prev_view
let dimensions t = Term.dimensions t.term
let finished t = Ivar.read t.finished
let resize t dimensions = Term.enqueue_event t.term (Resize dimensions)
let send_event t event = Term.enqueue_event t.term (Event event)

let send_incoming_event t incoming_event =
  Term.enqueue_event t.term (Incoming_event incoming_event)
;;
