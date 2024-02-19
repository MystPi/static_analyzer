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

type Diagnostics =
  List(Diagnostic)

pub type DiagnosticLevel {
  WarningLevel
  ErrorLevel
}

type Scopes =
  List(Dict(String, VarMetadata))

type VarMetadata {
  VarMetadata(usages: Int, publicity: glance.Publicity)
}

// ANALYZERS -------------------------------------------------------------------

fn analyze(module: glance.Module) -> Diagnostics {
  let scopes = [dict.new()]

  analyze_functions(module.functions, scopes)
}

fn analyze_functions(
  functions: List(glance.Definition(glance.Function)),
  scopes: Scopes,
) -> Diagnostics {
  list.flat_map(functions, analyze_function(_, scopes))
}

fn analyze_function(
  function: glance.Definition(glance.Function),
  scopes: Scopes,
) -> Diagnostics {
  let glance.Definition(definition: function, ..) = function

  let scopes =
    list.fold(function.parameters, scopes, fn(scopes, param) {
      case param.name {
        glance.Named(name) -> push_priv_var(scopes, name)
        glance.Discarded(_) -> scopes
      }
    })
    |> push_var(function.name, function.publicity)

  let #(scopes, d1) = analyze_statements(function.body, scopes)
  let d2 = analyze_unused_vars(scopes)

  list.append(d2, d1)
}

fn analyze_statements(
  statements: List(glance.Statement),
  scopes: Scopes,
) -> #(Scopes, Diagnostics) {
  let #(scopes, d1) =
    list.fold(statements, #(open_scope(scopes), []), fn(prev, statement) {
      let #(scopes, diagnostics) = analyze_statement(statement, prev.0)
      #(scopes, list.append(diagnostics, prev.1))
    })

  let d2 = analyze_unused_vars(scopes)

  #(close_scope(scopes), list.append(d2, d1))
}

fn analyze_statement(
  statement: glance.Statement,
  scopes: Scopes,
) -> #(Scopes, Diagnostics) {
  case statement {
    glance.Assignment(pattern: pattern, ..) -> #(
      analyze_pattern(pattern, scopes),
      [],
    )
    glance.Use(patterns: patterns, ..) -> #(
      analyze_patterns(patterns, scopes),
      [],
    )
    glance.Expression(expr) -> analyze_expression(expr, scopes)
  }
}

fn analyze_patterns(patterns: List(glance.Pattern), scopes: Scopes) -> Scopes {
  list.fold(patterns, scopes, fn(scopes, pattern) {
    analyze_pattern(pattern, scopes)
  })
}

fn analyze_pattern(pattern: glance.Pattern, scopes: Scopes) -> Scopes {
  case pattern {
    glance.PatternVariable(name) -> push_priv_var(scopes, name)
    glance.PatternTuple(patterns) -> analyze_patterns(patterns, scopes)
    glance.PatternList(head_patterns, tail_pattern) ->
      analyze_patterns(
        case tail_pattern {
          option.Some(pattern) -> [pattern, ..head_patterns]
          option.None -> head_patterns
        },
        scopes,
      )
    glance.PatternAssignment(pattern, name) ->
      analyze_pattern(pattern, scopes)
      |> push_priv_var(name)
    _ -> scopes
  }
}

fn analyze_expressions(
  expressions: List(glance.Expression),
  scopes: Scopes,
) -> #(Scopes, Diagnostics) {
  list.fold(expressions, #(scopes, []), fn(prev, expression) {
    let #(scopes, diagnostics) = analyze_expression(expression, prev.0)
    #(scopes, list.append(diagnostics, prev.1))
  })
}

fn analyze_expression(
  expression: glance.Expression,
  scopes: Scopes,
) -> #(Scopes, Diagnostics) {
  case expression {
    glance.Variable(name) -> analyze_var_usage(name, scopes)
    glance.NegateInt(expr) | glance.NegateBool(expr) ->
      analyze_expression(expr, scopes)
    glance.Block(statements) -> analyze_statements(statements, scopes)
    glance.Tuple(exprs) -> analyze_expressions(exprs, scopes)
    _ -> #(scopes, [])
  }
}

fn analyze_var_usage(var: String, scopes: Scopes) -> #(Scopes, Diagnostics) {
  case verify_var_exists(scopes, var) {
    True -> #(increment_usage(scopes, var), [])
    False -> #(scopes, [Diagnostic("`" <> var <> "` not defined", ErrorLevel)])
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

fn analyze_unused_vars(scopes: Scopes) -> Diagnostics {
  let assert [scope, ..] = scopes
  dict.fold(scope, [], fn(detected, name, metadata) {
    case metadata {
      VarMetadata(usages: 0, publicity: glance.Private) -> [
        Diagnostic("`" <> name <> "` never used", WarningLevel),
        ..detected
      ]
      _ -> detected
    }
  })
}

// UTILS -----------------------------------------------------------------------

fn push_var(scopes: Scopes, var: String, publicity: glance.Publicity) -> Scopes {
  let assert [scope, ..rest] = scopes
  [
    dict.insert(scope, var, VarMetadata(usages: 0, publicity: publicity)),
    ..rest
  ]
}

fn push_priv_var(scopes: Scopes, var: String) -> Scopes {
  push_var(scopes, var, glance.Private)
}

fn open_scope(scopes: Scopes) -> Scopes {
  [dict.new(), ..scopes]
}

fn close_scope(scopes: Scopes) -> Scopes {
  let assert [_, ..scopes] = scopes
  scopes
}
