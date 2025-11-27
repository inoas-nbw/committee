//// Gatheres `git blame` information from a repo
//// and calculates the percentage of lines of code
//// a given author has contributed to each file.
////

import argv
import committee/shell
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/order.{type Order}
import gleam/regexp
import gleam/string
import pprint
import taskle

// import gleam/erlang/process

// import pprint.{debug as dbg}

// TODO: support authors instead of author, comma separated list

// const max_commit_count = 2000
//
// const files_from_commits_chunk_size = 64

const max_git_processes = 16

const max_files_to_consider = 1_000_000

const one_minute = 60_000

pub fn main() -> Nil {
  case argv.load().arguments {
    ["ranked-authors", "--path=" <> path] ->
      path
      |> ranked_authors
      |> print_results
    ["current-repo-files", "--path=" <> path] ->
      path
      |> current_repo_files(print_command: True)
      |> print_results
    ["commits", "--path=" <> path, "--author=" <> maybe_quoted_git_author] ->
      maybe_quoted_git_author
      |> commits(path:)
      |> print_results
    ["commit-files", "--path=" <> path, "--commit=" <> commit] ->
      commit
      |> commit_files(path:, print_command: True)
      |> list.sort(by: string.compare)
      |> print_results
    ["file-blame", "--path=" <> path, "--file-path=" <> file_path] ->
      file_path
      |> file_blame(path:, print_command: False)
      |> print_results
    [
      "file-blame-quota",
      "--path=" <> path,
      "--file-path=" <> file_path,
      "--author=" <> author,
    ] -> {
      file_path
      |> file_blame_quota(path:, author:, print_command: True)
      |> print_quota
    }
    [
      "repo-file-blame-quota",
      "--path=" <> path,
      "--author=" <> maybe_quoted_git_author,
      "--sort-by-quota",
    ] -> {
      repo_file_blame_quota(
        path:,
        author: maybe_quoted_git_author,
        print_command: True,
      )
      |> then_println("Sorting by quota percentage...")
      |> list.sort(quota_compare_percentage_desc)
      |> then_println("Percentage quotas:\n")
      |> list.each(print_quota)
    }
    [
      "repo-file-blame-quota",
      "--path=" <> path,
      "--author=" <> maybe_quoted_git_author,
      "--sort-by-total",
    ] -> {
      repo_file_blame_quota(
        path:,
        author: maybe_quoted_git_author,
        print_command: True,
      )
      |> then_println("Sorting by quota total...")
      |> list.sort(quota_compare_total_desc)
      |> then_println("Total quotas:\n")
      |> list.each(print_quota)
    }
    [
      "export-repo-file-blame-quota-to-csv",
      "--path=" <> path,
      "--author=" <> maybe_quoted_git_author,
    ] -> {
      io.println("FILE PATH, AUTHOR LINES, TOTAL LINES, LINES PERCENTAGE")

      repo_file_blame_quota(
        path:,
        author: maybe_quoted_git_author,
        print_command: False,
      )
      |> list.sort(quota_compare_total_desc)
      |> list.each(print_csv)
    }
    _ -> {
      "Usages:

  gleam run --no-print-progress export-repo-file-blame-quota-to-csv --path=\"/PATH/TO/REPO\" --author=\"GIT_AUTHOR\" > git-blame-quota-export.csv

  OR one of these:

  gleam run ranked-authors --path=\"/PATH/TO/REPO\"
  gleam run current-repo-files --path=\"/PATH/TO/REPO\"
  gleam run commits --path=\"/PATH/TO/REPO\" --author=\"GIT_AUTHOR\"
  gleam run commit-files --path=\"/PATH/TO/REPO\" --commit=GIT_COMMIT_ID
  gleam run file-blame --path=\"/PATH/TO/REPO\" --file-path=\"RELATIVE/FILE/PATH/WITHIN/REPO\"
  gleam run file-blame-quota --path=\"/PATH/TO/REPO\" --file-path=\"RELATIVE/FILE/PATH/WITHIN/REPO\" --author=\"GIT_AUTHOR\"
  gleam run repo-file-blame-quota --path=\"/PATH/TO/REPO\" --author=\"GIT_AUTHOR\" --sort-by-total
  gleam run repo-file-blame-quota --path=\"/PATH/TO/REPO\" --author=\"GIT_AUTHOR\" --sort-by-quota
"
      |> io.println_error

      Nil
    }
  }
}

fn print_quota(quota: #(String, Int, Int, Int)) -> Nil {
  let author_lines = quota.1 |> int.to_string
  let total_lines = quota.2 |> int.to_string
  let percentage = quota.3 |> int.to_string

  {
    quota.0
    <> " - "
    <> author_lines
    <> " of "
    <> total_lines
    <> " lines"
    <> " - "
    <> percentage
    <> "%"
  }
  |> io.println
}

