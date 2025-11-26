import gleam/int
import gleam/io
import gleam/string
import gleamyshell

pub fn exec_command(
  path in: String,
  command command: String,
  args args: List(String),
  print_command print_command: Bool,
) -> Result(String, String) {
  case print_command {
    True ->
      io.println(
        "$ "
        <> command
        <> " "
        <> string.join(args, " ")
        <> "\n  in: "
        <> in
        <> "\n",
      )
    False -> Nil
  }

  case gleamyshell.execute(command, in:, args:) {
    Ok(gleamyshell.CommandOutput(0, output)) -> output |> string.trim |> Ok
    Ok(gleamyshell.CommandOutput(exit_code, output)) ->
      non_zero_exit(command:, in:, args:, exit_code:, output:)
    Error(reason) -> error(command:, in:, args:, reason:)
  }
}

fn non_zero_exit(
  in in: String,
  command command: String,
  args args: List(String),
  exit_code exit_code: Int,
  output output: String,
) -> Result(String, String) {
  {
    "Error ("
    <> int.to_string(exit_code)
    <> "): "
    <> string.trim(output)
    <> "\n  command: "
    <> command
    <> " "
    <> args |> string.join(" ")
    <> "\n  in: "
    <> in
  }
  |> Error
}

fn error(
  in in: String,
  command command: String,
  args args: List(String),
  reason reason: String,
) -> Result(String, String) {
  {
    "Fatal: "
    <> reason
    <> "\n  command: "
    <> command
    <> " "
    <> args |> string.join(" ")
    <> "\n  in: "
    <> in
  }
  |> Error
}
