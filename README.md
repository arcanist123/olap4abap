# olap4abap

An XMLA server with its own MDX engine, written in ABAP. It runs on an SAP system and serves OLAP cubes defined on top
of SAP BW InfoProviders (InfoCubes and cube-type aDSOs) to XMLA clients such as Excel pivot tables.

olap4abap is a port of [Mondrian](https://github.com/pentaho/mondrian) (in the version of the eMondrian fork) to ABAP:
cubes are described by Mondrian schema XML, MDX is parsed with a port of Mondrian's grammar, and queries are resolved
and evaluated as Mondrian does. The BW system's own MDX engine is not used.

Status: under development. The MDX engine answers the statements of Mondrian's test suite that apply to a single cube
the way the reference server does (see `docs/test-strategy.md`).

## What is in the repository

- `src/` - the ABAP objects (abapGit file format), package `$ZZXXMLA1`, NetWeaver 7.50 syntax
- `web/schema/` - the schema builder, a Preact web application served by the ABAP system
- `scripts/` - deployment, test and code generation scripts (Python, bash)
- `reference/`, `tests/` - XMLA exchanges and MDX statements with the reference server's answers
- `docs/` - scope, design and the development environment

## Getting started

1. Import `src/` into a package with [abapGit](https://abapgit.org) (or `scripts/sap-sync.sh push`, which uses sapcli).
2. Create an ICF service whose handler is `ZZXXMLA1_MAIN_ENDPOINT`.
3. Upload the data sources file and a schema (`scripts/sap-files.py`, see `docs/environment.md`, Catalogs), or build
   a schema for an InfoProvider in the schema builder under `<service>/schema`.
4. Point an XMLA client at the service URL.

`docs/environment.md` describes the development setup, including the reference server (eMondrian in Docker) that the
tests compare against.

## License

olap4abap is licensed under the [Eclipse Public License 2.0](LICENSE). It contains code derived from Mondrian
(Eclipse Public License 1.0); see [NOTICE](NOTICE) for the copyright notices and the third-party components.

SAP, SAP BW, ABAP and SAP NetWeaver are trademarks of SAP SE; Mondrian is a trademark of Hitachi Vantara. olap4abap is
not affiliated with or endorsed by either.
