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
CLASS ltc_schema_fix DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    TYPES ty_provider TYPE zzxxmla1_cl_bw_provider=>ty_provider.

    "! the clinic cube's fiscal time as the proposal makes it, a user hierarchy on the period, nothing fixed
    METHODS plain_schema
      RETURNING VALUE(result) TYPE zzxxmla1_cl_schema_def=>ty_schema
      RAISING   cx_static_check.
    "! ZCLVISIT read for nothing fixed: its fact table, the views of the variant and of the compounded period
    METHODS plain_provider
      RETURNING VALUE(result) TYPE ty_provider.
    "! ZCLVISIT read with the variant fixed to K4: the fact view and the views not generated yet, the period not
    "! compounded
    METHODS k4_provider
      RETURNING VALUE(result) TYPE ty_provider.
    "! ZCLVISIT read with the period's special periods excluded, restrict members: its facts as they are, the period
    "! on its view for the selection, not generated yet, still compounded
    METHODS regular_periods_provider
      RETURNING VALUE(result) TYPE ty_provider.
    "! the selection of the cube's annotations
    METHODS annotations
      IMPORTING cube          TYPE zzxxmla1_cl_schema_def=>ty_cube
      RETURNING VALUE(result) TYPE zzxxmla1_cl_schema_def=>ty_t_annotation.
    "! the dimension of the schema of that name
    METHODS dimension
      IMPORTING !schema       TYPE zzxxmla1_cl_schema_def=>ty_schema
                !name         TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_schema_def=>ty_dimension.

    "! fixing: annotation, facts, measure column, the views of the variant and the period, the period named by its own
    "! key; the user's hierarchy and names stay
    METHODS fix FOR TESTING RAISING cx_static_check.
    "! un-fixing gives the plain schema back
    METHODS round_trip FOR TESTING RAISING cx_static_check.
    "! a cube on other facts than the provider's is refused
    METHODS other_facts FOR TESTING RAISING cx_static_check.
    "! the characteristics with the dimensions on them and their selections
    METHODS characteristics FOR TESTING RAISING cx_static_check.
    "! the annotation of fixing, olap4abap.fixed.C = v, is filter the cube with I EQ v, and written with the new name
    METHODS fixed_annotation FOR TESTING RAISING cx_static_check.
    "! restrict members: the annotation olap4abap.members.C with the rows, the facts and the measures as they are, the
    "! period's own view replaced
    METHODS members_mode FOR TESTING RAISING cx_static_check.
    "! two selections of a characteristic are refused
    METHODS two_selections FOR TESTING RAISING cx_static_check.
ENDCLASS.


