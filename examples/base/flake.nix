{
	description = "Example flake";

	inputs = {
		nixpkgs.url = "github:nixos/nixpkgs/nixos-21.11";
		nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
	};

	outputs = inputs: {
		packages.x86_64-linux = rec {
			default = hello;
			hello = inputs.nixpkgs.legacyPackages.x86_64-linux.hello;
		};
	};
}
