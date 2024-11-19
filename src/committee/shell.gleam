import gleam/int
import gleam/string
import gleamyshell.{CommandOutput}

// import gleam/io
// import pprint.{debug as dbg}

pub fn string_enclose(
  nested s2: String,
  before s1: String,
  after s3: String,
) -> String {
  s1 <> s2 <> s3
}

pub fn exec_command(
  path in: String,
  command command: String,
  args args: List(String),
) -> Result(String, String) {
  // io.println(
  //   "\n$ "
  //   <> command
  //   <> " "
  //   <> string.join(args, " ")
  //   <> "\n  in: "
  //   <> in
  //   <> "\n",
  // )

  case gleamyshell.execute(command, in:, args:) {
    Ok(CommandOutput(0, output)) -> output |> string.trim |> Ok
    Ok(CommandOutput(exit_code, output)) -> non_zero_exit(exit_code:, output:)
    Error(reason) -> error(reason)
  }
}

fn non_zero_exit(
  exit_code exit_code: Int,
  output output: String,
) -> Result(String, String) {
  {
    "Whoops!\nError ("
    <> int.to_string(exit_code)
    <> "): "
    <> string.trim(output)
  }
  |> Error
}

fn error(reason reason: String) -> Result(String, String) {
  { "Fatal: " <> reason } |> Error
}
