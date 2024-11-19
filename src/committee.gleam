import argv
import committee/shell
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/otp/task
import gleam/regex
import gleam/string
import pprint.{debug as dbg}

// TODO: support authors instead of author, comma separated list

pub fn main() -> Nil {
  case argv.load().arguments {
    ["ranked-authors", "--path=" <> path] ->
      path
      |> ranked_authors
      |> print_results
    ["commits", "--path=" <> path, "--author=" <> maybe_quoted_git_author] ->
      maybe_quoted_git_author
      |> commits(path:)
      |> print_results
    ["commit-files", "--path=" <> path, "--commit=" <> commit] ->
      commit
      |> commit_files(path:)
      |> print_results
    ["file-blame", "--path=" <> path, "--file-path=" <> file_path] ->
      file_path
      |> file_blame(path:)
      |> print_results
    [
      "file-blame-quota",
      "--path=" <> path,
      "--file-path=" <> file_path,
      "--author=" <> author,
    ] -> {
      file_path
      |> file_blame_quota(path:, author:)
      |> fn(quota) {
        {
          quota.0 <> " " <> quota.1 |> int.to_string <> quota.2 |> int.to_string
        }
        //
        // If I omit calling io.println, I get:
        //
        // src/committee.gleam:51:18: Warning: a term is constructed, but never used
        // %   51|       "--path=" <> path,
        // %     |                  ^

        // |> io.println
      }

      Nil
    }
    [
      "top-blame-quota",
      "--path=" <> path,
      "--author=" <> maybe_quoted_git_author,
    ] -> {
      top_blame_quota(path:, author: maybe_quoted_git_author)
      |> then_println(" ")
      |> dbg
      // |> string.join("\n")
      // |> io.println

      Nil
    }
    _ -> {
      "Usages:

  gleam run --no-print-progress ranked-authors --path=\"/PATH/TO/REPO\"

  gleam run --no-print-progress commits --path=\"/PATH/TO/REPO\" --author=\"GIT_AUTHOR\"

  gleam run --no-print-progress commit-files --path=\"/PATH/TO/REPO\" --commit=d623c514686f241f0b424b48917f094efa5c854b

  gleam run --no-print-progress file-blame --path=\"/PATH/TO/REPO\" --file-path=\"RELATIVE/FILE/PATH/WITHIN/REPO\"

  gleam run --no-print-progress file-blame-quota --path=\"/PATH/TO/REPO\" --file-path=\"RELATIVE/FILE/PATH/WITHIN/REPO\" --author=\"GIT_AUTHOR\"

  gleam run --no-print-progress top-blame-quota --path=\"/PATH/TO/REPO\" --author=\"GIT_AUTHOR\"

  gleam run --no-print-progress export-top-blame-quota-to-csv --path=\"/PATH/TO/REPO\" --author=\"GIT_AUTHOR\"
"
      |> io.println_error

      Nil
    }
  }
}

fn print_results(strings strngs: List(String)) -> Nil {
  strngs |> string.join("\n") |> io.println

  Nil
}

fn then_println(x: a, message message: String) -> a {
  io.println(message)
  x
}

fn ranked_authors(path path: String) -> List(String) {
  let command = "git"
  let args = ["shortlog", "-n", "-s"]

  case shell.exec_command(path: path, command:, args:) {
    Ok(strings) -> strings |> string.split("\n")
    Error(error) -> panic as pprint.format(error)
  }
}

fn commits(author author: String, path path: String) -> List(String) {
  let command = "git"
  let args = ["log", "--author=" <> author, "--format=format:%H"]

  case shell.exec_command(path: path, command:, args:) {
    Ok(strings) -> strings |> string.split("\n")
    Error(error) -> panic as pprint.format(error)
  }
}

fn commit_files(commit commit: String, path path: String) -> List(String) {
  let command = "git"
  let args = ["-c", "diff.renamelimit=9999", "diff", "--name-only", commit]

  case shell.exec_command(path: path, command:, args:) {
    Ok(strings) -> strings |> string.split("\n")
    Error(error) -> panic as pprint.format(error)
  }
}

