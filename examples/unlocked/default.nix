let
  compat = import ../../.;

  flake = compat.load {
    src = ./.;
  };
in
flake.message
