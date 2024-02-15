import gleam/io
import gleam/list
import gleam/dict.{type Dict}
import gleam/bool
import gleam/option
import glance
import gleam_community/ansi

const test_str = "
import blah

pub fn add(a, b) {
  let d = 1
  c
  {
    let none = 2
    let non3 = asdf
    a
    d
    #(foo, bar, none)
  }
  io.println(d)
}

fn lol() {
  blah
}
"

pub fn main() {
  test_str
  |> analyze_code
  |> list.each(fn(diagnostic) {
    case diagnostic.level {
      WarningLevel -> ansi.yellow("⚠️ " <> diagnostic.message)
      ErrorLevel -> ansi.red("✕ " <> diagnostic.message)
    }
    |> io.println
  })
}

pub fn analyze_code(code: String) -> List(Diagnostic) {
  let assert Ok(parsed) = glance.module(code)
  parsed
  |> analyze
  |> list.reverse
}

// TYPES -----------------------------------------------------------------------

pub type Diagnostic {
  Diagnostic(message: String, level: DiagnosticLevel)
}

pub type DiagnosticLevel {
  WarningLevel
  ErrorLevel
}

type Scopes =
  List(Dict(String, VarMetadata))

type VarMetadata {
  VarMetadata(usages: Int, publicity: glance.Publicity)
}

type State {
  State(scopes: Scopes, diagnostics: List(Diagnostic))
}

// ANALYZERS -------------------------------------------------------------------

fn analyze(module: glance.Module) -> List(Diagnostic) {
  let state = State(scopes: [dict.new()], diagnostics: [])

  analyze_functions(module.functions, state)
}

fn analyze_functions(
  functions: List(glance.Definition(glance.Function)),
  state: State,
) -> List(Diagnostic) {
  list.flat_map(functions, analyze_function(_, state))
}

fn analyze_function(
  function: glance.Definition(glance.Function),
  state: State,
) -> List(Diagnostic) {
  let glance.Definition(definition: function, ..) = function

  let state =
    list.fold(function.parameters, state, fn(state, param) {
      case param.name {
        glance.Named(name) -> push_priv_var(state, name)
        glance.Discarded(_) -> state
      }
    })
    |> push_var(function.name, function.publicity)

  analyze_statements(function.body, state)
  |> unused_vars
  |> get_diagnostics
}

/// @can-modify: diagnostics
fn analyze_statements(statements: List(glance.Statement), state: State) -> State {
  list.fold(statements, open_scope(state), fn(state, statement) {
    analyze_statement(statement, state)
  })
  |> unused_vars
  |> close_scope
}

/// @can-modify: scopes diagnostics
fn analyze_statement(statement: glance.Statement, state: State) -> State {
  case statement {
    glance.Assignment(pattern: pattern, ..) -> analyze_pattern(pattern, state)
    glance.Use(patterns: patterns, ..) -> analyze_patterns(patterns, state)
    glance.Expression(expr) -> analyze_expression(expr, state)
  }
}

/// @can-modify: scopes
fn analyze_patterns(patterns: List(glance.Pattern), state: State) -> State {
  list.fold(patterns, state, fn(state, pattern) {
    analyze_pattern(pattern, state)
  })
}

/// @can-modify: scopes
fn analyze_pattern(pattern: glance.Pattern, state: State) -> State {
  case pattern {
    glance.PatternVariable(name) -> push_priv_var(state, name)
    glance.PatternTuple(patterns) -> analyze_patterns(patterns, state)
    glance.PatternList(head_patterns, tail_pattern) ->
      analyze_patterns(
        case tail_pattern {
          option.Some(pattern) -> [pattern, ..head_patterns]
          option.None -> head_patterns
        },
        state,
      )
    glance.PatternAssignment(pattern, name) ->
      analyze_pattern(pattern, state)
      |> push_priv_var(name)
    _ -> state
  }
}

/// @can-modify: diagnostics
fn analyze_expressions(
  expressions: List(glance.Expression),
  state: State,
) -> State {
  list.fold(expressions, state, fn(state, expression) {
    analyze_expression(expression, state)
  })
}

/// @can-modify: diagnostics
fn analyze_expression(expression: glance.Expression, state: State) -> State {
  case expression {
    glance.Variable(name) -> var_usage(state, name)
    glance.NegateInt(expr) | glance.NegateBool(expr) ->
      analyze_expression(expr, state)
    glance.Block(statements) -> analyze_statements(statements, state)
    glance.Tuple(exprs) -> analyze_expressions(exprs, state)
    _ -> state
  }
}

// UTILS -----------------------------------------------------------------------

/// @modifies: scopes
fn push_var(state: State, var: String, publicity: glance.Publicity) -> State {
  let assert [scope, ..rest] = state.scopes
  let scopes = [
    dict.insert(scope, var, VarMetadata(usages: 0, publicity: publicity)),
    ..rest
  ]

  State(..state, scopes: scopes)
}

/// @modifies: scopes
fn push_priv_var(state: State, var: String) -> State {
  push_var(state, var, glance.Private)
}

/// @modifies: diagnostics
fn push_diagnostic(state: State, diagnostic: Diagnostic) -> State {
  State(..state, diagnostics: [diagnostic, ..state.diagnostics])
}

/// @modifies: diagnostics
fn push_diagnostics(state: State, diagnostics: List(Diagnostic)) -> State {
  State(..state, diagnostics: list.append(diagnostics, state.diagnostics))
}

fn get_diagnostics(state: State) -> List(Diagnostic) {
  state.diagnostics
}

/// @modifies: scopes
fn open_scope(state: State) -> State {
  State(..state, scopes: [dict.new(), ..state.scopes])
}

/// @modifies: scopes
fn close_scope(state: State) -> State {
  let assert [_, ..scopes] = state.scopes
  State(..state, scopes: scopes)
}

/// @can-modify: diagnostics scopes
fn var_usage(state: State, var: String) -> State {
  case verify_var_exists(state.scopes, var) {
    True -> State(..state, scopes: increment_usage(state.scopes, var))
    False ->
      push_diagnostic(
        state,
        Diagnostic("`" <> var <> "` not defined", ErrorLevel),
      )
  }
}

fn verify_var_exists(scopes: Scopes, var: String) -> Bool {
  case list.find(scopes, dict.has_key(_, var)) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn increment_usage(scopes: Scopes, var: String) -> Scopes {
  list.map_fold(scopes, False, fn(found, scope) {
    use <- bool.guard(when: found, return: #(found, scope))
    case dict.get(scope, var) {
      Error(_) -> #(False, scope)
      Ok(metadata) -> #(
        True,
        dict.insert(
          scope,
          var,
          VarMetadata(..metadata, usages: metadata.usages + 1),
        ),
      )
    }
  }).1
}

/// @can-modify: diagnostics
fn unused_vars(state: State) -> State {
  let assert [scope, ..] = state.scopes
  let diagnostics =
    dict.fold(scope, [], fn(diagnostics, name, metadata) {
      case metadata {
        VarMetadata(usages: 0, publicity: glance.Private) -> [
          Diagnostic("`" <> name <> "` never used", WarningLevel),
          ..diagnostics
        ]
        _ -> diagnostics
      }
    })
  push_diagnostics(state, diagnostics)
}
