# static_analyzer

I have always wanted to figure out how static analyzers work, so I decided
to make a tiny one for a subset of Gleam.

The analyzer can:
- detect when a variable is defined but never used
- identify variables that have not been defined

That's it. It won't work for a lot of Gleam code because, frankly, I am too
lazy to implement everything. But that's not the point of the project anyway.

## About the weird doc comments

I wrote some doc comments over function that look like this:
```gleam
/// @can-modify: scope diagnostics
fn foo(state: State) -> State

/// @modifies: scope
fn bar(state: State) -> State
```
While the comments are pretty strange (and probably violate some sort of best practice), they are helpful for determining whether a function returns a modified version of the passed-in state or not. `@can-modify` means the function might modify the stated fields, `@modifies` means it will.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
gleam shell # Run an Erlang shell
```