fn print_csv(quota: #(String, Int, Int, Int)) -> Nil {
  let author_lines = quota.1 |> int.to_string
  let total_lines = quota.2 |> int.to_string
  let percentage = quota.3 |> int.to_string

  {
    "\""
    <> quota.0
    <> "\""
    <> ", "
    <> author_lines
    <> ", "
    <> total_lines
    <> ", "
    <> percentage
    <> ";"
  }
  |> io.println
}

fn quota_compare_percentage_desc(
  a: #(String, Int, Int, Int),
  with b: #(String, Int, Int, Int),
) -> Order {
  case a.3 == b.3 {
    True -> order.Eq
    False ->
      case a.3 > b.3 {
        True -> order.Lt
        False -> order.Gt
      }
  }
}

fn quota_compare_total_desc(
  a: #(String, Int, Int, Int),
  with b: #(String, Int, Int, Int),
) -> Order {
  case a.1 == b.1 {
    True -> order.Eq
    False ->
      case a.1 > b.1 {
        True -> order.Lt
        False -> order.Gt
      }
  }
}

fn print_results(strings strngs: List(String)) -> Nil {
  strngs |> string.join("\n") |> io.println

  Nil
}

fn then_println(x: a, message message: String) -> a {
  message |> io.println

  x
}

fn then_println_if(x: a, message message: String, when when: Bool) -> a {
  case when {
    True -> message |> io.println
    False -> Nil
  }

  x
}

fn current_repo_files(
  path path: String,
  print_command print_command: Bool,
) -> List(String) {
  let command = "git"
  let args = ["ls-files"]

  case
    shell.exec_command(path:, command:, args:, print_command: print_command)
  {
    Ok(strings) -> strings |> string.split("\n")
    Error(error) -> panic as pprint.format(error)
  }
}

fn ranked_authors(path path: String) -> List(String) {
  let command = "git"
  let args = ["shortlog", "-n", "-s", "-e"]

  case shell.exec_command(path:, command:, args:, print_command: True) {
    Ok(strings) -> strings |> string.split("\n")
    Error(error) -> panic as pprint.format(error)
  }
}

fn commits(author author: String, path path: String) -> List(String) {
  let command = "git"
  let args = ["log", "--author=" <> author, "--format=format:%H"]

  case shell.exec_command(path:, command:, args:, print_command: True) {
    Ok(strings) -> strings |> string.split("\n")
    Error(error) -> panic as pprint.format(error)
  }
}

fn commit_files(
  commit commit: String,
  path path: String,
  print_command print_command: Bool,
) -> List(String) {
  let command = "git"
  let args = ["-c", "diff.renamelimit=9999", "diff", "--name-only", commit]

  case shell.exec_command(path:, command:, args:, print_command:) {
    Ok(strings) -> strings |> string.split("\n")
    Error(error) -> panic as pprint.format(error)
  }
}

fn file_blame(
  relative_file_path relative_file_path: String,
  path path: String,
  print_command print_command: Bool,
) -> List(String) {
  let command = "git"
  let args = ["blame", "-w", "-c", "-M", "-C", "-C", relative_file_path]

  // process.sleep(1000)

  case shell.exec_command(path:, command:, args:, print_command:) {
    Ok(strings) -> strings |> string.split("\n")
    Error(error) -> panic as pprint.format(error)
  }
}

fn file_blame_quota(
  relative_file_path relative_file_path: String,
  path path: String,
  author author: String,
  print_command print_command: Bool,
) -> #(String, Int, Int, Int) {
  let file_blame =
    relative_file_path
    |> file_blame(path:, print_command:)
    |> reject_empty_lines_in_file_blame
  let total_lines = file_blame |> total_lines
  let author_lines = file_blame |> author_lines(author:)
  let percentage =
    { int.to_float(author_lines) /. int.to_float(total_lines) *. 100.0 }
    |> float.round

  #(relative_file_path, author_lines, total_lines, percentage)
}

fn reject_empty_lines_in_file_blame(lines lines: List(String)) -> List(String) {
  // Unescaped regex: ^[a-z0-9]*\s+\(.*\s+\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \+\d{4}\s+\d{1,}\)\s*$
  let assert Ok(match_empty_source_code_line_re) =
    regexp.compile(
      "^[a-z0-9]*\\s+\\(.*\\s+\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2} \\+\\d{4}\\s+\\d{1,}\\)\\s*$",
      with: regexp.Options(case_insensitive: False, multi_line: True),
    )

  lines
  |> list.filter(fn(line: String) -> Bool {
    line |> regexp.check(with: match_empty_source_code_line_re) == False
  })
}

fn total_lines(lines lines: List(String)) -> Int {
  lines |> list.length
}

