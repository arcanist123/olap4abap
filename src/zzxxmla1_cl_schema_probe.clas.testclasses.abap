*----------------------------------------------------------------------------------------------------------------------*
* olap4abap - XMLA server with an MDX engine for SAP BW               https://github.com/arcanist123/olap4abap
* Copyright (c) 2026 the olap4abap authors
*
* This program and the accompanying materials are made available under the terms of the Eclipse Public License 2.0,
* which is available at https://www.eclipse.org/legal/epl-2.0/
* SPDX-License-Identifier: EPL-2.0
*
* olap4abap contains code derived from Mondrian (Eclipse Public License 1.0): Copyright (C) 1998-2005 Julian Hyde,
* Copyright (C) 2005-2021 Hitachi Vantara and others, Copyright (C) 2021-2025 Sergei Semenkov. See the NOTICE file.
*----------------------------------------------------------------------------------------------------------------------*
CLASS ltc_schema_probe DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    "! the clinic's fiscal period, compounded with the variant
    METHODS period
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_view_gen=>ty_metadata.
    "! the special periods excluded
    METHODS regular
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_selection=>ty_t_row.

    "! InfoCube: the SIDs grouped on the facts filtered on the variant's SID table, then the excluded keys
    METHODS cube FOR TESTING RAISING cx_static_check.
    "! aDSO: the values grouped where the selection excludes them, nothing filtered
    METHODS adso FOR TESTING RAISING cx_static_check.
    "! a characteristic that is no field of the facts: nothing to probe
    METHODS no_field FOR TESTING RAISING cx_static_check.
    "! the refusal lists the values per characteristic; none if all are ok
    METHODS refusal FOR TESTING RAISING cx_static_check.
ENDCLASS.


CLASS ltc_schema_probe IMPLEMENTATION.

  METHOD period.
    result-characteristic = 'ZCLFISCPR'.
    result-tables-basic = 'ZCLFISCPR'.
    result-tables-sids = '/BIC/SZCLFISCPR'.
    result-tables-key_field = '/BIC/ZCLFISCPR'.
    result-compounding = VALUE #( ( iobjnm = 'ZCLFISCVR' field = '/BIC/ZCLFISCVR' ) ).
  ENDMETHOD.

  METHOD regular.
    result = VALUE #( ( sign = 'E' option = 'CP' low = '*013' ) ( sign = 'E' option = 'CP' low = '*014' ) ).
  ENDMETHOD.

  METHOD cube.
    DATA(facts) = VALUE zzxxmla1_cl_bw_view_gen=>ty_fact_metadata(
      provider   = 'ZCLVISIT'
      cube       = abap_true
      fact_table = '/BIC/FZCLVISIT'
      fields     = VALUE #( ( field = 'SID_ZCLFISCPR' iobjnm = 'ZCLFISCPR' )
                            ( field = 'SID_ZCLFISCVR' iobjnm = 'ZCLFISCVR' ) )
      filtered   = VALUE #( ( iobjnm    = 'ZCLFISCVR'
                              rows      = zzxxmla1_cl_bw_selection=>equals( `K4` )
                              sids      = '/BIC/SZCLFISCVR'
                              key_field = '/BIC/ZCLFISCVR' ) ) ).
    DATA(query) = zzxxmla1_cl_schema_probe=>build_query( facts = facts characteristic = period( ) rows = regular( ) ).
    cl_abap_unit_assert=>assert_equals( act = query-columns exp = 3 ).
    cl_abap_unit_assert=>assert_equals(
      act = query-sql
      exp = `SELECT s."/BIC/ZCLFISCVR", s."/BIC/ZCLFISCPR", p.probe_facts ` &&
            `FROM ( SELECT a."SID_ZCLFISCPR" AS probe_sid, COUNT(*) AS probe_facts FROM "/BIC/FZCLVISIT" AS a ` &&
            `INNER JOIN "/BIC/SZCLFISCVR" AS f1 ON f1."SID" = a."SID_ZCLFISCVR" ` &&
            `WHERE f1."/BIC/ZCLFISCVR" = 'K4' GROUP BY a."SID_ZCLFISCPR" ) AS p ` &&
            `INNER JOIN "/BIC/SZCLFISCPR" AS s ON s."SID" = p.probe_sid ` &&
            `WHERE NOT ( s."/BIC/ZCLFISCPR" not like '%013' and s."/BIC/ZCLFISCPR" not like '%014' ) ` &&
            `ORDER BY s."/BIC/ZCLFISCVR", s."/BIC/ZCLFISCPR" LIMIT 20` ).
  ENDMETHOD.

  METHOD adso.
    DATA(facts) = VALUE zzxxmla1_cl_bw_view_gen=>ty_fact_metadata(
      provider   = 'ZCLVISITA'
      fact_table = '/BIC/AZCLVISITA7'
      fields     = VALUE #( ( field = 'ZCLFISCPR' iobjnm = 'ZCLFISCPR' )
                            ( field = 'ZCLFISCVR' iobjnm = 'ZCLFISCVR' ) ) ).
    DATA(query) = zzxxmla1_cl_schema_probe=>build_query( facts = facts characteristic = period( ) rows = regular( ) ).
    cl_abap_unit_assert=>assert_equals( act = query-columns exp = 3 ).
    cl_abap_unit_assert=>assert_equals(
      act = query-sql
      exp = `SELECT a."ZCLFISCVR", a."ZCLFISCPR", COUNT(*) FROM "/BIC/AZCLVISITA7" AS a ` &&
            `WHERE NOT ( a."ZCLFISCPR" not like '%013' and a."ZCLFISCPR" not like '%014' ) ` &&
            `GROUP BY a."ZCLFISCVR", a."ZCLFISCPR" ORDER BY a."ZCLFISCVR", a."ZCLFISCPR" LIMIT 20` ).
  ENDMETHOD.

  METHOD no_field.
    DATA(facts) = VALUE zzxxmla1_cl_bw_view_gen=>ty_fact_metadata(
      provider   = 'ZCLVISITA'
      fact_table = '/BIC/AZCLVISITA7'
      fields     = VALUE #( ( field = 'ZCLFISCVR' iobjnm = 'ZCLFISCVR' ) ) ).
    cl_abap_unit_assert=>assert_initial(
      zzxxmla1_cl_schema_probe=>build_query( facts = facts characteristic = period( ) rows = regular( ) ) ).
  ENDMETHOD.

  METHOD refusal.
    DATA(cubes) = VALUE zzxxmla1_cl_schema_probe=>ty_t_cube(
      ( cube = `ZCLVISIT` ok = abap_true
        characteristics = VALUE #( ( name = `ZCLFISCVR` ok = abap_true ) ) ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_schema_probe=>refusal( cubes ) ).
    APPEND VALUE #( cube = `ZCLVISITA` ok = abap_false
                    characteristics = VALUE #( ( name   = `ZCLFISCPR`
                                                 ok     = abap_false
                                                 values = VALUE #( ( value = `K4/2024013` facts = 12 )
                                                                   ( value = `K4/2025013` facts = 3 ) ) ) ) )
      TO cubes.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_schema_probe=>refusal( cubes )
      exp = `Cube 'ZCLVISITA' restricts the members of ZCLFISCPR, but its facts hold values its selection ` &&
            `excludes: K4/2024013 (12 facts), K4/2025013 (3 facts). Filter the cube on it instead, or widen the ` &&
            `selection` ).
  ENDMETHOD.

ENDCLASS.
