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
CLASS ltcl_model_gen DEFINITION DEFERRED.
CLASS zzxxmla1_cl_model_gen DEFINITION LOCAL FRIENDS ltcl_model_gen.

CLASS ltcl_model_gen DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    DATA cut TYPE REF TO zzxxmla1_cl_model_gen.

    METHODS setup.
    METHODS hierarchies_of
      IMPORTING model        TYPE zzxxmla1_cl_model_gen=>ty_model
                dim          TYPE string
      RETURNING VALUE(count) TYPE i.
    METHODS names_of_customer_objects FOR TESTING.
    METHODS names_of_sap_objects FOR TESTING.
    METHODS dictionary_types_to_schema FOR TESTING.
    METHODS unknown_cube_gives_empty_model FOR TESTING.
    " integration tests: read the BW metadata of the generated FoodMart cube ZFMSALES (nothing is written)
    METHODS foodmart_cube_and_measures FOR TESTING.
    METHODS foodmart_dimensions FOR TESTING.
    METHODS foodmart_hierarchies FOR TESTING.
    METHODS foodmart_level_types FOR TESTING.
ENDCLASS.

CLASS ltcl_model_gen IMPLEMENTATION.

  METHOD setup.
    cut = NEW #( ).
  ENDMETHOD.

  METHOD hierarchies_of.
    count = REDUCE i( INIT n = 0 FOR h IN model-hiers WHERE ( dim_name = dim ) NEXT n = n + 1 ).
  ENDMETHOD.

  METHOD names_of_customer_objects.
    cl_abap_unit_assert=>assert_equals( act = cut->column_name( 'ZFMSTORE' ) exp = '/BIC/ZFMSTORE' ).
    cl_abap_unit_assert=>assert_equals( act = cut->table_name( kind = 'P' iobjnm = 'ZFMSTORE' ) exp = '/BIC/PZFMSTORE' ).
    cl_abap_unit_assert=>assert_equals( act = cut->table_name( kind = 'S' iobjnm = 'ZFMSTORE' ) exp = '/BIC/SZFMSTORE' ).
  ENDMETHOD.

  METHOD names_of_sap_objects.
    " SAP objects drop their leading 0: 0D_NW_PROD -> /BI0/SD_NW_PROD
    cl_abap_unit_assert=>assert_equals( act = cut->column_name( '0D_NW_PROD' ) exp = '/BI0/D_NW_PROD' ).
    cl_abap_unit_assert=>assert_equals( act = cut->table_name( kind = 'S' iobjnm = '0D_NW_PROD' ) exp = '/BI0/SD_NW_PROD' ).
    cl_abap_unit_assert=>assert_equals( act = cut->table_name( kind = 'P' iobjnm = '0CALMONTH' ) exp = '/BI0/PCALMONTH' ).
  ENDMETHOD.

  METHOD dictionary_types_to_schema.
    cl_abap_unit_assert=>assert_equals( act = cut->schema_type( 'NUMC' ) exp = 'Numeric' ).
    cl_abap_unit_assert=>assert_equals( act = cut->schema_type( 'INT4' ) exp = 'Numeric' ).
    cl_abap_unit_assert=>assert_equals( act = cut->schema_type( 'DEC' ) exp = 'Numeric' ).
    cl_abap_unit_assert=>assert_equals( act = cut->schema_type( 'CHAR' ) exp = 'String' ).
    cl_abap_unit_assert=>assert_equals( act = cut->schema_type( 'DATS' ) exp = 'String' ).
    cl_abap_unit_assert=>assert_equals( act = cut->schema_type( '' ) exp = 'String' ).
  ENDMETHOD.

  METHOD unknown_cube_gives_empty_model.
    DATA(model) = cut->build( 'ZNOSUCHCUBE' ).
    cl_abap_unit_assert=>assert_initial( model ).
  ENDMETHOD.

  METHOD foodmart_cube_and_measures.
    DATA(model) = cut->build( 'ZFMSALES' ).
    cl_abap_unit_assert=>assert_equals( act = model-cube-fact_table exp = '/BIC/FZFMSALES' ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR m IN model-measures ( CONV #( m-meas_name ) ) )
      exp = VALUE string_table( ( `Unit Sales` ) ( `Store Cost` ) ( `Store Sales` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = model-measures[ meas_name = 'Unit Sales' ]-fact_column exp = '/BIC/ZFMUNITS' ).
    cl_abap_unit_assert=>assert_equals( act = model-measures[ meas_name = 'Unit Sales' ]-aggregator exp = 'sum' ).
  ENDMETHOD.

  METHOD foodmart_dimensions.
    DATA(model) = cut->build( 'ZFMSALES' ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR d IN model-dims ( CONV #( d-dim_name ) ) )
      exp = VALUE string_table( ( `Product` ) ( `Customer` ) ( `Store` ) ( `Promotion` ) ( `Date` ) ) ).
    DATA(store) = model-dims[ dim_name = 'Store' ].
    cl_abap_unit_assert=>assert_equals( act = store-characteristic exp = 'ZFMSTORE' ).
    cl_abap_unit_assert=>assert_equals( act = store-fk_column exp = 'SID_ZFMSTORE' ).
    cl_abap_unit_assert=>assert_equals( act = store-sid_table exp = '/BIC/SZFMSTORE' ).
    cl_abap_unit_assert=>assert_equals( act = store-attr_table exp = '/BIC/PZFMSTORE' ).
    cl_abap_unit_assert=>assert_equals( act = store-key_column exp = '/BIC/ZFMSTORE' ).
  ENDMETHOD.

  METHOD foodmart_hierarchies.
    DATA(model) = cut->build( 'ZFMSALES' ).
    " key hierarchy plus one hierarchy per attribute
    cl_abap_unit_assert=>assert_equals( act = hierarchies_of( model = model dim = `Product` ) exp = 7 ).
    cl_abap_unit_assert=>assert_equals( act = hierarchies_of( model = model dim = `Customer` ) exp = 9 ).
    cl_abap_unit_assert=>assert_equals( act = hierarchies_of( model = model dim = `Store` ) exp = 13 ).
    cl_abap_unit_assert=>assert_equals( act = hierarchies_of( model = model dim = `Promotion` ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = hierarchies_of( model = model dim = `Date` ) exp = 10 ).
    " the key hierarchy carries the dimension's name; every hierarchy has exactly one level
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( model-hiers[ dim_name = 'Store' hier_name = 'Store' ] ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( model-levels ) exp = lines( model-hiers ) ).
    cl_abap_unit_assert=>assert_equals(
      act = model-levels[ dim_name = 'Store' hier_name = 'Country' ]-key_column exp = '/BIC/ZFMCNTRY' ).
  ENDMETHOD.

  METHOD foodmart_level_types.
    DATA(model) = cut->build( 'ZFMSALES' ).
    cl_abap_unit_assert=>assert_equals(
      act = model-levels[ dim_name = 'Store' hier_name = 'Store Sqft' ]-data_type exp = 'Numeric' ).
    cl_abap_unit_assert=>assert_equals(
      act = model-levels[ dim_name = 'Date' hier_name = 'Year' ]-data_type exp = 'Numeric' ).
    " BW has no boolean: the coffee bar flag is a one-character string
    cl_abap_unit_assert=>assert_equals(
      act = model-levels[ dim_name = 'Store' hier_name = 'Has Coffee Bar' ]-data_type exp = 'String' ).
    " the keys are the FoodMart ids: NUMC characteristics, so numbers
    cl_abap_unit_assert=>assert_equals(
      act = model-levels[ dim_name = 'Store' hier_name = 'Store' ]-data_type exp = 'Numeric' ).
  ENDMETHOD.

ENDCLASS.