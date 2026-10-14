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
"! The handler's helpers that need no repository, schema or database.
CLASS ltc_xmla_handler DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    METHODS unsupported_statements FOR TESTING.
    METHODS supported_statements FOR TESTING.
    METHODS discover_key FOR TESTING.
ENDCLASS.

CLASS zzxxmla1_cl_xmla_handler DEFINITION LOCAL FRIENDS ltc_xmla_handler.

CLASS ltc_xmla_handler IMPLEMENTATION.

  METHOD unsupported_statements.
    " what Excel sends when members of a PivotTable are grouped
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_xmla_handler=>unsupported_statement(
              `CREATE SESSION CUBE [0D_NW_C01_XL_GROUPING0] FROM [0D_NW_C01] ( MEASURE [0D_NW_C01].[Cost] )` )
      exp = `CREATE SESSION CUBE` ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_xmla_handler=>unsupported_statement( |  create\n  session\tcube[X] FROM [Sales]| )
      exp = `CREATE SESSION CUBE` ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_xmla_handler=>unsupported_statement( `CREATE SUBCUBE [Sales] AS SELECT {} ON 0 FROM [Sales]` )
      exp = `CREATE SUBCUBE` ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_xmla_handler=>unsupported_statement( `DROP SUBCUBE [Sales]` )
      exp = `DROP SUBCUBE` ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_xmla_handler=>unsupported_statement( `ALTER CUBE [Sales] CREATE DIMENSION MEMBER [X].[Y]` )
      exp = `ALTER CUBE` ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_xmla_handler=>unsupported_statement( `DROP CUBE [0D_NW_C01_XL_GROUPING0]` )
      exp = `DROP CUBE` ).
  ENDMETHOD.

  METHOD supported_statements.
    " the grammar's own statements, and names that only start like a cube keyword, go to the parser
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_xmla_handler=>unsupported_statement(
      `CREATE SESSION MEMBER [Sales].[Measures].[X] AS 1` ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_xmla_handler=>unsupported_statement(
      `CREATE SESSION SET [Sales].[S] AS {}` ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_xmla_handler=>unsupported_statement(
      `SELECT FROM [Sales]` ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_xmla_handler=>unsupported_statement(
      `CREATE SESSION CUBES` ) ).
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_xmla_handler=>unsupported_statement( `` ) ).
  ENDMETHOD.

  METHOD discover_key.
    DATA(request) = VALUE zzxxmla1_cl_xmla_handler=>ty_request(
      method       = `DISCOVER`
      type         = `MDSCHEMA_CUBES`
      restrictions = VALUE #( ( name = `CATALOG_NAME` value = `FoodMart` ) )
      properties   = VALUE #( ( name = `Catalog` value = `FoodMart` ) ( name = `Content` value = `Data` ) )
      session_id   = `abc` ).
    DATA(key) = zzxxmla1_cl_xmla_handler=>discover_key( request = request url = `http://x/zzxxmla1` ).
    cl_abap_unit_assert=>assert_equals(
      act = key
      exp = |DISCOVER MDSCHEMA_CUBES\nURL http://x/zzxxmla1\nR CATALOG_NAME=FoodMart\nP Catalog=FoodMart\nP Content=Data| ).
    " another session asks the same
    request-session_id = `def`.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_xmla_handler=>discover_key( request = request url = `http://x/zzxxmla1` )
                                        exp = key ).
    " a restriction is not a property
    DATA(other) = request.
    other-restrictions = VALUE #( ).
    other-properties = VALUE #( ( name = `CATALOG_NAME` value = `FoodMart` ) ( LINES OF request-properties ) ).
    cl_abap_unit_assert=>assert_differs( act = zzxxmla1_cl_xmla_handler=>discover_key( request = other url = `http://x/zzxxmla1` )
                                         exp = key ).
    " another URL
    cl_abap_unit_assert=>assert_differs( act = zzxxmla1_cl_xmla_handler=>discover_key( request = request url = `http://y/zzxxmla1` )
                                         exp = key ).
  ENDMETHOD.

ENDCLASS.
