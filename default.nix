let
  lib = {
    attrs = {
      when = condition: set:
        if condition then set else { };

      pick = name: set:
        lib.attrs.when (set ? ${name}) { ${name} = set.${name}; };
    };

    strings = {
      when = condition: string:
        if condition then string else "";
    };

    hash = {
      from = {
        info = set: lib.attrs.when (set ? narHash)
          { sha256 = set.narHash; };
      };
    };

    date = {
      from = {
        modified = timestamp:
          let
            rem = x: y: x - x / y * y;
            days = timestamp / 86400;
            secondsInDay = rem timestamp 86400;
            hours = secondsInDay / 3600;
            minutes = (rem secondsInDay 3600) / 60;
            seconds = rem timestamp 60;

            # Courtesy of https://stackoverflow.com/a/32158604.
            z = days + 719468;
            era = (if z >= 0 then z else z - 146096) / 146097;
            doe = z - era * 146097;
            yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
            y = yoe + era * 400;
            doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
            mp = (5 * doy + 2) / 153;
            d = doy - (153 * mp + 2) / 5 + 1;
            m = mp + (if mp < 10 then 3 else -9);
            y' = y + (if m <= 2 then 1 else 0);

            pad = s: if builtins.stringLength s < 2 then "0" + s else s;
          in
          "${builtins.toString y'}${pad (builtins.toString m)}${pad (builtins.toString d)}${pad (builtins.toString hours)}${pad (builtins.toString minutes)}${pad (builtins.toString seconds)}";
      };
    };

    info = {
      from = {
        path = path: {
          type = "path";
          lastModified = 0;
          inherit path;
        };

        # TODO: Do we need support for other types?
      };
    };
  };

  fetchurl = { url, sha256 }:
    builtins.path {
      name = "source";
      recursive = true;
      path = builtins.derivation {
        builder = "builtin:fetchurl";

        name = "source";
        inherit url;

        executable = false;
        unpack = false;
        system = "builtin";
        preferLocalBuild = true;

        outputHash = sha256;
        outputHashAlgo = "sha256";
        outputHashMode = "recursive";

        impureEnvVars = [
          "http_proxy"
          "https_proxy"
          "ftp_proxy"
          "all_proxy"
          "no_proxy"
        ];

        urls = [ url ];
      };
    };

  fetch = info:
    if info.type == "path" then
      {
        outPath = builtins.path (
          {
            name = "source";
            inherit (info) path;
          }
          // lib.hash.from.info info
        );
      }
    else if info.type == "file" then
      if builtins.substring 0 7 info.url == "http://" || builtins.substring 0 8 info.url == "https://" then
        {
          outPath = fetchurl ({
            inherit (info) url;
          } // lib.hash.from.info info);
        }
      else if builtins.substring 0 7 info.url == "file://" then
        {
          outPath = builtins.path ({
            name = "source";
            path = builtins.substring 7 (-1) info.url;
          } // lib.hash.from.info info);
        }
      else
        builtins.throw ''Unsupported input url "${info.url}"''
    else if info.type == "tarball" then
      {
        outPath = builtins.fetchTarball (
          { inherit (info) url; }
          // lib.hash.from.info info
        );
      }
    else if info.type == "git" then
      {
        outPath = builtins.fetchGit (
          { inherit (info) url; }
          // lib.attrs.pick "rev" info
          // lib.attrs.pick "ref" info
          // lib.attrs.pick "submodules" info
        );

        inherit (info) lastModified;
        lastModifiedDate = lib.date.from.modified info.lastModified;
        revCount = info.revCount or 0;
      } // lib.attrs.when (info ? rev) {
        inherit (info) rev;
        shortRev = builtins.substring 0 7 info.rev;
      }
    else if info.type == "github" then
      {
        outPath = builtins.fetchTarball (
          { url = "https://api.${info.host or "github.com"}/repos/${info.owner}/${info.repo}/tarball/${info.rev}"; }
          // lib.hash.from.info info
        );

        inherit (info) rev lastModified;
        shortRev = builtins.substring 0 7 info.rev;
        lastModifiedDate = lib.date.from.modified info.lastModified;
      }
    else if info.type == "gitlab" then
      {
        outPath = builtins.fetchTarball (
          { url = "https://${info.host or "gitlab.com"}/api/v4/projects/${info.owner}%2F${info.repo}/repository/archive.tar.gz?sha=${info.rev}"; }
          // lib.hash.from.info info
        );

        inherit (info) rev lastModified;
        shortRev = builtins.substring 0 7 info.rev;
        lastModifiedDate = lib.date.from.modified info.lastModified;
      }
    else if info.type == "sourcehut" then
      {
        outPath = builtins.fetchTarball (
          { url = "https://${info.host or "git.sr.ht"}//${info.owner}/${info.repo}/archive/${info.rev}.tar.gz"; }
          // lib.hash.from.info info
        );

        inherit (info) rev lastModified;
        shortRev = builtins.substring 0 7 info.rev;
        lastModifiedDate = lib.date.from.modified info.lastModified;
      }
    else
      builtins.throw ''Unsupported input type "${info.type}".'';

  load = { src, replacements ? { } }:
    let
      lockFile = "${src}/flake.lock";

      lock = builtins.fromJSON (builtins.readFile lockFile);

      root =
        let
          isGit = builtins.pathExists "${src}/.git";
          isShallow = builtins.pathExists "${src}/.git/shallow";

          result =
            if src ? outPath then
              src
            else if isGit && !isShallow then
              let
                info = builtins.fetchGit src;
              in
              if info.rev == "0000000000000000000000000000000000000000" then
                builtins.removeAttrs info [ "rev" "shortRev" ]
              else
                info
            else
              {
                outPath =
                  if builtins.isPath src then
                    builtins.path
                      {
                        name = "source";
                        path = src;
                      }
                  else
                    src;
              };
        in
        {
          lastModified = 0;
          lastModifiedDate = lib.date.from.modified 0;
        } // result;

      nodes = builtins.mapAttrs
        (name: node:
          let
            info =
              if name == lock.root then
                root
              else
                fetch (
                  node.info or { }
                  // builtins.removeAttrs node.locked [ "dir" ]
                );

            subdir =
              if name == lock.root then
                ""
              else
                node.locked.dir or "";

            outPath = info + lib.strings.when (subdir != "") "/${subdir}";

            inputs = builtins.mapAttrs
              (name: spec:
                let
                  resolved = resolve spec;
                  input = nodes.${resolve spec};
                in
                if replacements ? ${resolved} then
                  replacements.${resolved}
                else
                  input
              )
              (node.inputs or { });

            resolve = spec:
              if builtins.isList spec then
                select lock.root spec
              else
                spec;

            select = name: path:
              if path == [ ] then
                name
              else
                select
                  (resolve lock.nodes.${name}.inputs.${builtins.head path})
                  (builtins.tail path);

            flake = import "${outPath}/flake.nix";

            outputs = flake.outputs (inputs // {
              self = result;
            });

            result =
              outputs
              // info
              // {
                inherit outPath inputs outputs;
                sourceInfo = info;
                _type = "flake";
              };
          in
          if node.flake or true then
            assert builtins.isFunction flake.outputs;
            result
          else
            info
        )
        lock.nodes;

      unlocked =
        let
          flake = import "${root}/flake.nix";
          outputs = root // flake.outputs {
            self = outputs;
          };
        in
        outputs;

      flake =
        let
          result =
            if !(builtins.pathExists lockFile) then
              unlocked
            else if lock.version == 4 then
            # TODO: Get a lockfile with version 4 to test.
              builtins.throw ''Lock file "${lockFile}" with version "${lock.version}" is not supported.''
            else if lock.version >= 5 && lock.version <= 7 then
              nodes.${lock.root}
            else
              builtins.throw ''Lock file "${lockFile}" with version "${lock.version}" is not supported.'';
        in
        result // {
          inputs = result.inputs or { } // {
            self = flake;
          };
        };
    in
    flake;
in
{
  inherit load fetch lib;
}
