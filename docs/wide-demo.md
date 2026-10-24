# Wide demo

A demo data set for trying the schema builder and the engine on a wide model: one provider with 100 characteristics
(one of 100,000 members, the others of 1,000) and 1,000,000 records. It is made up by `ZZXXMLA1_CL_BW_WIDE_GEN` (a seeded pseudo-random generator,
the same records on every run), so it carries no third-party data and is under the project's license.

Run program `ZZXXMLA1_SETUP` with the checkbox "Also generate the wide demo"; "Demos: create the InfoCube" and
"Demos: create the aDSO" (`run( cube = ... adso = ... )`) choose the providers it creates and loads (it deletes both
either way). "Wide demo: records" (`run( records = ...
)` of the class) sets the number of records in each provider; 0 (the default) is 1,000,000. Most of a small run
goes to creating and activating the objects. A run with many records takes longer than a dialog work process may:
start the program in the background (F9). A run with 1,000,000 records (2026-10-13, job `ZZXXMLA1_WIDE_1M`) loaded the
cube in 20 requests of 50,000 and the aDSO in 20 requests, each activated. An earlier run with packages of 100,000 (2026-10-06) was cancelled
during the aDSO load without a short dump; a BW message raised as `ERROR_MESSAGE` now fails the load with the
message in the log instead of cancelling the job.

A run **deletes and creates** InfoArea `ZXMLWIDE`'s objects: the aDSO, the cube, the views of the characteristics (if
the schema builder generated any) and the InfoObjects `ZXMLAD00` to `ZXMLAD99` and `ZXMLAKF`. A catalog made for the
providers stays in `/WEB-INF/datasources.xml`.

## What it creates

- Characteristics `ZXMLAD00` to `ZXMLAD99` ("Dimension 00" ... "Dimension 99"), with master data and no attributes.
  `ZXMLAD00` is NUMC 6 with the members `000001` to `100000` in its attribute table (`/BIC/PZXMLAD00`): a level larger
  than eMondrian's bound on a split operand of a native crossjoin (15,000 members, which olap4abap does not have; see
  `docs/next-steps.md`). The others are NUMC 4 with the members `0001` to `1000`. Each also has BW's blank member.
- Key figure `ZXMLAKF` (Amount): a decimal number, summed.
- InfoCube `ZXMLWIDE`: an InfoCube has at most 13 dimensions of its own, so the characteristics are grouped ten to a
  BW dimension (`ZXMLWIDE1` holds `ZXMLAD00` to `ZXMLAD09`, ..., `ZXMLWIDEA` holds `ZXMLAD90` to `ZXMLAD99`).
- Cube-type aDSO `ZXMLWIDEA` with the same characteristics and records.
- No views, schema or catalog: make them with the schema builder (`/zzxxmla1/schema`, `docs/schema-generator.md`).
  The reference server has no copy of the wide demo (its schema and tables were removed on 2026-10-13, when the views
  got BW's NUMC values; the schemas made before named the numbers).

## The data

1,000,000 records. In every record each characteristic takes one of its members, uniformly at random, and the
amount is a whole number from 1 to 1,000. So each member of a characteristic of 1,000 has about 1,000 records
and each of `ZXMLAD00`'s 100,000 about 10 (with 1,000 records: a third of the members of 1,000 have none, and at most
1,000 of `ZXMLAD00`'s have one), every record is a different key (the aDSO keeps all of them), and nothing correlates. The records
are built and loaded in packages of 50,000 (20 at the default size; each package's table is freed after its load): a request per package on the cube, a request
activated per package on the aDSO. The run ends by counting the rows of
the cube's fact table and the aDSO's reporting view and summing the amount, next to the generated totals.
