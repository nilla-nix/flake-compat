# Flake Compat

> Load Nix flakes with support for replacing inputs.

## Usage

First, fetch this repository using either a built-in fetcher or
a tool like [npins](https://github.com/andir/npins).

```bash
npins init --bare

npins add github nilla-nix flake-compat
```

With the library fetched, you can import it and use the
`compat.load` function.

```nix
let
    pins = import ./npins;

    compat = import pins.flake-compat;

    flake = compat.load {
        # Specify the directory of the flake you want to load.
        src = ./.;

        # Optionally specify replacements for any inputs.
        replacements = {};
    };
in
    flake
```

## Replacements

A replacement can be specified for any Flake input named in the
associated `flake.lock` file. The value will be substituted directly,
so it is necessary to ensure that valid input values are used. This
means that if you are replacing an input that is loaded as a flake
then your value must also provide things like outputs, sourceInfo,
etc.

The `compat.fetch` and `compat.lib.info.from.*`
helpers simplify this process.

```nix
let
    pins = import ./npins;

    compat = import pins.flake-compat;

    flake = compat.load {
        src = ./.;

        replacements = {
            nixpkgs-stable = flake.inputs.nixpkgs-unstable;

            my-archive =
                compat.fetch
                    (compat.lib.info.from.path ./my-archive);
        };
    };
in
    flake
```
