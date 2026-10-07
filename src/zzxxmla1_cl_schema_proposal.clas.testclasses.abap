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
"! ZFMSALESA (aDSO) and ZFMSALES (InfoCube) and the demo cube 0D_NW_C01, so no BW object is needed.
CLASS ltc_proposal DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    TYPES ty_provider TYPE zzxxmla1_cl_bw_provider=>ty_provider.

    "! a store characteristic with a text, display attributes (a name, a NUMC, a date) and a navigation attribute
    "! with a text, time characteristics, and a key figure of each kind
    METHODS adso
      RETURNING VALUE(result) TYPE ty_provider.
    METHODS dimension_of_adso FOR TESTING RAISING cx_static_check.
    METHODS hierarchies FOR TESTING RAISING cx_static_check.
    METHODS key_by_sid_on_infocube FOR TESTING RAISING cx_static_check.
    METHODS reference_characteristic FOR TESTING RAISING cx_static_check.
    METHODS time_characteristics FOR TESTING RAISING cx_static_check.
    METHODS measures_and_notes FOR TESTING RAISING cx_static_check.
    METHODS view_not_generated_yet FOR TESTING RAISING cx_static_check.
    METHODS suggestions FOR TESTING RAISING cx_static_check.
    METHODS data_types FOR TESTING.
    METHODS format_strings FOR TESTING.
ENDCLASS.