CLASS ltc_schema_fix IMPLEMENTATION.

  METHOD plain_schema.
    result = zzxxmla1_cl_schema_def=>parse(
      `<Schema name="ZCLVISIT">` &&
      `<Dimension name="ZCLFISCVR" caption="Fiscal Year Variant" table="ZZXXMLA1V0000001">` &&
      `<DimensionAttribute name="ZCLFISCVR SID" usage="Key" attributeHierarchyEnabled="false">` &&
      `<KeyColumn dataType="Integer" columnName="SID"/><NameColumn dataType="String" columnName="ZCLFISCVR"/>` &&
      `</DimensionAttribute>` &&
      `<DimensionAttribute name="ZCLFISCVR Key" attributeHierarchyEnabled="false">` &&
      `<KeyColumn dataType="String" columnName="ZCLFISCVR"/></DimensionAttribute>` &&
      `<Hierarchy hasAll="true"><Level name="ZCLFISCVR" sourceAttribute="ZCLFISCVR SID" nameColumn="ZCLFISCVR"/>` &&
      `</Hierarchy>` &&
      `</Dimension>` &&
      `<Dimension name="ZCLFISCPR" caption="Fiscal Period" table="ZZXXMLA1V0000002">` &&
      `<DimensionAttribute name="ZCLFISCPR SID" usage="Key" attributeHierarchyEnabled="false">` &&
      `<KeyColumn dataType="Integer" columnName="SID"/><OrderByColumn dataType="String" columnName="COMPOUND_KEY"/>` &&
      `<NameColumn dataType="String" columnName="COMPOUND_KEY"/></DimensionAttribute>` &&
      `<DimensionAttribute name="ZCLFISCPR Key" attributeHierarchyEnabled="false">` &&
      `<KeyColumn dataType="String" columnName="ZCLFISCPR"/></DimensionAttribute>` &&
      `<Hierarchy name="Periods" hasAll="true">` &&
      `<Level name="Period" sourceAttribute="ZCLFISCPR SID" nameColumn="COMPOUND_KEY"/></Hierarchy>` &&
      `</Dimension>` &&
      `<Cube name="ZCLVISIT" caption="Clinic Visits">` &&
      `<Table name="/BIC/FZCLVISIT"/>` &&
      `<DimensionUsage name="Variant" source="ZCLFISCVR" foreignKey="SID_ZCLFISCVR"/>` &&
      `<DimensionUsage name="ZCLFISCPR" source="ZCLFISCPR" foreignKey="SID_ZCLFISCPR"/>` &&
      `<Measure name="Visits" column="/BIC/ZCLVISNO" aggregator="sum"/>` &&
      `</Cube>` &&
      `</Schema>` ).
  ENDMETHOD.

  METHOD plain_provider.
    result = VALUE #(
      name            = `ZCLVISIT`
      kind            = zzxxmla1_cl_bw_provider=>c_kind-cube
      fact_table      = `/BIC/FZCLVISIT`
      characteristics = VALUE #(
        ( iobjnm      = `ZCLFISCVR` text = `Fiscal Year Variant` basic = `ZCLFISCVR` has_sids = abap_true
          fact_sid    = abap_true fact_column = VALUE #( name = `SID_ZCLFISCVR` datatype = `INT4` )
          view        = `ZZXXMLA1V0000001` key_column = VALUE #( name = `ZCLFISCVR` datatype = `CHAR` length = 2 ) )
        ( iobjnm      = `ZCLFISCPR` text = `Fiscal Period` basic = `ZCLFISCPR` has_sids = abap_true
          fact_sid    = abap_true fact_column = VALUE #( name = `SID_ZCLFISCPR` datatype = `INT4` )
          view        = `ZZXXMLA1V0000002` key_column = VALUE #( name = `ZCLFISCPR` datatype = `NUMC` length = 7 )
          name_column = VALUE #( name = `COMPOUND_KEY` datatype = `CHAR` length = 10 )
          compounding = VALUE #( ( `ZCLFISCVR` ) ) ) )
      key_figures     = VALUE #( ( iobjnm = `ZCLVISNO` fact_column = VALUE #( name = `/BIC/ZCLVISNO` datatype = `DEC` ) ) ) ).
  ENDMETHOD.

  METHOD k4_provider.
    result = plain_provider( ).
    result-fact_table = `ZZXXMLA1_F_ZCLVISIT`.
    result-selection = VALUE #( ( iobjnm = 'ZCLFISCVR'
                                  mode   = zzxxmla1_cl_bw_selection=>c_mode-filter
                                  rows   = zzxxmla1_cl_bw_selection=>equals( `K4` ) ) ).
    LOOP AT result-characteristics ASSIGNING FIELD-SYMBOL(<characteristic>).
      CLEAR: <characteristic>-view, <characteristic>-name_column.
    ENDLOOP.
    result-key_figures[ 1 ]-fact_column-name = `ZCLVISNO`.
  ENDMETHOD.

  METHOD regular_periods_provider.
    result = plain_provider( ).
    result-selection = VALUE #( ( iobjnm = 'ZCLFISCPR'
                                  mode   = zzxxmla1_cl_bw_selection=>c_mode-members
                                  rows   = VALUE #( ( sign = 'E' option = 'CP' low = `*013` )
                                                    ( sign = 'E' option = 'CP' low = `*014` ) ) ) ).
    CLEAR result-characteristics[ 2 ]-view.
  ENDMETHOD.

  METHOD annotations.
    IF cube-annotations IS BOUND.
      result = cube-annotations->array.
    ENDIF.
  ENDMETHOD.

  METHOD dimension.
    READ TABLE schema-dimensions INTO result WITH KEY name = name.
    cl_abap_unit_assert=>assert_subrc( msg = |no dimension { name }| ).
  ENDMETHOD.

  METHOD fix.
    DATA(schema) = plain_schema( ).
    DATA(result) = zzxxmla1_cl_schema_fix=>apply( EXPORTING cube   = `ZCLVISIT`
                                                            old    = plain_provider( )
                                                            new    = k4_provider( )
                                                  CHANGING  schema = schema ).
    DATA(cube) = schema-cubes[ 1 ].
    cl_abap_unit_assert=>assert_equals(
      act = annotations( cube )
      exp = VALUE zzxxmla1_cl_schema_def=>ty_t_annotation( ( name = `olap4abap.filter.ZCLFISCVR` cdata = `I EQ 'K4'` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_schema_fix=>cube_selection( cube )
                                        exp = k4_provider( )-selection ).
    DATA(fact) = CAST zzxxmla1_cl_schema_def=>ty_table( cube-fact-def ).
    cl_abap_unit_assert=>assert_equals( act = fact->name exp = `ZZXXMLA1_F_ZCLVISIT` ).
    cl_abap_unit_assert=>assert_equals( act = cube-measures[ 1 ]-column exp = `ZCLVISNO` ).
    cl_abap_unit_assert=>assert_equals( act = cube-measures[ 1 ]-name exp = `Visits` ).
    " the variant keeps its dimension, on its view filtered on K4
    cl_abap_unit_assert=>assert_equals( act = lines( cube-dimensions ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = dimension( schema = schema name = `ZCLFISCVR` )-table
                                        exp = `ZZXXMLA1_C_ZCLFISCVR` ).
    " the period: its own key, no order by COMPOUND_KEY; the user's hierarchy stays
    DATA(period) = dimension( schema = schema name = `ZCLFISCPR` ).
    cl_abap_unit_assert=>assert_equals( act = period-table exp = `ZZXXMLA1_C_ZCLFISCPR` ).
    DATA(key) = period-attributes[ name = `ZCLFISCPR SID` ].
    cl_abap_unit_assert=>assert_equals( act = key-name_column->column_name exp = `ZCLFISCPR` ).
    cl_abap_unit_assert=>assert_equals( act = key-name_column->data_type exp = `String` ).
    cl_abap_unit_assert=>assert_not_bound( key-order_by_column ).
    cl_abap_unit_assert=>assert_equals( act = period-hierarchies[ 1 ]-name exp = `Periods` ).
    cl_abap_unit_assert=>assert_equals( act = period-hierarchies[ 1 ]-levels[ 1 ]-name_column exp = `ZCLFISCPR` ).
    cl_abap_unit_assert=>assert_equals(
      act = result-tables
      exp = VALUE zzxxmla1_cl_schema_fix=>ty_t_replaced( ( from = `/BIC/FZCLVISIT` to = `ZZXXMLA1_F_ZCLVISIT` )
                                                         ( from = `ZZXXMLA1V0000001` to = `ZZXXMLA1_C_ZCLFISCVR` )
                                                         ( from = `ZZXXMLA1V0000002` to = `ZZXXMLA1_C_ZCLFISCPR` ) ) ).
  ENDMETHOD.

  METHOD round_trip.
    DATA(schema) = plain_schema( ).
    DATA(plain) = zzxxmla1_cl_schema_def=>to_xml( schema ).
    zzxxmla1_cl_schema_fix=>apply( EXPORTING cube   = `ZCLVISIT`
                                             old    = plain_provider( )
                                             new    = k4_provider( )
                                   CHANGING  schema = schema ).
    cl_abap_unit_assert=>assert_differs( act = zzxxmla1_cl_schema_def=>to_xml( schema ) exp = plain ).
    zzxxmla1_cl_schema_fix=>apply( EXPORTING cube   = `ZCLVISIT`
                                             old    = k4_provider( )
                                             new    = plain_provider( )
                                   CHANGING  schema = schema ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_schema_def=>to_xml( schema ) exp = plain ).
  ENDMETHOD.

  METHOD other_facts.
    DATA(schema) = plain_schema( ).
    DATA(fact) = CAST zzxxmla1_cl_schema_def=>ty_table( schema-cubes[ 1 ]-fact-def ).
    fact->name = `/BIC/FZOTHER`.
    TRY.
        zzxxmla1_cl_schema_fix=>apply( EXPORTING cube   = `ZCLVISIT`
                                                 old    = plain_provider( )
                                                 new    = k4_provider( )
                                       CHANGING  schema = schema ).
        cl_abap_unit_assert=>fail( `other facts accepted` ).
      CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
        cl_abap_unit_assert=>assert_char_cp( act = error->get_text( ) exp = `*/BIC/FZOTHER*ZCLVISIT*` ).
    ENDTRY.
  ENDMETHOD.

  METHOD characteristics.
    DATA(schema) = plain_schema( ).
    zzxxmla1_cl_schema_fix=>apply( EXPORTING cube   = `ZCLVISIT`
                                             old    = plain_provider( )
                                             new    = k4_provider( )
                                   CHANGING  schema = schema ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_schema_fix=>characteristics( cube = schema-cubes[ 1 ] provider = k4_provider( ) )
      exp = VALUE zzxxmla1_cl_schema_fix=>ty_t_characteristic(
              ( name = `ZCLFISCVR` text = `Fiscal Year Variant` foreign_key = `SID_ZCLFISCVR`
                dimension = `ZCLFISCVR` shared = abap_true
                mode = zzxxmla1_cl_bw_selection=>c_mode-filter rows = zzxxmla1_cl_bw_selection=>equals( `K4` )
                fixed = abap_true value = `K4` )
              ( name = `ZCLFISCPR` text = `Fiscal Period` compounding = VALUE #( ( `ZCLFISCVR` ) )
                foreign_key = `SID_ZCLFISCPR`
                dimension = `ZCLFISCPR` shared = abap_true ) ) ).
  ENDMETHOD.

  METHOD fixed_annotation.
    " a schema fixed before selections: the K4 tables, the old annotation
    DATA(schema) = plain_schema( ).
    zzxxmla1_cl_schema_fix=>apply( EXPORTING cube   = `ZCLVISIT`
                                             old    = plain_provider( )
                                             new    = k4_provider( )
                                   CHANGING  schema = schema ).
    schema-cubes[ 1 ]-annotations = NEW #( array = VALUE zzxxmla1_cl_schema_def=>ty_t_annotation( ( name = `olap4abap.fixed.ZCLFISCVR` cdata = `K4` )
                                                            ( name = `other` cdata = `stays` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_schema_fix=>cube_selection( schema-cubes[ 1 ] )
                                        exp = k4_provider( )-selection ).
    " the same selection again: only the annotation's name changes
    zzxxmla1_cl_schema_fix=>apply( EXPORTING cube   = `ZCLVISIT`
                                             old    = k4_provider( )
                                             new    = k4_provider( )
                                   CHANGING  schema = schema ).
    cl_abap_unit_assert=>assert_equals(
      act = annotations( schema-cubes[ 1 ] )
      exp = VALUE zzxxmla1_cl_schema_def=>ty_t_annotation( ( name = `other` cdata = `stays` )
                                                           ( name = `olap4abap.filter.ZCLFISCVR` cdata = `I EQ 'K4'` ) ) ).
  ENDMETHOD.

  METHOD members_mode.
    DATA(schema) = plain_schema( ).
    DATA(result) = zzxxmla1_cl_schema_fix=>apply( EXPORTING cube   = `ZCLVISIT`
                                                            old    = plain_provider( )
                                                            new    = regular_periods_provider( )
                                                  CHANGING  schema = schema ).
    DATA(cube) = schema-cubes[ 1 ].
    cl_abap_unit_assert=>assert_equals(
      act = annotations( cube )
      exp = VALUE zzxxmla1_cl_schema_def=>ty_t_annotation( ( name  = `olap4abap.members.ZCLFISCPR`
                                                             cdata = `E CP '*013';E CP '*014'` ) ) ).
    DATA(fact) = CAST zzxxmla1_cl_schema_def=>ty_table( cube-fact-def ).
    cl_abap_unit_assert=>assert_equals( act = fact->name exp = `/BIC/FZCLVISIT` ).
    cl_abap_unit_assert=>assert_equals( act = cube-measures[ 1 ]-column exp = `/BIC/ZCLVISNO` ).
    " the period still compounded, on its view for the selection
    DATA(period) = dimension( schema = schema name = `ZCLFISCPR` ).
    cl_abap_unit_assert=>assert_equals( act = period-attributes[ name = `ZCLFISCPR SID` ]-name_column->column_name
                                        exp = `COMPOUND_KEY` ).
    cl_abap_unit_assert=>assert_equals(
      act = result-tables
      exp = VALUE zzxxmla1_cl_schema_fix=>ty_t_replaced( ( from = `ZZXXMLA1V0000002` to = `ZZXXMLA1_C_ZCLFISCPR` ) ) ).
  ENDMETHOD.

  METHOD two_selections.
    DATA(schema) = plain_schema( ).
    schema-cubes[ 1 ]-annotations = NEW #( array = VALUE zzxxmla1_cl_schema_def=>ty_t_annotation( ( name = `olap4abap.fixed.ZCLFISCVR` cdata = `K4` )
                                                            ( name = `olap4abap.members.ZCLFISCVR` cdata = `I EQ 'K1'` ) ) ).
    TRY.
        zzxxmla1_cl_schema_fix=>cube_selection( schema-cubes[ 1 ] ).
        cl_abap_unit_assert=>fail( `two selections accepted` ).
      CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
        cl_abap_unit_assert=>assert_char_cp( act = error->get_text( ) exp = `*two selections of ZCLFISCVR*` ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
