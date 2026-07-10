open! Core
module View = View
module Attr = Attr
module Event = Event
module Effect = Effect
module Cursor = Cursor
module Title = Title
module Captured_or_ignored = Captured_or_ignored

module Mouse_reporting = struct
  include Mouse_reporting_config
  include Mouse_reporting
end

module Driver = Driver
include Geom

let start_with_exit = Loop.start_with_exit
let start_with_exit_result = Loop.start_with_exit_result
let start_with_driver = Loop.start_with_driver
let start = Loop.start

module Bonsai = Bonsai

let stitch (~view, ~handler) =
  let%arr.Bonsai view and handler in
  ~view, ~handler
;;

let unstitch t =
  let%sub.Bonsai ~view, ~handler = t in
  ~view, ~handler
;;

module Private = struct
  module Driver = Driver
  module Frame_outcome = Frame_outcome

  module For_testing = struct
    let make_app_exit_on_ctrlc = Loop.For_testing.make_app_exit_on_ctrlc
    let with_driver = Loop.For_testing.with_driver
    let register_mouse_reporting_for_mock_tests = Mouse_reporting.For_mock_tests.register
  end
end

module Expert = struct
  module Write_to_tty = Write_to_tty
  module For_other_bonsais = Loop.For_other_bonsais
end
