import gleam/string
import gleeunit
import birdie
import static_analyzer.{analyze_code}

pub fn main() {
  gleeunit.main()
}

pub fn unused_test() {
  "fn foo(bar) { let baz = 1}"
  |> analyze_code
  |> string.inspect
  |> birdie.snap("unused variables should generate diagnostics")
}

pub fn undefined_test() {
  "pub fn main() { uhoh }"
  |> analyze_code
  |> string.inspect
  |> birdie.snap("undefined variables should generate diagnostics")
}

pub fn multiple_functions_test() {
  "
  pub fn foo() {
    bar
  }

  pub fn foobar() {
    barbaz
  }
  "
  |> analyze_code
  |> string.inspect
  |> birdie.snap("multiple functions should be analyzed")
}

pub fn nested_scopes_test() {
  "
  pub fn main() {
    let a = 1
    {
      a
      let b = 2
    }
    b
  }
  "
  |> analyze_code
  |> string.inspect
  |> birdie.snap("scopes should be followed correctly")
}

pub fn patterns_test() {
  "
  pub fn main() {
    use x, [1, y] <- 42
    x
  }
  "
  |> analyze_code
  |> string.inspect
  |> birdie.snap("patterns should generate variables")
}