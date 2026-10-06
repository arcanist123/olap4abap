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
"! The proposal for provider metadata as ZZXXMLA1_CL_BW_PROVIDER reads it, built by hand after the FoodMart providers
"! ZFMSALESA (aDSO) and ZFMSALES (InfoCube), so no BW object is needed.
CLASS ltc_proposal DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    TYPES ty_provider TYPE zzxxmla1_cl_bw_provider=>ty_provider.

    "! a store characteristic with a name, a NUMC and a date attribute, and a key figure of each kind
    METHODS adso
      RETURNING VALUE(result) TYPE ty_provider.
    METHODS shared_dimension_of_adso FOR TESTING RAISING cx_static_check.
    METHODS key_by_sid_on_infocube FOR TESTING RAISING cx_static_check.
    METHODS time_characteristics FOR TESTING RAISING cx_static_check.
    METHODS measures_and_notes FOR TESTING RAISING cx_static_check.
    METHODS names_are_unique FOR TESTING RAISING cx_static_check.
    METHODS view_not_generated_yet FOR TESTING RAISING cx_static_check.
    METHODS suggestions FOR TESTING RAISING cx_static_check.
    METHODS data_types FOR TESTING.
ENDCLASS.

CLASS ltc_proposal IMPLEMENTATION.

  METHOD adso.
    result = VALUE #(
      name = `ZFMSALESA` kind = zzxxmla1_cl_bw_provider=>c_kind-adso text = `FoodMart Sales (aDSO)`
      fact_table = `/BIC/AZFMSALESA7`
      characteristics = VALUE #(
        ( iobjnm = `ZFMSTORE` text = `Store` iobjtp = `CHA` has_sids = abap_true view = `ZZXXMLA1V0000003`
          fact_column = VALUE #( name = `/BIC/ZFMSTORE` datatype = `NUMC` length = 10 )
          key_column = VALUE #( name = `ZFMSTORE` datatype = `NUMC` length = 10 )
          attributes = VALUE #( ( iobjnm = `ZFMSNAME` text = `Store Name`
                                  column = VALUE #( name = `ZFMSNAME` datatype = `CHAR` length = 60 ) )
                                ( iobjnm = `ZFMSQFT` text = `Store Sqft`
                                  column = VALUE #( name = `ZFMSQFT` datatype = `NUMC` length = 60 ) )
                                ( iobjnm = `ZFMOPEN` text = `Opened`
                                  column = VALUE #( name = `ZFMOPEN` datatype = `DATS` length = 8 ) ) ) )
        ( iobjnm = `0CALDAY` text = `Calendar Day` iobjtp = `TIM`
          fact_column = VALUE #( name = `CALDAY` datatype = `DATS` length = 8 ) )
        ( iobjnm = `0CALWEEK` text = `Calendar Year/Week` iobjtp = `TIM` has_sids = abap_true
          fact_column = VALUE #( name = `CALWEEK` datatype = `NUMC` length = 6 )
          key_column = VALUE #( name = `CALWEEK` datatype = `NUMC` length = 6 ) )
        ( iobjnm = `0CALMONTH` text = `Calendar Year/Month` iobjtp = `TIM` has_sids = abap_true
          fact_column = VALUE #( name = `CALMONTH` datatype = `NUMC` length = 6 )
          key_column = VALUE #( name = `CALMONTH` datatype = `NUMC` length = 6 ) )
        ( iobjnm = `0CALYEAR` text = `Calendar Year` iobjtp = `TIM` has_sids = abap_true
          fact_column = VALUE #( name = `CALYEAR` datatype = `NUMC` length = 4 )
          key_column = VALUE #( name = `CALYEAR` datatype = `NUMC` length = 4 ) ) )
      key_figures = VALUE #(
        ( iobjnm = `ZFMUNITS` text = `Unit Sales` aggregation = `SUM` exception_aggregation = `SUM`
          fact_column = VALUE #( name = `/BIC/ZFMUNITS` datatype = `DEC` length = 28 ) )
        ( iobjnm = `ZFMPEAK` text = `Peak` aggregation = `MAX` exception_aggregation = `MAX`
          fact_column = VALUE #( name = `/BIC/ZFMPEAK` datatype = `DEC` length = 28 ) )
        ( iobjnm = `ZFMAVG` text = `Average` aggregation = `SUM` exception_aggregation = `AVG`
          fact_column = VALUE #( name = `/BIC/ZFMAVG` datatype = `DEC` length = 28 ) )
        ( iobjnm = `ZFMSTOCK` text = `Stock` aggregation = `SUM` exception_aggregation = `SUM` non_cumulative = abap_true
          fact_column = VALUE #( name = `/BIC/ZFMSTOCK` datatype = `DEC` length = 28 ) ) )
      notes = VALUE #( ( iobjnm = `0CURRENCY` reason = `unit or currency` ) ) ).
  ENDMETHOD.

  METHOD shared_dimension_of_adso.
    DATA(schema) = NEW zzxxmla1_cl_schema_proposal( )->propose( adso( ) )-schema.
    cl_abap_unit_assert=>assert_equals( act = schema-name exp = `ZFMSALESA` ).
    DATA(store) = schema-dimensions[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = store-name exp = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = store-table exp = `ZZXXMLA1V0000003` ).
    cl_abap_unit_assert=>assert_initial( store-hierarchies ).
    cl_abap_unit_assert=>assert_equals( act = lines( store-attributes ) exp = 4 ).
    " the key: the characteristic's value, the column the aDSO's fact column joins
    DATA(key) = store-attributes[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = key-name exp = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = key-usage exp = `Key` ).
    cl_abap_unit_assert=>assert_equals( act = key-key_column->column_name exp = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_equals( act = key-key_column->data_type exp = `Numeric` ).
    cl_abap_unit_assert=>assert_not_bound( key-name_column ).
    cl_abap_unit_assert=>assert_equals( act = store-attributes[ 2 ]-name exp = `Store Name` ).
    cl_abap_unit_assert=>assert_equals( act = store-attributes[ 2 ]-key_column->data_type exp = `String` ).
    cl_abap_unit_assert=>assert_equals( act = store-attributes[ 3 ]-key_column->column_name exp = `ZFMSQFT` ).
    cl_abap_unit_assert=>assert_equals( act = store-attributes[ 3 ]-key_column->data_type exp = `Numeric` ).
    " only the key is a hierarchy, as the Store dimension of the reference's FoodMart has one
    cl_abap_unit_assert=>assert_equals( act = key-attribute_hierarchy_enabled exp = abap_undefined ).
    cl_abap_unit_assert=>assert_equals( act = store-attributes[ 2 ]-attribute_hierarchy_enabled exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = store-attributes[ 4 ]-attribute_hierarchy_enabled exp = abap_false ).

    DATA(cube) = schema-cubes[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = cube-name exp = `ZFMSALESA` ).
    cl_abap_unit_assert=>assert_equals( act = cube-caption exp = `FoodMart Sales (aDSO)` ).
    DATA(fact) = CAST zzxxmla1_cl_schema_def=>ty_table( cube-fact-def ).
    cl_abap_unit_assert=>assert_equals( act = fact->name exp = `/BIC/AZFMSALESA7` ).
    cl_abap_unit_assert=>assert_equals( act = cube-dimensions[ 1 ]-name exp = `DimensionUsage` ).
    DATA(usage) = CAST zzxxmla1_cl_schema_def=>ty_dimension_usage( cube-dimensions[ 1 ]-def ).
    cl_abap_unit_assert=>assert_equals( act = usage->name exp = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = usage->source exp = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = usage->foreign_key exp = `/BIC/ZFMSTORE` ).
  ENDMETHOD.

  METHOD key_by_sid_on_infocube.
    DATA(provider) = adso( ).
    provider-kind = zzxxmla1_cl_bw_provider=>c_kind-cube.
    provider-characteristics[ 1 ]-fact_column = VALUE #( name = `SID_ZFMSTORE` datatype = `INT4` length = 10 ).
    DATA(schema) = NEW zzxxmla1_cl_schema_proposal( )->propose( provider )-schema.
    DATA(key) = schema-dimensions[ 1 ]-attributes[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = key-key_column->column_name exp = `SID` ).
    cl_abap_unit_assert=>assert_equals( act = key-key_column->data_type exp = `Integer` ).
    cl_abap_unit_assert=>assert_equals( act = key-name_column->column_name exp = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_equals( act = key-name_column->data_type exp = `Numeric` ).
    DATA(usage) = CAST zzxxmla1_cl_schema_def=>ty_dimension_usage( schema-cubes[ 1 ]-dimensions[ 1 ]-def ).
    cl_abap_unit_assert=>assert_equals( act = usage->foreign_key exp = `SID_ZFMSTORE` ).
  ENDMETHOD.

  METHOD time_characteristics.
    " BW's time characteristics are characteristics like the others, on InfoCubes and aDSOs alike: each a dimension on
    " its view, joined on its fact column, none a TimeDimension; 0CALDAY has no SID table, so no view. Their attributes
    " stay hierarchies.
    DATA(adso) = adso( ).
    adso-characteristics[ 4 ]-attributes = VALUE #( ( iobjnm = `0CALMONTH2` text = `Calendar Month`
                                                      column = VALUE #( name = `CALMONTH2` datatype = `NUMC` length = 2 ) ) ).
    DATA(cube) = adso.
    cube-kind = zzxxmla1_cl_bw_provider=>c_kind-cube.
    cube-characteristics[ 4 ]-fact_column = VALUE #( name = `SID_0CALMONTH` datatype = `INT4` length = 10 ).
    DATA(adso_proposal) = NEW zzxxmla1_cl_schema_proposal( )->propose( adso ).
    DATA(cube_proposal) = NEW zzxxmla1_cl_schema_proposal( )->propose( cube ).
    DATA(names) = VALUE string_table( ( `Store` ) ( `Calendar Year/Week` ) ( `Calendar Year/Month` )
                                      ( `Calendar Year` ) ).
    cl_abap_unit_assert=>assert_equals( act = VALUE string_table( FOR d IN adso_proposal-schema-dimensions ( d-name ) )
                                        exp = names ).
    cl_abap_unit_assert=>assert_equals( act = VALUE string_table( FOR d IN cube_proposal-schema-dimensions ( d-name ) )
                                        exp = names ).
    DATA(month) = adso_proposal-schema-dimensions[ 3 ].
    cl_abap_unit_assert=>assert_equals( act = month-table exp = `ZZXXMLA1_C_0CALMONTH` ).
    cl_abap_unit_assert=>assert_initial( month-type ).
    cl_abap_unit_assert=>assert_equals( act = month-attributes[ 1 ]-key_column->column_name exp = `CALMONTH` ).
    cl_abap_unit_assert=>assert_equals( act = month-attributes[ 1 ]-key_column->data_type exp = `Integer` ).
    cl_abap_unit_assert=>assert_equals( act = month-attributes[ 2 ]-attribute_hierarchy_enabled exp = abap_undefined ).
    DATA(adso_usage) = CAST zzxxmla1_cl_schema_def=>ty_dimension_usage(
                         adso_proposal-schema-cubes[ 1 ]-dimensions[ 3 ]-def ).
    cl_abap_unit_assert=>assert_equals( act = adso_usage->foreign_key exp = `CALMONTH` ).
    DATA(cube_usage) = CAST zzxxmla1_cl_schema_def=>ty_dimension_usage(
                         cube_proposal-schema-cubes[ 1 ]-dimensions[ 3 ]-def ).
    cl_abap_unit_assert=>assert_equals( act = cube_usage->foreign_key exp = `SID_0CALMONTH` ).
    cl_abap_unit_assert=>assert_equals( act = cube_proposal-schema-dimensions[ 3 ]-attributes[ 1 ]-key_column->column_name
                                        exp = `SID` ).
    " the level types are suggestions only
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists(
      adso_proposal-suggestions[ dimension = `Calendar Year/Month` attribute = `Calendar Year/Month`
                                 level_type = `TimeMonths` ] ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists(
      adso_proposal-notes[ iobjnm = `0CALDAY` reason = `no SID table, so no view` ] ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( cube_proposal-notes[ iobjnm = `0CALDAY` ] ) ) ).
  ENDMETHOD.

  METHOD measures_and_notes.
    DATA(proposal) = NEW zzxxmla1_cl_schema_proposal( )->propose( adso( ) ).
    DATA(cube) = proposal-schema-cubes[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = cube-default_measure exp = `Unit Sales` ).
    cl_abap_unit_assert=>assert_equals( act = lines( cube-measures ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = cube-measures[ 1 ]-column exp = `/BIC/ZFMUNITS` ).
    cl_abap_unit_assert=>assert_equals( act = cube-measures[ 1 ]-aggregator exp = `sum` ).
    cl_abap_unit_assert=>assert_equals( act = cube-measures[ 2 ]-name exp = `Peak` ).
    cl_abap_unit_assert=>assert_equals( act = cube-measures[ 2 ]-aggregator exp = `max` ).
    cl_abap_unit_assert=>assert_equals(
      act = proposal-notes
      exp = VALUE zzxxmla1_cl_bw_provider=>ty_t_note( ( iobjnm = `0CURRENCY` reason = `unit or currency` )
                                                     ( iobjnm = `0CALDAY` reason = `no SID table, so no view` )
                                                     ( iobjnm = `ZFMAVG` reason = `exception aggregation AVG` )
                                                     ( iobjnm = `ZFMSTOCK` reason = `non-cumulative key figure` ) ) ).
  ENDMETHOD.

  METHOD names_are_unique.
    DATA(provider) = adso( ).
    " a second characteristic named Store, an attribute named like its dimension, two key figures of one name
    APPEND VALUE #( iobjnm = `ZFMSTORE2` text = `store` iobjtp = `CHA` has_sids = abap_true view = `ZZXXMLA1V0000009`
                    fact_column = VALUE #( name = `/BIC/ZFMSTORE2` datatype = `NUMC` length = 10 )
                    key_column = VALUE #( name = `ZFMSTORE2` datatype = `NUMC` length = 10 )
                    attributes = VALUE #( ( iobjnm = `ZFMSTORE` text = `Store`
                                            column = VALUE #( name = `ZFMSTORE` datatype = `NUMC` length = 10 ) ) ) )
      TO provider-characteristics.
    provider-key_figures[ 2 ]-text = `Unit Sales`.
    DATA(schema) = NEW zzxxmla1_cl_schema_proposal( )->propose( provider )-schema.
    cl_abap_unit_assert=>assert_equals( act = schema-dimensions[ 5 ]-name exp = `store (ZFMSTORE2)` ).
    cl_abap_unit_assert=>assert_equals( act = schema-dimensions[ 5 ]-attributes[ 1 ]-name exp = `store (ZFMSTORE2)` ).
    cl_abap_unit_assert=>assert_equals( act = schema-dimensions[ 5 ]-attributes[ 2 ]-name exp = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = schema-cubes[ 1 ]-measures[ 2 ]-name exp = `Unit Sales (ZFMPEAK)` ).
  ENDMETHOD.

  METHOD view_not_generated_yet.
    DATA(provider) = adso( ).
    CLEAR provider-characteristics[ 1 ]-view.
    DATA(schema) = NEW zzxxmla1_cl_schema_proposal( )->propose( provider )-schema.
    cl_abap_unit_assert=>assert_equals( act = schema-dimensions[ 1 ]-table exp = `ZZXXMLA1_C_ZFMSTORE` ).
  ENDMETHOD.

  METHOD suggestions.
    " a date attribute and a date key suggest TimeDays; nothing is marked as time
    DATA(provider) = adso( ).
    provider-characteristics[ 1 ]-key_column = VALUE #( name = `ZFMSTORE` datatype = `DATS` length = 8 ).
    DATA(proposal) = NEW zzxxmla1_cl_schema_proposal( )->propose( provider ).
    cl_abap_unit_assert=>assert_equals(
      act = proposal-suggestions
      exp = VALUE zzxxmla1_cl_schema_proposal=>ty_t_suggestion(
              ( dimension = `Store` attribute = `Store` level_type = `TimeDays` )
              ( dimension = `Store` attribute = `Opened` level_type = `TimeDays` )
              ( dimension = `Calendar Year/Week` attribute = `Calendar Year/Week` level_type = `TimeWeeks` )
              ( dimension = `Calendar Year/Month` attribute = `Calendar Year/Month` level_type = `TimeMonths` )
              ( dimension = `Calendar Year` attribute = `Calendar Year` level_type = `TimeYears` ) ) ).
    cl_abap_unit_assert=>assert_initial( proposal-schema-dimensions[ 1 ]-type ).
  ENDMETHOD.

  METHOD data_types.
    cl_abap_unit_assert=>assert_equals( exp = `Integer` act = zzxxmla1_cl_schema_proposal=>data_type(
      VALUE #( datatype = `NUMC` length = 9 ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Numeric` act = zzxxmla1_cl_schema_proposal=>data_type(
      VALUE #( datatype = `NUMC` length = 10 ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Integer` act = zzxxmla1_cl_schema_proposal=>data_type(
      VALUE #( datatype = `INT4` length = 10 ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = `Numeric` act = zzxxmla1_cl_schema_proposal=>data_type(
      VALUE #( datatype = `DEC` length = 17 ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = `String` act = zzxxmla1_cl_schema_proposal=>data_type(
      VALUE #( datatype = `DATS` length = 8 ) ) ).
  ENDMETHOD.

ENDCLASS.

"! The proposals for the FoodMart providers as BW has them (ZZXXMLA1_CL_BW_PROVIDER reads them; only reads).
CLASS ltc_foodmart DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    "! the InfoCube's proposal is a schema the engine reads: one dimension per characteristic, three measures
    METHODS infocube_is_read FOR TESTING RAISING cx_static_check.
    "! the aDSO's too: its time characteristics are dimensions on their views, joined on the fact columns
    METHODS adso_is_read FOR TESTING RAISING cx_static_check.
ENDCLASS.

CLASS ltc_foodmart IMPLEMENTATION.

  METHOD infocube_is_read.
    DATA(proposal) = NEW zzxxmla1_cl_schema_proposal( )->propose( NEW zzxxmla1_cl_bw_provider( )->read( 'ZFMSALES' ) ).
    cl_abap_unit_assert=>assert_initial( proposal-notes ).
    DATA(schema) = zzxxmla1_cl_schema=>of_catalogs( VALUE #( ( name = `PROPOSAL` schema = proposal-xml ) ) ).
    DATA(dimensions) = schema->dimensions( `ZFMSALES` ).
    cl_abap_unit_assert=>assert_equals( act = VALUE string_table( FOR d IN dimensions ( |{ d-dim_name } { d-key_column }| ) )
                                        exp = VALUE string_table( ( `Product SID` ) ( `Customer SID` ) ( `Store SID` )
                                                                  ( `Promotion SID` ) ( `Date SID` ) ) ).
    DATA(levels) = schema->levels( cube = `ZFMSALES` dim = `Store` hier = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = levels[ 1 ]-name_column exp = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_equals( act = lines( schema->measures( `ZFMSALES` ) ) exp = 3 ).
  ENDMETHOD.

  METHOD adso_is_read.
    DATA(proposal) = NEW zzxxmla1_cl_schema_proposal( )->propose( NEW zzxxmla1_cl_bw_provider( )->read( 'ZFMSALESA' ) ).
    cl_abap_unit_assert=>assert_equals( act = proposal-notes
                                        exp = VALUE zzxxmla1_cl_bw_provider=>ty_t_note(
                                                ( iobjnm = `0CALDAY` reason = `no SID table, so no view` ) ) ).
    DATA(schema) = zzxxmla1_cl_schema=>of_catalogs( VALUE #( ( name = `PROPOSAL` schema = proposal-xml ) ) ).
    DATA(dimensions) = schema->dimensions( `ZFMSALESA` ).
    cl_abap_unit_assert=>assert_equals( act = lines( dimensions ) exp = 8 ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( dimensions[ fk_column = `CALMONTH` key_column = `CALMONTH` ] ) ) ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists( dimensions[ dim_type = `Time` ] ) ) ).
  ENDMETHOD.

ENDCLASS.
