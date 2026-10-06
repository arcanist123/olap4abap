# Wide demo

A demo data set for trying the schema builder and the engine on a wide model: one provider with 100 characteristics
of 1,000 members each and 1,000 records. It is made up by `ZZXXMLA1_CL_BW_WIDE_GEN` (a seeded pseudo-random generator,
the same records on every run), so it carries no third-party data and is under the project's license.

Run program `ZZXXMLA1_SETUP` with the checkbox "Also generate the wide demo". "Wide demo: records" (`run( records = ...
)` of the class) sets the number of records in each provider; 0 (the default) is 1,000. A run with 1,000 records takes
about four minutes, most of it for creating and activating the objects. A run with many records takes longer than a
dialog work process may: start the program in the background (F9). A run with 1,000,000 records (2026-10-06) was
cancelled by the system during the aDSO load without a short dump, and kept only the cube's first package; that size
is not supported yet.

A run **deletes and creates** InfoArea `ZXMLWIDE`'s objects: the aDSO, the cube, the views of the characteristics (if
the schema builder generated any) and the InfoObjects `ZXMLAD00` to `ZXMLAD99` and `ZXMLAKF`. A catalog made for the
providers stays in `/WEB-INF/datasources.xml`.

## What it creates

- Characteristics `ZXMLAD00` to `ZXMLAD99` ("Dimension 00" ... "Dimension 99"): NUMC 4, with master data and no
  attributes. Each has the members `0001` to `1000` in its attribute table (`/BIC/PZXMLAD00`), and BW's blank member.
- Key figure `ZXMLAKF` (Amount): a decimal number, summed.
- InfoCube `ZXMLWIDE`: an InfoCube has at most 13 dimensions of its own, so the characteristics are grouped ten to a
  BW dimension (`ZXMLWIDE1` holds `ZXMLAD00` to `ZXMLAD09`, ..., `ZXMLWIDEA` holds `ZXMLAD90` to `ZXMLAD99`).
- Cube-type aDSO `ZXMLWIDEA` with the same characteristics and records.
- No views, schema or catalog: make them with the schema builder (`/zzxxmla1/schema`, `docs/schema-generator.md`).

## The data

1,000 records. In every record each characteristic takes one of its 1,000 members, uniformly at random, and the
amount is a whole number from 1 to 1,000. So about a third of each characteristic's members have no record and the
others one or a few, every record is a different key (the aDSO keeps all of them), and nothing correlates. The records
are built and loaded in packages of 100,000 (one at the default size): a request per package on the cube, a request
activated per package on the aDSO. The run ends by counting the rows of
the cube's fact table and the aDSO's reporting view and summing the amount, next to the generated totals.
