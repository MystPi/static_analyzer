# static_analyzer

I have always wanted to figure out how static analyzers work, so I decided
to make a tiny one for a subset of Gleam.

The analyzer can:
- detect when a variable is defined but never used
- identify variables that have not been defined

That's it. It won't work for a lot of Gleam code because, frankly, I am too
lazy to implement everything. But that's not the point of the project anyway.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
gleam shell # Run an Erlang shell
```