fn file_blame(
  relative_file_path relative_file_path: String,
  path path: String,
) -> List(String) {
  let command = "git"
  let args = ["blame", "-w", "-M", "-C", "-C", relative_file_path]

  case shell.exec_command(path: path, command:, args:) {
    Ok(strings) -> strings |> string.split("\n")
    Error(error) -> panic as pprint.format(error)
  }
}

fn file_blame_quota(
  relative_file_path relative_file_path: String,
  path path: String,
  author author: String,
) -> #(String, Int, Int) {
  let file_blame =
    relative_file_path |> file_blame(path:) |> reject_empty_lines_in_file_blame
  let total_lines = file_blame |> total_lines
  let author_lines = file_blame |> author_lines(author: author)

  #(relative_file_path, author_lines, total_lines)
}

fn reject_empty_lines_in_file_blame(lines lines: List(String)) -> List(String) {
  // Unescaped regex: ^[a-z0-9]*\s+\(.*\s+\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \+\d{4}\s+\d{1,}\)\s*$
  let assert Ok(match_empty_source_code_line_re) =
    regex.compile(
      "^[a-z0-9]*\\s+\\(.*\\s+\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2} \\+\\d{4}\\s+\\d{1,}\\)\\s*$",
      with: regex.Options(case_insensitive: False, multi_line: True),
    )

  lines
  |> list.filter(fn(line) {
    line |> regex.check(with: match_empty_source_code_line_re) == False
  })
}

fn total_lines(lines lines: List(String)) -> Int {
  lines |> list.length
}

fn author_lines(lines lines: List(String), author author: String) -> Int {
  let assert Ok(fetch_line_author_re) =
    regex.compile(
      // Unescaped regex: ^([a-z0-9]*)\s+\((.*)\s+\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \+\d{4}\s+\d{1,}\).*$
      "^([a-z0-9]*)\\s+\\((.*)\\s+\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2} \\+\\d{4}\\s+\\d{1,}\\).*$",
      with: regex.Options(case_insensitive: False, multi_line: True),
    )

  lines
  |> list.fold(0, fn(acc, line) {
    let matches = line |> regex.scan(with: fetch_line_author_re)
    case matches {
      [regex.Match(_full_match, [Some(_commit_id), Some(match_author)])] ->
        case match_author == author {
          True -> acc + 1
          False -> acc
        }
      [] -> acc
      match -> panic as pprint.format(#("unexpected input", match))
    }
  })
}

fn top_blame_quota(author author: String, path path: String) -> List(String) {
  author
  |> commits(path:)
  |> collect_files_from_commits(path:)
}

const tuncate_commits_to = 150

const files_from_commits_chunk_size = 32

fn collect_files_from_commits(
  commits commits: List(String),
  path path: String,
) -> List(String) {
  let commits = commits |> list.take(tuncate_commits_to)

  {
    "Detected "
    <> commits |> list.length |> int.to_string
    <> " files commits..."
  }
  |> io.println

  commits
  |> list.sized_chunk(into: files_from_commits_chunk_size)
  |> list.map(fn(commits_chunk) {
    {
      "Getting files from "
      <> files_from_commits_chunk_size |> int.to_string
      <> " commits..."
    }
    |> io.println

    commits_chunk |> collect_files_from_commits_chunk(path:)
  })
  |> list.flatten
  |> then_println("Removing duplicate files...")
  |> list.unique
  |> then_println("Sorting files...")
  |> list.sort(by: string.compare)
}

fn collect_files_from_commits_chunk(
  commits commits: List(String),
  path path: String,
) -> List(String) {
  commits
  |> list.map(fn(commit) { task.async(fn() { commit |> commit_files(path:) }) })
  |> task.try_await_all(10_000)
  |> list.fold(
    [],
    fn(acc: List(String), task_result: Result(List(String), task.AwaitError)) -> List(
      String,
    ) {
      case task_result {
        Ok(files) -> list.flatten([acc, files])
        Error(error) -> panic as pprint.format(error)
      }
    },
  )
}