fn author_lines(lines lines: List(String), author author: String) -> Int {
  let assert Ok(fetch_line_author_re) =
    regexp.compile(
      // Unescaped regex: ^([a-z0-9]*)\s+\((.*)\s+\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \+\d{4}\s+\d{1,}\).*$
      "^([a-z0-9]*)\\s+\\((.*)\\s+\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2} \\+\\d{4}\\s+\\d{1,}\\).*$",
      with: regexp.Options(case_insensitive: False, multi_line: True),
    )

  lines
  |> list.fold(0, fn(acc: Int, line: String) -> Int {
    let matches = line |> regexp.scan(with: fetch_line_author_re)
    case matches {
      [regexp.Match(_full_match, [Some(_commit_id), Some(match_author)])] ->
        case match_author == author {
          True -> acc + 1
          False -> acc
        }
      [] -> acc
      match -> panic as pprint.format(#("unexpected input", match))
    }
  })
}

fn repo_file_blame_quota(
  author author: String,
  path path: String,
  print_command print_command: Bool,
) -> List(#(String, Int, Int, Int)) {
  // author
  // |> commits(path:)
  // |> then_println("Getting files from commits...")
  // |> collect_files_from_commits(path:)
  path
  |> then_println_if("Getting current repo files...", when: print_command)
  |> current_repo_files(print_command:)
  |> list.take(max_files_to_consider)
  |> list.sized_chunk(into: max_git_processes)
  |> list.flat_map(fn(files: List(String)) -> List(#(String, Int, Int, Int)) {
    case print_command {
      True ->
        {
          "Getting git blame based quota for up to "
          <> files |> list.length |> int.to_string
          <> " files..."
        }
        |> io.println
      False -> Nil
    }

    files
    |> repo_file_blame_quota_chunk(path:, author:, print_command: print_command)
  })
}

const ignored_files_by_ext = [
  ".xml",
  ".json",
]

fn repo_file_blame_quota_chunk(
  files files: List(String),
  path path: String,
  author author: String,
  print_command print_command: Bool,
) -> List(#(String, Int, Int, Int)) {
  let files =
    files
    |> list.filter(fn(file: String) {
      list.any(ignored_files_by_ext, string.ends_with(file, _)) == False
    })

  let assert Ok(tasks) =
    files
    |> list.map(fn(file: String) {
      taskle.async(fn() -> #(String, Int, Int, Int) {
        file |> file_blame_quota(path:, author:, print_command: print_command)
      })
    })
    |> taskle.try_await_all(one_minute * 60 * 5)

  tasks
  |> list.fold(
    [],
    fn(
      acc: List(#(String, Int, Int, Int)),
      task_result: #(String, Int, Int, Int),
    ) -> List(#(String, Int, Int, Int)) {
      case task_result {
        quota if quota.1 > 0 -> [quota, ..acc]
        _quota -> acc
      }
    },
  )
}
//
// fn collect_files_from_commits(
//   commits commits: List(String),
//   path path: String,
// ) -> List(String) {
//   let commits = commits |> list.take(max_commit_count)

//   {
//     "Collecting from "
//     <> commits |> list.length |> int.to_string
//     <> " commits..."
//   }
//   |> io.println

//   commits
//   |> list.sized_chunk(into: files_from_commits_chunk_size)
//   |> list.map(fn(commits_chunk: List(String)) -> List(String) {
//     {
//       "Getting files from up to "
//       <> commits_chunk |> list.length |> int.to_string
//       <> " commits..."
//     }
//     |> io.println

//     commits_chunk |> collect_files_from_commits_chunk(path:)
//   })
//   |> list.flatten
//   |> fn(file_pathes: List(String)) -> List(String) {
//     {
//       "Detected "
//       <> file_pathes |> list.length |> int.to_string
//       <> " files in commits..."
//     }
//     |> io.println

//     file_pathes
//   }
//   |> then_println("Removing duplicate files...")
//   |> list.unique
//   |> fn(files: List(String)) -> List(String) {
//     {
//       "Detected " <> files |> list.length |> int.to_string <> " unique files..."
//     }
//     |> io.println

//     files
//   }
// }

// fn collect_files_from_commits_chunk(
//   commits commits: List(String),
//   path path: String,
// ) -> List(String) {
//   commits
//   |> list.map(fn(commit: String) -> taskle.Task(List(String)) {
//     taskle.async(fn() -> List(String) {
//       commit |> commit_files(path:, print_command: False)
//     })
//   })
//   |> taskle.try_await_all(one_minute)
//   |> list.fold(
//     [],
//     fn(acc: List(String), task_result: Result(List(String), taskle.AwaitError)) -> List(
//       String,
//     ) {
//       case task_result {
//         Ok(files) -> list.flatten([acc, files])
//         Error(error) -> panic as pprint.format(error)
//       }
//     },
//   )
// }
