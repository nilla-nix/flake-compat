let
	compat = import ../../.;

	flake = compat.load {
		src = ./.;

		replacements = {
			# nixpkgs = flake.inputs.nixpkgs-unstable;
			nixpkgs = compat.fetch
				(compat.lib.info.from.path ./source);
		};
	};
in
	builtins.readFile "${flake.inputs.nixpkgs}/.version"