CLASS ltc_proposal IMPLEMENTATION.

  METHOD adso.
    result = VALUE #(
      name = `ZFMSALESA` kind = zzxxmla1_cl_bw_provider=>c_kind-adso text = `FoodMart Sales (aDSO)`
      fact_table = `/BIC/AZFMSALESA7`
      characteristics = VALUE #(
        ( iobjnm = `ZFMSTORE` text = `Store` iobjtp = `CHA` basic = `ZFMSTORE` has_sids = abap_true
          view = `ZZXXMLA1V0000003` text_column = `TXTMD`
          fact_column = VALUE #( name = `/BIC/ZFMSTORE` datatype = `NUMC` length = 10 )
          key_column = VALUE #( name = `ZFMSTORE` datatype = `NUMC` length = 10 )
          attributes = VALUE #( ( iobjnm = `ZFMSNAME` text = `Store Name`
                                  column = VALUE #( name = `ZFMSNAME` datatype = `CHAR` length = 60 ) )
                                ( iobjnm = `ZFMSQFT` text = `Store Sqft`
                                  column = VALUE #( name = `ZFMSQFT` datatype = `NUMC` length = 60 ) )
                                ( iobjnm = `ZFMOPEN` text = `Opened`
                                  column = VALUE #( name = `ZFMOPEN` datatype = `DATS` length = 8 ) )
                                ( iobjnm = `ZFMREGIO` text = `Region` navigation = abap_true
                                  column = VALUE #( name = `ZFMREGIO` datatype = `CHAR` length = 3 )
                                  text_column = `ZFMREGIO_TXT` ) ) )
        ( iobjnm = `0CALDAY` text = `Calendar Day` iobjtp = `TIM` basic = `0CALDAY`
          fact_column = VALUE #( name = `CALDAY` datatype = `DATS` length = 8 ) )
        ( iobjnm = `0CALWEEK` text = `Calendar Year/Week` iobjtp = `TIM` basic = `0CALWEEK` has_sids = abap_true
          fact_column = VALUE #( name = `CALWEEK` datatype = `NUMC` length = 6 )
          key_column = VALUE #( name = `CALWEEK` datatype = `NUMC` length = 6 ) )
        ( iobjnm = `0CALMONTH` text = `Calendar Year/Month` iobjtp = `TIM` basic = `0CALMONTH` has_sids = abap_true
          text_column = `TXTLG`
          fact_column = VALUE #( name = `CALMONTH` datatype = `NUMC` length = 6 )
          key_column = VALUE #( name = `CALMONTH` datatype = `NUMC` length = 6 ) )
        ( iobjnm = `0CALYEAR` text = `Calendar Year` iobjtp = `TIM` basic = `0CALYEAR` has_sids = abap_true
          fact_column = VALUE #( name = `CALYEAR` datatype = `NUMC` length = 4 )
          key_column = VALUE #( name = `CALYEAR` datatype = `NUMC` length = 4 ) ) )
      key_figures = VALUE #(
        ( iobjnm = `ZFMUNITS` text = `Unit Sales` aggregation = `SUM` exception_aggregation = `SUM`
          fact_column = VALUE #( name = `/BIC/ZFMUNITS` datatype = `QUAN` length = 17 decimals = 3 ) )
        ( iobjnm = `ZFMPEAK` text = `Peak` aggregation = `MAX` exception_aggregation = `MAX`
          fact_column = VALUE #( name = `/BIC/ZFMPEAK` datatype = `DEC` length = 17 decimals = 2 ) )
        ( iobjnm = `ZFMAVG` text = `Average` aggregation = `SUM` exception_aggregation = `AVG`
          fact_column = VALUE #( name = `/BIC/ZFMAVG` datatype = `DEC` length = 17 decimals = 2 ) )
        ( iobjnm = `ZFMSTOCK` text = `Stock` aggregation = `SUM` exception_aggregation = `SUM` non_cumulative = abap_true
          fact_column = VALUE #( name = `/BIC/ZFMSTOCK` datatype = `DEC` length = 17 decimals = 2 ) ) )
      notes = VALUE #( ( iobjnm = `0CURRENCY` reason = `unit or currency` ) ) ).
  ENDMETHOD.

  METHOD dimension_of_adso.
    DATA(schema) = NEW zzxxmla1_cl_schema_proposal( )->propose( adso( ) )-schema.
    cl_abap_unit_assert=>assert_equals( act = schema-name exp = `ZFMSALESA` ).
    " named by the InfoObject, captioned by its text
    DATA(store) = schema-dimensions[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = store-name exp = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_equals( act = store-caption exp = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = store-table exp = `ZZXXMLA1V0000003` ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR a IN store-attributes ( |{ a-name }: { a-key_column->column_name }| ) )
      exp = VALUE string_table( ( `ZFMSTORE Key: ZFMSTORE` ) ( `ZFMSTORE Text: TXTMD` ) ( `ZFMSNAME: ZFMSNAME` )
                                ( `ZFMSQFT: ZFMSQFT` ) ( `ZFMOPEN: ZFMOPEN` ) ( `ZFMSTORE__ZFMREGIO: ZFMREGIO` )
                                ( `ZFMSTORE__ZFMREGIO Text: ZFMREGIO_TXT` ) ) ).
    " the key: the characteristic's value, the column the aDSO's fact column joins
    DATA(key) = store-attributes[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = key-usage exp = `Key` ).
    cl_abap_unit_assert=>assert_equals( act = key-key_column->data_type exp = `Numeric` ).
    cl_abap_unit_assert=>assert_not_bound( key-name_column ).
    cl_abap_unit_assert=>assert_equals( act = store-attributes[ 2 ]-key_column->data_type exp = `String` ).
    " what users see are the hierarchies: no attribute is one
    LOOP AT store-attributes INTO DATA(attribute).
      cl_abap_unit_assert=>assert_equals( act = attribute-attribute_hierarchy_enabled exp = abap_false
                                          msg = attribute-name ).
    ENDLOOP.

    DATA(cube) = schema-cubes[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = cube-name exp = `ZFMSALESA` ).
    cl_abap_unit_assert=>assert_equals( act = cube-caption exp = `FoodMart Sales (aDSO)` ).
    DATA(fact) = CAST zzxxmla1_cl_schema_def=>ty_table( cube-fact-def ).
    cl_abap_unit_assert=>assert_equals( act = fact->name exp = `/BIC/AZFMSALESA7` ).
    cl_abap_unit_assert=>assert_equals( act = cube-dimensions[ 1 ]-name exp = `DimensionUsage` ).
    DATA(usage) = CAST zzxxmla1_cl_schema_def=>ty_dimension_usage( cube-dimensions[ 1 ]-def ).
    cl_abap_unit_assert=>assert_equals( act = usage->name exp = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_equals( act = usage->caption exp = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = usage->source exp = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_equals( act = usage->foreign_key exp = `/BIC/ZFMSTORE` ).
  ENDMETHOD.

  METHOD hierarchies.
    " the characteristic first and unnamed, so it is the default; display attributes are its properties, key and
    " text; the navigation attribute is a flat hierarchy of its own, named as BW names it
    DATA(schema) = NEW zzxxmla1_cl_schema_proposal( )->propose( adso( ) )-schema.
    DATA(store) = schema-dimensions[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = lines( store-hierarchies ) exp = 2 ).
    DATA(main) = store-hierarchies[ 1 ].
    cl_abap_unit_assert=>assert_initial( main-name ).
    cl_abap_unit_assert=>assert_equals( act = main-caption exp = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = main-has_all exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = main-all_member_name exp = `All Store` ).
    cl_abap_unit_assert=>assert_equals( act = lines( main-levels ) exp = 1 ).
    DATA(level) = main-levels[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = level-name exp = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_equals( act = level-caption exp = `Store` ).
    cl_abap_unit_assert=>assert_equals( act = level-source_attribute exp = `ZFMSTORE Key` ).
    cl_abap_unit_assert=>assert_equals( act = level-unique_members exp = abap_true ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR p IN level-properties ( |{ p-name }/{ p-caption }/{ p-source_attribute }| ) )
      exp = VALUE string_table( ( `Text/Store (Text)/ZFMSTORE Text` ) ( `ZFMSNAME/Store Name/ZFMSNAME` )
                                ( `ZFMSQFT/Store Sqft/ZFMSQFT` ) ( `ZFMOPEN/Opened/ZFMOPEN` ) ) ).
    DATA(region) = store-hierarchies[ 2 ].
    cl_abap_unit_assert=>assert_equals( act = region-name exp = `ZFMSTORE__ZFMREGIO` ).
    cl_abap_unit_assert=>assert_equals( act = region-caption exp = `Region` ).
    cl_abap_unit_assert=>assert_equals( act = region-all_member_name exp = `All Region` ).
    level = region-levels[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = level-name exp = `ZFMREGIO` ).
    cl_abap_unit_assert=>assert_equals( act = level-source_attribute exp = `ZFMSTORE__ZFMREGIO` ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR p IN level-properties ( |{ p-name }/{ p-source_attribute }| ) )
      exp = VALUE string_table( ( `Text/ZFMSTORE__ZFMREGIO Text` ) ) ).
    " a characteristic without text has no Text property
    DATA(week) = schema-dimensions[ 2 ].
    cl_abap_unit_assert=>assert_initial( week-hierarchies[ 1 ]-levels[ 1 ]-properties ).
    cl_abap_unit_assert=>assert_equals( act = lines( week-attributes ) exp = 1 ).
  ENDMETHOD.

  METHOD key_by_sid_on_infocube.
    DATA(provider) = adso( ).
    provider-kind = zzxxmla1_cl_bw_provider=>c_kind-cube.
    provider-characteristics[ 1 ]-fact_column = VALUE #( name = `SID_ZFMSTORE` datatype = `INT4` length = 10 ).
    DATA(schema) = NEW zzxxmla1_cl_schema_proposal( )->propose( provider )-schema.
    DATA(key) = schema-dimensions[ 1 ]-attributes[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = key-name exp = `ZFMSTORE SID` ).
    cl_abap_unit_assert=>assert_equals( act = key-key_column->column_name exp = `SID` ).
    cl_abap_unit_assert=>assert_equals( act = key-key_column->data_type exp = `Integer` ).
    cl_abap_unit_assert=>assert_equals( act = key-name_column->column_name exp = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_equals( act = key-name_column->data_type exp = `Numeric` ).
    cl_abap_unit_assert=>assert_equals( act = schema-dimensions[ 1 ]-hierarchies[ 1 ]-levels[ 1 ]-source_attribute
                                        exp = `ZFMSTORE SID` ).
    DATA(usage) = CAST zzxxmla1_cl_schema_def=>ty_dimension_usage( schema-cubes[ 1 ]-dimensions[ 1 ]-def ).
    cl_abap_unit_assert=>assert_equals( act = usage->foreign_key exp = `SID_ZFMSTORE` ).
  ENDMETHOD.

  METHOD reference_characteristic.
    " ship-to party references customer: a dimension of its own on the customer's view
    DATA(provider) = adso( ).
    provider-kind = zzxxmla1_cl_bw_provider=>c_kind-cube.
    provider-characteristics = VALUE #(
      ( iobjnm = `0D_NW_SHIP` text = `Ship-to Party` iobjtp = `CHA` basic = `0D_NW_CUST` has_sids = abap_true
        fact_column = VALUE #( name = `SID_0D_NW_SHIP` datatype = `INT4` length = 10 )
        key_column = VALUE #( name = `D_NW_CUST` datatype = `CHAR` length = 60 ) ) ).
    DATA(schema) = NEW zzxxmla1_cl_schema_proposal( )->propose( provider )-schema.
    cl_abap_unit_assert=>assert_equals( act = schema-dimensions[ 1 ]-name exp = `0D_NW_SHIP` ).
    cl_abap_unit_assert=>assert_equals( act = schema-dimensions[ 1 ]-table exp = `ZZXXMLA1_C_0D_NW_CUST` ).
    cl_abap_unit_assert=>assert_equals( act = schema-dimensions[ 1 ]-attributes[ 1 ]-name exp = `0D_NW_SHIP SID` ).
  ENDMETHOD.

  METHOD time_characteristics.
    " BW's time characteristics are characteristics like the others, on InfoCubes and aDSOs alike: each a dimension on
    " its view, joined on its fact column, none a TimeDimension; 0CALDAY has no SID table, so no view. Their attributes
    " are properties, as any characteristic's display attributes.
    DATA(adso) = adso( ).
    adso-characteristics[ 4 ]-attributes = VALUE #( ( iobjnm = `0CALMONTH2` text = `Calendar Month`
                                                      column = VALUE #( name = `CALMONTH2` datatype = `NUMC` length = 2 ) ) ).
    DATA(cube) = adso.
    cube-kind = zzxxmla1_cl_bw_provider=>c_kind-cube.
    cube-characteristics[ 4 ]-fact_column = VALUE #( name = `SID_0CALMONTH` datatype = `INT4` length = 10 ).
    DATA(adso_proposal) = NEW zzxxmla1_cl_schema_proposal( )->propose( adso ).
    DATA(cube_proposal) = NEW zzxxmla1_cl_schema_proposal( )->propose( cube ).
    DATA(names) = VALUE string_table( ( `ZFMSTORE` ) ( `0CALWEEK` ) ( `0CALMONTH` ) ( `0CALYEAR` ) ).
    cl_abap_unit_assert=>assert_equals( act = VALUE string_table( FOR d IN adso_proposal-schema-dimensions ( d-name ) )
                                        exp = names ).
    cl_abap_unit_assert=>assert_equals( act = VALUE string_table( FOR d IN cube_proposal-schema-dimensions ( d-name ) )
                                        exp = names ).
    DATA(month) = adso_proposal-schema-dimensions[ 3 ].
    cl_abap_unit_assert=>assert_equals( act = month-table exp = `ZZXXMLA1_C_0CALMONTH` ).
    cl_abap_unit_assert=>assert_initial( month-type ).
    cl_abap_unit_assert=>assert_equals( act = month-attributes[ 1 ]-key_column->column_name exp = `CALMONTH` ).
    cl_abap_unit_assert=>assert_equals( act = month-attributes[ 1 ]-key_column->data_type exp = `Integer` ).
    cl_abap_unit_assert=>assert_equals( act = lines( month-hierarchies ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR p IN month-hierarchies[ 1 ]-levels[ 1 ]-properties ( p-name ) )
      exp = VALUE string_table( ( `Text` ) ( `0CALMONTH2` ) ) ).
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
      adso_proposal-suggestions[ dimension = `0CALMONTH` attribute = `0CALMONTH Key` level_type = `TimeMonths` ] ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists(
      adso_proposal-notes[ iobjnm = `0CALDAY` reason = `no SID table, so no view` ] ) ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( cube_proposal-notes[ iobjnm = `0CALDAY` ] ) ) ).
  ENDMETHOD.

  METHOD measures_and_notes.
    DATA(proposal) = NEW zzxxmla1_cl_schema_proposal( )->propose( adso( ) ).
    DATA(cube) = proposal-schema-cubes[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = cube-default_measure exp = `ZFMUNITS` ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR m IN cube-measures
                                ( |{ m-name }/{ m-caption }/{ m-column }/{ m-aggregator }/{ m-format_string }| ) )
      exp = VALUE string_table( ( `ZFMUNITS/Unit Sales//BIC/ZFMUNITS/sum/#,##0.000` )
                                ( `ZFMPEAK/Peak//BIC/ZFMPEAK/max/#,##0.00` ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = proposal-notes
      exp = VALUE zzxxmla1_cl_bw_provider=>ty_t_note( ( iobjnm = `0CURRENCY` reason = `unit or currency` )
                                                     ( iobjnm = `0CALDAY` reason = `no SID table, so no view` )
                                                     ( iobjnm = `ZFMAVG` reason = `exception aggregation AVG` )
                                                     ( iobjnm = `ZFMSTOCK` reason = `non-cumulative key figure` ) ) ).
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
              ( dimension = `ZFMSTORE` attribute = `ZFMSTORE Key` level_type = `TimeDays` )
              ( dimension = `ZFMSTORE` attribute = `ZFMOPEN` level_type = `TimeDays` )
              ( dimension = `0CALWEEK` attribute = `0CALWEEK Key` level_type = `TimeWeeks` )
              ( dimension = `0CALMONTH` attribute = `0CALMONTH Key` level_type = `TimeMonths` )
              ( dimension = `0CALYEAR` attribute = `0CALYEAR Key` level_type = `TimeYears` ) ) ).
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

  METHOD format_strings.
    cl_abap_unit_assert=>assert_equals( exp = `#,##0` act = zzxxmla1_cl_schema_proposal=>format_string(
      VALUE #( datatype = `INT4` length = 10 ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = `#,##0` act = zzxxmla1_cl_schema_proposal=>format_string(
      VALUE #( datatype = `DEC` length = 17 ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = `#,##0.00` act = zzxxmla1_cl_schema_proposal=>format_string(
      VALUE #( datatype = `CURR` length = 17 decimals = 2 ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = `#,##0.000` act = zzxxmla1_cl_schema_proposal=>format_string(
      VALUE #( datatype = `FLTP` length = 16 decimals = 16 ) ) ).
  ENDMETHOD.

ENDCLASS.

"! The proposals for the FoodMart providers and the demo cube as BW has them (ZZXXMLA1_CL_BW_PROVIDER reads them;
"! only reads), loaded as the XMLA endpoint loads a schema.
CLASS ltc_bw DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    "! the InfoCube's proposal is a schema the engine reads: one dimension per characteristic, three measures
    METHODS infocube_is_read FOR TESTING RAISING cx_static_check.
    "! the aDSO's too: its time characteristics are dimensions on their views, joined on the fact columns
    METHODS adso_is_read FOR TESTING RAISING cx_static_check.
    "! the demo cube: navigation attributes switched on are hierarchies, the others properties; reference
    "! characteristics are on the view of the one they reference
    METHODS demo_cube FOR TESTING RAISING cx_static_check.
ENDCLASS.

CLASS ltc_bw IMPLEMENTATION.

  METHOD infocube_is_read.
    DATA(proposal) = NEW zzxxmla1_cl_schema_proposal( )->propose( NEW zzxxmla1_cl_bw_provider( )->read( 'ZFMSALES' ) ).
    cl_abap_unit_assert=>assert_initial( proposal-notes ).
    DATA(schema) = zzxxmla1_cl_schema=>of_catalogs( VALUE #( ( name = `PROPOSAL` schema = proposal-xml ) ) ).
    DATA(dimensions) = schema->dimensions( `ZFMSALES` ).
    cl_abap_unit_assert=>assert_equals( act = VALUE string_table( FOR d IN dimensions ( |{ d-dim_name } { d-key_column }| ) )
                                        exp = VALUE string_table( ( `ZFMPROD SID` ) ( `ZFMCUST SID` ) ( `ZFMSTORE SID` )
                                                                  ( `ZFMPROMO SID` ) ( `ZFMDATE SID` ) ) ).
    DATA(hierarchies) = schema->hierarchies( cube = `ZFMSALES` dim = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_equals( act = lines( hierarchies ) exp = 1 ).
    DATA(levels) = schema->levels( cube = `ZFMSALES` dim = `ZFMSTORE` hier = hierarchies[ 1 ]-hier_name ).
    cl_abap_unit_assert=>assert_equals( act = levels[ 1 ]-name_column exp = `ZFMSTORE` ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( levels[ 1 ]-properties[ name = `ZFMSNAME` ] ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( schema->measures( `ZFMSALES` ) ) exp = 3 ).
  ENDMETHOD.

  METHOD adso_is_read.
    DATA(proposal) = NEW zzxxmla1_cl_schema_proposal( )->propose( NEW zzxxmla1_cl_bw_provider( )->read( 'ZFMSALESA' ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists(
      proposal-notes[ iobjnm = `0CALDAY` reason = `no SID table, so no view` ] ) ) ).
    DATA(schema) = zzxxmla1_cl_schema=>of_catalogs( VALUE #( ( name = `PROPOSAL` schema = proposal-xml ) ) ).
    DATA(dimensions) = schema->dimensions( `ZFMSALESA` ).
    cl_abap_unit_assert=>assert_equals( act = lines( dimensions ) exp = 8 ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( dimensions[ fk_column = `CALMONTH` key_column = `CALMONTH` ] ) ) ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists( dimensions[ dim_type = `Time` ] ) ) ).
  ENDMETHOD.

  METHOD demo_cube.
    DATA(proposal) = NEW zzxxmla1_cl_schema_proposal( )->propose( NEW zzxxmla1_cl_bw_provider( )->read( '0D_NW_C01' ) ).
    DATA(code) = proposal-schema-dimensions[ name = `0D_NW_CODE` ].
    cl_abap_unit_assert=>assert_equals( act = VALUE string_table( FOR h IN code-hierarchies ( h-name ) )
                                        exp = VALUE string_table( ( `` ) ( `0D_NW_CODE__0D_NW_CNTRY` ) ) ).
    DATA(ship) = proposal-schema-dimensions[ name = `0D_NW_SHIP` ].
    cl_abap_unit_assert=>assert_equals( act = lines( ship-hierarchies ) exp = 1 ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( ship-hierarchies[ 1 ]-levels[ 1 ]-properties[ name = `0D_NW_CNTRY` ] ) ) ).
    cl_abap_unit_assert=>assert_char_cp( act = ship-table exp = 'ZZXXMLA1*' ).
    cl_abap_unit_assert=>assert_equals( act = ship-attributes[ 1 ]-name_column->column_name exp = `D_NW_CUST` ).
  ENDMETHOD.

ENDCLASS.
